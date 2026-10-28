import Foundation

/// Hands `GitHubAPI` the token for one account.
public protocol TokenSource: Sendable {
    func token() async throws -> String
    /// The API got a 401 with `token`. True: retry once with `token()`. False: give up (`APIError.unauthorized`).
    /// Throws `AuthError.signedOut` when the account is now signed out.
    func rejected(_ token: String) async throws -> Bool
}

/// A fixed token, e.g. a fresh grant before its account is added. A 401 is final.
public struct StaticTokenSource: TokenSource {
    private let value: String

    public init(_ token: String) {
        value = token
    }

    public func token() async throws -> String { value }
    public func rejected(_ token: String) async throws -> Bool { false }
}
