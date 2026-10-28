import Foundation

/// A signed-in account's tokens, as kept in the Keychain. No token appears in any rendering of
/// this value; the mirror exposes only identity and expiry dates.
public struct StoredCredential: Codable, Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let userID: Int64
    public let login: String
    public let accessToken: String
    public let accessExpiresAt: Date?
    public let refreshToken: String?
    public let refreshExpiresAt: Date?

    public init(userID: Int64, login: String, grant: TokenGrant) {
        self.userID = userID
        self.login = login
        accessToken = grant.accessToken
        accessExpiresAt = grant.accessExpiresAt
        refreshToken = grant.refreshToken
        refreshExpiresAt = grant.refreshExpiresAt
    }

    /// The same account with a newly granted token pair.
    public func refreshed(with grant: TokenGrant) -> StoredCredential {
        StoredCredential(userID: userID, login: login, grant: grant)
    }

    public var description: String {
        let expires = accessExpiresAt.map { $0.formatted(.iso8601) } ?? "never"
        return "<credential login=\(login) expires=\(expires)>"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "userID": userID, "login": login,
                "accessExpiresAt": accessExpiresAt as Any, "refreshExpiresAt": refreshExpiresAt as Any,
            ], displayStyle: .struct)
    }
}
