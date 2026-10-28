import Foundation
import Security

/// Tokens for every account. GitHub App accounts come from the Keychain and are refreshed in the
/// background; `gh` accounts come from `gh auth token`. Keychain calls run on this actor, never on
/// the main actor.
public actor TokenBroker {
    /// Refresh when the access token has less than this left.
    static let refreshMargin: TimeInterval = 600

    private let store: any CredentialStore
    private let deviceFlow: DeviceFlowClient
    private let ghTokens: GhTokenCache
    private let now: @Sendable () -> Date

    /// Changes to an app account's state, in order. Single consumer.
    public nonisolated let states: AsyncStream<(AccountRef, AuthState)>
    private nonisolated let continuation: AsyncStream<(AccountRef, AuthState)>.Continuation

    private var userIDs: [String: Int64] = [:]
    private var credentials: [Int64: StoredCredential] = [:]
    private var authStates: [String: AuthState] = [:]
    private var refreshes: [Int64: Task<String, any Error>] = [:]
    /// Access tokens that came from a refresh forced by a 401; another 401 on one is a sign-out.
    private var forcedTokens: [Int64: String] = [:]
    /// Bumped by `add` and `signOut`, so a refresh started before them can't store its pair.
    private var generations: [Int64: Int] = [:]
    /// A save failed with `.unsignedBuild`: storage is unavailable whatever a later probe says.
    private var saveNeedsSignedBuild = false

    public init(
        store: any CredentialStore, deviceFlow: DeviceFlowClient, gh: GhCLI,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.deviceFlow = deviceFlow
        ghTokens = GhTokenCache(gh: gh)
        self.now = now
        (states, continuation) = AsyncStream.makeStream()
    }

    public nonisolated func source(for account: AccountRef) -> any TokenSource {
        switch account.source {
        case .gitHubApp: AppTokenSource(broker: self, account: account)
        case .gh: GhTokenSource(cache: ghTokens, login: account.login)
        }
    }

    /// The app accounts from settings, so a login can be matched to its Keychain item.
    public func register(_ accounts: [AccountSummary]) {
        for account in accounts {
            if userIDs[account.login] == nil, authStates[account.login] == .signedOut(.notFound) {
                authStates[account.login] = nil
            }
            userIDs[account.login] = account.userID
        }
    }

    /// Saves a new sign-in, replacing any credential for the same user (whose login may have
    /// changed). Throws the store's error when the save fails.
    public func add(_ grant: TokenGrant, identity: GitHubIdentity) throws -> AccountRef {
        let credential = StoredCredential(userID: identity.userID, login: identity.login, grant: grant)
        do {
            try store.save(credential)
        } catch {
            if error as? CredentialStoreError == .unsignedBuild { saveNeedsSignedBuild = true }
            throw error
        }
        let id = identity.userID
        forget(id)
        for (login, userID) in userIDs where userID == id { userIDs[login] = nil }
        userIDs[identity.login] = id
        credentials[id] = credential
        let ref = AccountRef(login: identity.login, source: .gitHubApp)
        authStates[ref.login] = .valid
        continuation.yield((ref, .valid))
        return ref
    }

    /// Deletes the account's Keychain item. `gh` logins are managed by `gh`, so this does nothing
    /// for them.
    public func signOut(_ account: AccountRef) throws {
        guard account.source == .gitHubApp else { return }
        let id = userIDs[account.login]
        // Signed out for this launch even when the delete fails; the caller reports the error.
        if let id { forget(id) }
        userIDs[account.login] = nil
        authStates[account.login] = .signedOut(.notFound)
        if let id { try store.delete(userID: id) }
    }

    /// For `gh`: drops the memoized token (scopes changed).
    public func invalidate(_ account: AccountRef) async {
        guard account.source == .gh else { return }
        await ghTokens.invalidate(account.login)
    }

    /// False when the Keychain needs a team-signed build. Each call writes and deletes a sentinel
    /// Keychain item, and the answer can't change while the app runs, so callers check once and
    /// cache it (for example the app's main-actor `canSignInWithGitHub`) rather than call it per use.
    public func isStorageAvailable() -> Bool {
        if saveNeedsSignedBuild { return false }
        do {
            try store.checkAvailable()
            return true
        } catch CredentialStoreError.unsignedBuild {
            return false
        } catch {
            return true
        }
    }

    // MARK: - App accounts

    func token(for account: AccountRef) async throws -> String {
        let credential = try credential(for: account)
        if let task = refreshes[credential.userID] { return try await task.value }
        if authStates[account.login] == .unsaved { retrySave(credential, account: account) }
        guard let expires = credential.accessExpiresAt, credential.refreshToken != nil,
            expires.addingTimeInterval(-Self.refreshMargin) < now()
        else { return credential.accessToken }
        // The refresh token is dead but the access token still works: use it until it expires.
        if let refreshExpires = credential.refreshExpiresAt, refreshExpires <= now(), expires > now() {
            return credential.accessToken
        }
        return try await refresh(credential, account: account, forced: false)
    }

    func rejected(_ token: String, for account: AccountRef) async throws -> Bool {
        let credential = try credential(for: account)
        let id = credential.userID
        if let task = refreshes[id] {
            _ = try await task.value
            return true
        }
        // A newer token exists: retry with it.
        guard token == credential.accessToken else { return true }
        if credential.refreshToken == nil || forcedTokens[id] == token {
            // A stored refresh token is kept: polling stops for this launch, the next one retries it.
            throw markSignedOut(
                account, userID: id, reason: .tokenRejected, deleteItem: credential.refreshToken == nil)
        }
        _ = try await refresh(credential, account: account, forced: true)
        return true
    }

    private func credential(for account: AccountRef) throws -> StoredCredential {
        if case .signedOut = authStates[account.login] { throw AuthError.signedOut(account) }
        guard let id = userIDs[account.login] else {
            throw markSignedOut(account, userID: nil, reason: .notFound)
        }
        if let credential = credentials[id] { return credential }
        let loaded: StoredCredential?
        do {
            loaded = try store.load(userID: id)
        } catch is DecodingError {
            // A corrupt item is unusable but stays in place: signing in again overwrites it.
            loaded = nil
        } catch CredentialStoreError.keychain(errSecDecode) {
            loaded = nil
        }
        guard let loaded else { throw markSignedOut(account, userID: nil, reason: .notFound) }
        credentials[id] = loaded
        return loaded
    }

    /// One refresh per user at a time; concurrent callers join it.
    private func refresh(_ credential: StoredCredential, account: AccountRef, forced: Bool) async throws -> String {
        let id = credential.userID
        if let task = refreshes[id] { return try await task.value }
        let task = Task { try await self.performRefresh(credential, account: account, forced: forced) }
        refreshes[id] = task
        let result = await task.result
        if refreshes[id] == task { refreshes[id] = nil }
        return try result.get()
    }

    private func performRefresh(
        _ credential: StoredCredential, account: AccountRef, forced: Bool, reloaded: Bool = false
    ) async throws -> String {
        let id = credential.userID
        guard let refreshToken = credential.refreshToken else {
            throw markSignedOut(account, userID: id, reason: .tokenRejected, deleteItem: false)
        }
        if let refreshExpires = credential.refreshExpiresAt, refreshExpires <= now() {
            return try await adoptStoredOrSignOut(
                credential, account: account, forced: forced, reloaded: reloaded, reason: .refreshExpired)
        }
        let generation = generations[id, default: 0]
        let outcome: Result<TokenGrant, any Error>
        do {
            outcome = .success(try await deviceFlow.refresh(refreshToken))
        } catch {
            outcome = .failure(error)
        }
        guard generations[id, default: 0] == generation else {
            if let current = credentials[id] { return current.accessToken }
            throw AuthError.signedOut(account)
        }
        let grant: TokenGrant
        switch outcome {
        case .success(let value):
            grant = value
        case .failure(DeviceFlowError.badRefreshToken):
            return try await adoptStoredOrSignOut(
                credential, account: account, forced: forced, reloaded: reloaded, reason: .refreshRejected)
        case .failure where !forced && credential.accessExpiresAt.map({ $0 > now() }) == true:
            // An early refresh failed, but the current token still works; the next call retries.
            return credential.accessToken
        case .failure(DeviceFlowError.network):
            throw APIError.network("Couldn't reach github.com to renew the sign-in")
        case .failure(let error):
            throw error
        }

        let updated = credential.refreshed(with: grant)
        credentials[id] = updated
        forcedTokens[id] = forced ? grant.accessToken : nil
        do {
            try store.save(updated)
            setState(.valid, for: account)
        } catch {
            // The old refresh token is spent, so keep the new pair for this launch; `token` retries the save.
            if error as? CredentialStoreError == .unsignedBuild { saveNeedsSignedBuild = true }
            setState(.unsaved, for: account)
        }
        return grant.accessToken
    }

    /// The refresh token in memory is dead. Another PullBull process sharing the Keychain item may
    /// have rotated it: adopt the stored pair, refreshing once with it if its access token has
    /// expired. Otherwise the account is signed out and the item stays, so the next launch retries
    /// it; signing in again overwrites it and Sign Out deletes it.
    private func adoptStoredOrSignOut(
        _ credential: StoredCredential, account: AccountRef, forced: Bool, reloaded: Bool,
        reason: SignOutReason
    ) async throws -> String {
        let id = credential.userID
        guard !reloaded, let stored = try? store.load(userID: id), stored.refreshToken != nil,
            stored.refreshToken != credential.refreshToken
        else { throw markSignedOut(account, userID: id, reason: reason, deleteItem: false) }
        credentials[id] = stored
        forcedTokens[id] = nil
        if stored.accessExpiresAt.map({ $0 > now() }) ?? true {
            setState(.valid, for: account)
            return stored.accessToken
        }
        return try await performRefresh(stored, account: account, forced: forced, reloaded: true)
    }

    /// Saves the in-memory pair of an `.unsaved` account again. A failure keeps it `.unsaved` and
    /// is not the caller's problem: the token in memory still works.
    private func retrySave(_ credential: StoredCredential, account: AccountRef) {
        do {
            try store.save(credential)
            setState(.valid, for: account)
        } catch {
            if error as? CredentialStoreError == .unsignedBuild { saveNeedsSignedBuild = true }
        }
    }

    /// Marks the account signed out and forgets it, if `userID` names one; its Keychain item is
    /// deleted unless `deleteItem` is false.
    private func markSignedOut(
        _ account: AccountRef, userID: Int64?, reason: SignOutReason, deleteItem: Bool = true
    ) -> AuthError {
        if let userID {
            if deleteItem { try? store.delete(userID: userID) }
            forget(userID)
        }
        setState(.signedOut(reason), for: account)
        return AuthError.signedOut(account)
    }

    private func forget(_ userID: Int64) {
        credentials[userID] = nil
        forcedTokens[userID] = nil
        refreshes[userID] = nil
        generations[userID, default: 0] += 1
    }

    /// Yields only changes; an account starts out `.valid`.
    private func setState(_ state: AuthState, for account: AccountRef) {
        guard authStates[account.login, default: .valid] != state else { return }
        authStates[account.login] = state
        continuation.yield((account, state))
    }
}

private struct AppTokenSource: TokenSource {
    let broker: TokenBroker
    let account: AccountRef

    func token() async throws -> String {
        try await broker.token(for: account)
    }

    func rejected(_ token: String) async throws -> Bool {
        try await broker.rejected(token, for: account)
    }
}
