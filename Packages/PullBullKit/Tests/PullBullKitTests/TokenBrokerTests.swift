import Foundation
import Security
import Testing
@testable import PullBullKit

private let now0 = Date(timeIntervalSince1970: 1_800_000_000)
private let octocat = AccountRef(login: "octocat", source: .gitHubApp)
private let ghRef = AccountRef(login: "octocat", source: .gh)

private final class NowBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func get() -> Date { lock.withLock { value } }
}

private struct StateEntry: Equatable {
    let ref: AccountRef
    let state: AuthState
}

/// Holds callers until released. Arrival and parking happen under one lock, and releases are
/// counted, so a `release()` that comes before its caller parks is never lost.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var arrived = 0
    private var permits = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    var arrivals: Int { lock.withLock { arrived } }

    func enter() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let (ready, pass) = lock.withLock { () -> ([CheckedContinuation<Void, Never>], Bool) in
                arrived += 1
                let ready = arrivalWaiters.filter { $0.count <= arrived }.map(\.continuation)
                arrivalWaiters.removeAll { $0.count <= arrived }
                if permits > 0 {
                    permits -= 1
                    return (ready, true)
                }
                parked.append(continuation)
                return (ready, false)
            }
            ready.forEach { $0.resume() }
            if pass { continuation.resume() }
        }
    }

    func waitForArrivals(_ n: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = lock.withLock { () -> Bool in
                if arrived >= n { return true }
                arrivalWaiters.append((n, continuation))
                return false
            }
            if done { continuation.resume() }
        }
    }

    /// Lets one caller through, now or when it arrives.
    func release() {
        let next = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if parked.isEmpty {
                permits += 1
                return nil
            }
            return parked.removeFirst()
        }
        next?.resume()
    }
}

/// `gh` stand-in that answers `auth token` with `tokens` in turn (the last one repeats). When
/// gated, each run waits for `release()`.
private final class GhRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let tokens: [String]
    private let gate: Gate?
    private var count = 0

    init(tokens: [String], gated: Bool = false) {
        self.tokens = tokens
        gate = gated ? Gate() : nil
    }

    var runs: Int { lock.withLock { count } }

    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        let index = lock.withLock { () -> Int in
            count += 1
            return count - 1
        }
        await gate?.enter()
        return (0, Data((tokens[min(index, tokens.count - 1)] + "\n").utf8), Data())
    }

    func waitForRuns(_ n: Int) async {
        await gate?.waitForArrivals(n)
    }

    func release() {
        gate?.release()
    }
}

/// Holds each request at `gate` before the fake server answers it, so a refresh can be kept in flight.
private struct GatedTransport: HTTPTransport {
    let inner: FakeGitHubOAuth
    let gate: Gate

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await gate.enter()
        return try await inner.send(request)
    }
}

/// Records how many saves the store holds at the moment each response comes back from the server.
private final class SaveCountProbe: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let inner: FakeGitHubOAuth
    private let store: InMemoryCredentialStore
    private var counts: [Int] = []

    init(_ inner: FakeGitHubOAuth, store: InMemoryCredentialStore) {
        self.inner = inner
        self.store = store
    }

    var savesAtResponse: [Int] { lock.withLock { counts } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = try await inner.send(request)
        let saves = store.saved.count
        lock.withLock { counts.append(saves) }
        return response
    }
}

private struct Harness {
    let store = InMemoryCredentialStore()
    let fake = FakeGitHubOAuth(validRefreshTokens: ["ghr_1"])
    let runner: GhRunner
    let broker: TokenBroker

    init(
        accessExpiresAt: Date? = now0 + 3600, refreshToken: String? = "ghr_1",
        refreshExpiresAt: Date? = now0 + 86_400 * 30, seed: Bool = true,
        transport: ((FakeGitHubOAuth, InMemoryCredentialStore) -> any HTTPTransport)? = nil,
        runner: GhRunner = GhRunner(tokens: ["gho_1"])
    ) async {
        if seed {
            store.items[1] = StoredCredential(
                userID: 1, login: "octocat",
                grant: TokenGrant(
                    accessToken: "ghu_1", accessExpiresAt: accessExpiresAt, refreshToken: refreshToken,
                    refreshExpiresAt: refreshExpiresAt))
        }
        self.runner = runner
        let clock = NowBox(now0)
        let transport = transport?(fake, store) ?? fake
        broker = TokenBroker(
            store: store,
            deviceFlow: DeviceFlowClient(clientID: "Iv23test", transport: transport, now: { clock.get() }),
            gh: GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true }),
            now: { clock.get() })
        if seed { await broker.register([AccountSummary(userID: 1, login: "octocat")]) }
    }

    var app: any TokenSource { broker.source(for: octocat) }

    /// Plays a second PullBull process: refreshes the stored pair and saves the result, behind the
    /// broker's back. `accessExpiresAt` overrides the new access token's expiry.
    func rotateInOtherProcess(accessExpiresAt: Date? = nil) async throws {
        let stored = try #require(store.items[1])
        let other = DeviceFlowClient(clientID: "Iv23test", transport: fake, now: { now0 })
        let grant = try await other.refresh(try #require(stored.refreshToken))
        store.items[1] = stored.refreshed(
            with: TokenGrant(
                accessToken: grant.accessToken, accessExpiresAt: accessExpiresAt ?? grant.accessExpiresAt,
                refreshToken: grant.refreshToken, refreshExpiresAt: grant.refreshExpiresAt))
    }

    var refreshRequests: Int {
        get async { await fake.requests.filter { $0.form["grant_type"] == "refresh_token" }.count }
    }

    /// Every state yielded so far: adds a sentinel account, whose `.valid` marks the end.
    func statesSoFar() async throws -> [StateEntry] {
        _ = try await broker.add(
            TokenGrant(accessToken: "ghu_s", accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil),
            identity: GitHubIdentity(login: "sentinel", userID: 999, avatarURL: nil))
        var entries: [StateEntry] = []
        for await (ref, state) in broker.states {
            if ref.login == "sentinel" { break }
            entries.append(StateEntry(ref: ref, state: state))
        }
        return entries
    }
}

@Suite struct TokenBrokerTests {
    @Test func validTokenIsReturnedWithoutRefresh() async throws {
        let h = await Harness()
        #expect(try await h.app.token() == "ghu_1")
        #expect(await h.fake.requests.isEmpty)
    }

    @Test func proactiveRefreshInsideTenMinutes() async throws {
        let h = await Harness(accessExpiresAt: now0 + 599)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 1)
        let saved = try #require(h.store.saved.last)
        #expect(saved.accessToken == "ghu_rotated1")
        #expect(saved.refreshToken == "ghr_rotated1")
        #expect(saved.userID == 1)
        #expect(saved.login == "octocat")
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let h = await Harness(accessExpiresAt: now0 + 60)
        let app = h.app
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await app.token() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(tokens == Array(repeating: "ghu_rotated1", count: 10))
        #expect(await h.refreshRequests == 1)
    }

    @Test func rotatedPairIsSavedBeforeReturn() async throws {
        var probe: SaveCountProbe?
        let h = await Harness(accessExpiresAt: now0 - 1) { fake, store in
            let p = SaveCountProbe(fake, store: store)
            probe = p
            return p
        }
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(probe?.savesAtResponse == [0])
        #expect(h.store.saved.count == 1)
    }

    @Test func badRefreshTokenSignsOutAndKeepsTheItem() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1, refreshToken: "ghr_revoked")
        let before = h.store.items[1]
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        // The spec keeps the item: the next launch retries it, and Sign Out deletes it.
        #expect(h.store.items[1] == before)
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        #expect(await h.refreshRequests == 1)
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .signedOut(.refreshRejected))])
    }

    @Test func expiredRefreshTokenSignsOutWithoutRequest() async throws {
        let h = await Harness(accessExpiresAt: now0 - 60, refreshExpiresAt: now0 - 1)
        let before = h.store.items[1]
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        #expect(await h.fake.requests.isEmpty)
        #expect(h.store.items[1] == before)
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .signedOut(.refreshExpired))])
    }

    /// Another PullBull process sharing the item rotated the pair: the stale refresh token is rejected,
    /// and the broker adopts the stored pair instead of signing out.
    @Test func rejectedRefreshAdoptsANewerStoredPair() async throws {
        let h = await Harness()
        #expect(try await h.app.token() == "ghu_1")
        try await h.rotateInOtherProcess()
        #expect(try await h.app.rejected("ghu_1"))
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 2)
        #expect(h.store.items[1]?.refreshToken == "ghr_rotated1")
        #expect(try await h.statesSoFar() == [])
    }

    @Test func rejectedRefreshRefreshesOnceWithAnExpiredStoredPair() async throws {
        let h = await Harness()
        #expect(try await h.app.token() == "ghu_1")
        try await h.rotateInOtherProcess(accessExpiresAt: now0 - 1)
        #expect(try await h.app.rejected("ghu_1"))
        #expect(try await h.app.token() == "ghu_rotated2")
        #expect(await h.refreshRequests == 3)
        #expect(h.store.items[1]?.refreshToken == "ghr_rotated2")
        #expect(try await h.statesSoFar() == [])
    }

    @Test func expiredRefreshTokenAdoptsANewerStoredPair() async throws {
        let h = await Harness(refreshExpiresAt: now0 - 1)
        #expect(try await h.app.token() == "ghu_1")
        try await h.rotateInOtherProcess()
        #expect(try await h.app.rejected("ghu_1"))
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 1)
        #expect(try await h.statesSoFar() == [])
    }

    @Test func networkErrorDuringRefreshKeepsAccount() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1)
        let before = h.store.items[1]
        await h.fake.failNext(URLError(.notConnectedToInternet))
        await #expect {
            try await h.app.token()
        } throws: { error in
            if case APIError.network = error { return true }
            return false
        }
        #expect(h.store.items[1] == before)
        #expect(h.store.saved.isEmpty)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 2)
        #expect(try await h.statesSoFar() == [])
    }

    @Test func signOutDuringRefreshSavesNothing() async throws {
        let gate = Gate()
        let h = await Harness(accessExpiresAt: now0 - 1) { fake, _ in GatedTransport(inner: fake, gate: gate) }
        let app = h.app
        let inFlight = Task { try await app.token() }
        await gate.waitForArrivals(1)
        let joiner = Task { try await app.token() }
        try await h.broker.signOut(octocat)
        gate.release()
        await #expect(throws: AuthError.signedOut(octocat)) { try await inFlight.value }
        await #expect(throws: AuthError.signedOut(octocat)) { try await joiner.value }
        #expect(h.store.items[1] == nil)
        #expect(h.store.saved.isEmpty)
        #expect(gate.arrivals == 1)
    }

    @Test func addDuringRefreshKeepsTheNewGrant() async throws {
        let gate = Gate()
        let h = await Harness(accessExpiresAt: now0 - 1) { fake, _ in GatedTransport(inner: fake, gate: gate) }
        let app = h.app
        let inFlight = Task { try await app.token() }
        await gate.waitForArrivals(1)
        _ = try await h.broker.add(
            TokenGrant(accessToken: "ghu_new", accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil),
            identity: GitHubIdentity(login: "octocat", userID: 1, avatarURL: nil))
        gate.release()
        #expect(try await inFlight.value == "ghu_new")
        #expect(h.store.saved.map(\.accessToken) == ["ghu_new"])
        #expect(h.store.items[1]?.accessToken == "ghu_new")
        #expect(try await app.token() == "ghu_new")
    }

    @Test func failedEarlyRefreshKeepsTheCurrentToken() async throws {
        let h = await Harness(accessExpiresAt: now0 + 300)
        let before = h.store.items
        await h.fake.failNext(URLError(.notConnectedToInternet))
        #expect(try await h.app.token() == "ghu_1")
        #expect(h.store.items == before)
        #expect(h.store.saved.isEmpty)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 2)
        #expect(try await h.statesSoFar() == [])
    }

    @Test func lockedKeychainIsNotSignOut() async throws {
        let h = await Harness()
        let before = h.store.items
        h.store.loadError = .locked
        await #expect(throws: CredentialStoreError.locked) { try await h.app.token() }
        #expect(h.store.items == before)
        h.store.loadError = nil
        #expect(try await h.app.token() == "ghu_1")
        #expect(try await h.statesSoFar() == [])
    }

    @Test func corruptItemIsSignedOutWithoutDeleting() async throws {
        let h = await Harness()
        let before = h.store.items
        h.store.corruptUserIDs = [1]
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        #expect(h.store.items == before)
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .signedOut(.notFound))])
    }

    @Test func undecodableKeychainDataIsSignedOutWithoutDeleting() async throws {
        let h = await Harness()
        let before = h.store.items
        h.store.loadError = .keychain(errSecDecode)
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        #expect(h.store.items == before)
    }

    @Test func otherKeychainErrorsAreNotSignOut() async throws {
        let h = await Harness()
        h.store.loadError = .keychain(-1)
        await #expect(throws: CredentialStoreError.keychain(-1)) { try await h.app.token() }
        h.store.loadError = nil
        #expect(try await h.app.token() == "ghu_1")
        #expect(try await h.statesSoFar() == [])
    }

    @Test func nonExpiringCredentialNeverRefreshes() async throws {
        let h = await Harness(accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil)
        #expect(try await h.app.token() == "ghu_1")
        #expect(try await h.app.token() == "ghu_1")
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.rejected("ghu_1") }
        #expect(await h.fake.requests.isEmpty)
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .signedOut(.tokenRejected))])
    }

    @Test func rejectedCurrentTokenRefreshesOnce() async throws {
        let h = await Harness()
        #expect(try await h.app.rejected("ghu_1"))
        #expect(try await h.app.token() == "ghu_rotated1")
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.rejected("ghu_rotated1") }
        #expect(await h.refreshRequests == 1)
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .signedOut(.tokenRejected))])
    }

    @Test func rejectionAfterForcedRefreshKeepsTheItem() async throws {
        let h = await Harness()
        #expect(try await h.app.rejected("ghu_1"))
        #expect(try await h.app.token() == "ghu_rotated1")
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.rejected("ghu_rotated1") }
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .signedOut(.tokenRejected))])
        // The next launch retries with the stored, rotated refresh token.
        let kept = try #require(h.store.items[1])
        #expect(kept.accessToken == "ghu_rotated1")
        #expect(kept.refreshToken == "ghr_rotated1")
    }

    @Test func expiredRefreshTokenWithLiveAccessTokenUsesIt() async throws {
        let h = await Harness(accessExpiresAt: now0 + 300, refreshExpiresAt: now0 - 1)
        #expect(try await h.app.token() == "ghu_1")
        #expect(try await h.app.token() == "ghu_1")
        #expect(await h.fake.requests.isEmpty)
        #expect(try await h.statesSoFar() == [])
    }

    @Test func staleRejectionRetriesWithoutRefresh() async throws {
        let h = await Harness(accessExpiresAt: now0 + 10)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(try await h.app.rejected("ghu_1"))
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 1)
    }

    @Test func concurrentRejectionsShareOneRefresh() async throws {
        let h = await Harness()
        let app = h.app
        let answers = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<6 { group.addTask { try await app.rejected("ghu_1") } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(answers == Array(repeating: true, count: 6))
        #expect(await h.refreshRequests == 1)
    }

    @Test func saveFailureKeepsPairInMemory() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1)
        h.store.saveError = .keychain(-1)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.refreshRequests == 1)
        #expect(await h.broker.isStorageAvailable())
        h.store.saveError = nil
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .unsaved)])
    }

    @Test func unsavedPairIsSavedOnTheNextToken() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1)
        h.store.saveError = .keychain(-1)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(h.store.saved.isEmpty)
        h.store.saveError = nil
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(h.store.saved.map(\.accessToken) == ["ghu_rotated1"])
        #expect(h.store.items[1]?.refreshToken == "ghr_rotated1")
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(h.store.saved.count == 1)
        #expect(await h.refreshRequests == 1)
        #expect(
            try await h.statesSoFar() == [
                StateEntry(ref: octocat, state: .unsaved), StateEntry(ref: octocat, state: .valid),
            ])
    }

    @Test func unsavedRetryFailureStaysUnsavedWithoutThrowing() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1)
        h.store.saveError = .keychain(-1)
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(h.store.saved.isEmpty)
        h.store.saveError = nil
        #expect(try await h.statesSoFar().first == StateEntry(ref: octocat, state: .unsaved))
    }

    @Test func unsignedBuildOnRefreshSaveIsReported() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1)
        h.store.saveError = .unsignedBuild
        #expect(try await h.app.token() == "ghu_rotated1")
        #expect(await h.broker.isStorageAvailable() == false)
        h.store.saveError = nil
        #expect(try await h.statesSoFar() == [StateEntry(ref: octocat, state: .unsaved)])
    }

    @Test func addSurfacesUnsignedBuild() async throws {
        let h = await Harness(seed: false)
        h.store.saveError = .unsignedBuild
        await #expect(throws: CredentialStoreError.unsignedBuild) {
            try await h.broker.add(
                TokenGrant(accessToken: "ghu_9", accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil),
                identity: GitHubIdentity(login: "octocat", userID: 1, avatarURL: nil))
        }
        #expect(await h.broker.isStorageAvailable() == false)
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
    }

    @Test func storageIsAvailableUnlessUnsigned() async {
        let h = await Harness()
        #expect(await h.broker.isStorageAvailable())
        h.store.probeError = .locked
        #expect(await h.broker.isStorageAvailable())
        h.store.probeError = .keychain(-1)
        #expect(await h.broker.isStorageAvailable())
        h.store.probeError = .unsignedBuild
        #expect(await h.broker.isStorageAvailable() == false)
    }

    /// An unsigned host answers reads with errSecItemNotFound, so only the write probe sees it.
    @Test func unsignedProbeIsUnavailableWhileReadsWork() async throws {
        let h = await Harness()
        h.store.probeError = .unsignedBuild
        #expect(await h.broker.isStorageAvailable() == false)
        #expect(try await h.app.token() == "ghu_1")
    }

    @Test func addSameUserReplacesCredential() async throws {
        let h = await Harness(seed: false)
        let first = try await h.broker.add(
            TokenGrant(accessToken: "ghu_a", accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil),
            identity: GitHubIdentity(login: "octocat", userID: 1, avatarURL: nil))
        #expect(first == octocat)
        let renamed = try await h.broker.add(
            TokenGrant(accessToken: "ghu_b", accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil),
            identity: GitHubIdentity(login: "octocat-renamed", userID: 1, avatarURL: nil))
        #expect(renamed == AccountRef(login: "octocat-renamed", source: .gitHubApp))
        #expect(h.store.items.count == 1)
        #expect(h.store.items[1]?.login == "octocat-renamed")
        #expect(h.store.items[1]?.accessToken == "ghu_b")
        #expect(try await h.broker.source(for: renamed).token() == "ghu_b")
    }

    @Test func addAfterSignOutSignsBackIn() async throws {
        let h = await Harness(accessExpiresAt: now0 - 1, refreshToken: "ghr_revoked")
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
        _ = try await h.broker.add(
            TokenGrant(accessToken: "ghu_new", accessExpiresAt: nil, refreshToken: nil, refreshExpiresAt: nil),
            identity: GitHubIdentity(login: "octocat", userID: 1, avatarURL: nil))
        #expect(try await h.app.token() == "ghu_new")
        #expect(
            try await h.statesSoFar() == [
                StateEntry(ref: octocat, state: .signedOut(.refreshRejected)),
                StateEntry(ref: octocat, state: .valid),
            ])
    }

    @Test func unregisteredAppAccountIsSignedOut() async throws {
        let h = await Harness()
        let stranger = AccountRef(login: "stranger", source: .gitHubApp)
        await #expect(throws: AuthError.signedOut(stranger)) { try await h.broker.source(for: stranger).token() }
        #expect(try await h.statesSoFar() == [StateEntry(ref: stranger, state: .signedOut(.notFound))])
    }

    @Test func signOutDeletesItem() async throws {
        let h = await Harness()
        #expect(try await h.app.token() == "ghu_1")
        try await h.broker.signOut(octocat)
        #expect(h.store.items[1] == nil)
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
    }

    @Test func failedDeleteStillSignsOutInMemory() async throws {
        let h = await Harness()
        #expect(try await h.app.token() == "ghu_1")
        h.store.deleteError = .keychain(-25293)
        await #expect(throws: CredentialStoreError.keychain(-25293)) { try await h.broker.signOut(octocat) }
        // The item is still there, but this launch no longer hands out its token.
        #expect(h.store.items[1] != nil)
        await #expect(throws: AuthError.signedOut(octocat)) { try await h.app.token() }
    }

    @Test func staticSourceNeverRetries() async throws {
        let source = StaticTokenSource("tok")
        #expect(try await source.token() == "tok")
        #expect(try await source.rejected("tok") == false)
    }

    @Test func ghSourceMemoizes() async throws {
        let h = await Harness()
        let gh = h.broker.source(for: ghRef)
        #expect(try await gh.token() == "gho_1")
        #expect(try await gh.token() == "gho_1")
        #expect(h.runner.runs == 1)
    }

    @Test func ghRejectedRetriesOnceThenGivesUp() async throws {
        let h = await Harness()
        let gh = h.broker.source(for: ghRef)
        let token = try await gh.token()
        #expect(try await gh.rejected(token))
        #expect(try await gh.token() == token)
        #expect(h.runner.runs == 2)
        #expect(try await gh.rejected(token) == false)
    }

    @Test func ghInvalidateDropsInFlight() async throws {
        let h = await Harness(runner: GhRunner(tokens: ["gho_old", "gho_new"], gated: true))
        let gh = h.broker.source(for: ghRef)
        let inFlight = Task { try await gh.token() }
        await h.runner.waitForRuns(1)
        await h.broker.invalidate(ghRef)
        h.runner.release()
        #expect(try await inFlight.value == "gho_old")
        let next = Task { try await gh.token() }
        await h.runner.waitForRuns(2)
        h.runner.release()
        #expect(try await next.value == "gho_new")
        #expect(h.runner.runs == 2)
    }
}
