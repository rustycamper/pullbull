import Foundation

public enum AccountSource: String, Codable, Sendable {
    case gitHubApp, gh
}

/// An account PullBull polls as: a login, and where its token comes from.
public struct AccountRef: Hashable, Codable, Sendable {
    public let login: String
    public let source: AccountSource

    public init(login: String, source: AccountSource) {
        self.login = login
        self.source = source
    }
}

/// A GitHub App account as kept in settings. The user ID names its Keychain item; the login can
/// change on GitHub.
public struct AccountSummary: Hashable, Codable, Sendable {
    public let userID: Int64
    public let login: String
    /// From sign-in; nil in summaries saved before it was kept. A public image URL, not a secret.
    public let avatarURL: URL?

    public init(userID: Int64, login: String, avatarURL: URL? = nil) {
        self.userID = userID
        self.login = login
        self.avatarURL = avatarURL
    }

    public var ref: AccountRef { AccountRef(login: login, source: .gitHubApp) }
}

/// Who a token belongs to, from `GET /user`.
public struct GitHubIdentity: Sendable, Equatable {
    public let login: String
    public let userID: Int64
    public let avatarURL: URL?

    public init(login: String, userID: Int64, avatarURL: URL?) {
        self.login = login
        self.userID = userID
        self.avatarURL = avatarURL
    }
}

public enum SignOutReason: Sendable, Equatable {
    /// GitHub answered the refresh with `bad_refresh_token`.
    case refreshRejected
    /// The refresh token's own expiry has passed.
    case refreshExpired
    /// The API rejected a token that can't be refreshed again.
    case tokenRejected
    /// No usable Keychain item: never added, signed out, or unreadable.
    case notFound
}

public enum AuthState: Sendable, Equatable {
    case valid
    /// Refreshed, but the Keychain save failed: valid this launch only.
    case unsaved
    case signedOut(SignOutReason)
}

public enum AuthError: Error, Sendable, Equatable {
    case signedOut(AccountRef)
}
