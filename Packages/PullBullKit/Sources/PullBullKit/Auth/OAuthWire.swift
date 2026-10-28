import Foundation

/// A pending device authorization. `deviceCode` is a credential for the poll endpoint and never
/// appears in any rendering of this value.
public struct DeviceCode: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: Duration
    /// Seconds between polls.
    public let interval: Int

    public init(deviceCode: String, userCode: String, verificationURL: URL, expiresIn: Duration, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }

    public var description: String { "<device code user=\(userCode)>" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "userCode": userCode, "verificationURL": verificationURL,
                "expiresIn": expiresIn, "interval": interval,
            ], displayStyle: .struct)
    }
}

/// Tokens from GitHub. Neither token appears in any rendering of this value; the mirror exposes
/// only the expiry dates.
public struct TokenGrant: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let accessToken: String
    public let accessExpiresAt: Date?
    public let refreshToken: String?
    public let refreshExpiresAt: Date?

    public init(accessToken: String, accessExpiresAt: Date?, refreshToken: String?, refreshExpiresAt: Date?) {
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
        self.refreshExpiresAt = refreshExpiresAt
    }

    public var description: String {
        "<grant expires=\(accessExpiresAt.map { "\($0)" } ?? "never")>"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["accessExpiresAt": accessExpiresAt as Any, "refreshExpiresAt": refreshExpiresAt as Any],
            displayStyle: .struct)
    }
}

public enum PollResult: Sendable, Equatable {
    case pending
    case slowDown(interval: Int)
    case granted(TokenGrant)
}

public enum OAuthErrorCode: String, Sendable {
    case authorizationPending = "authorization_pending"
    case slowDown = "slow_down"
    case expiredToken = "expired_token"
    case accessDenied = "access_denied"
    case deviceFlowDisabled = "device_flow_disabled"
    case incorrectClientCredentials = "incorrect_client_credentials"
    case incorrectDeviceCode = "incorrect_device_code"
    case unsupportedGrantType = "unsupported_grant_type"
    case badRefreshToken = "bad_refresh_token"
}

public enum DeviceFlowError: Error, Equatable, Sendable {
    case expired
    case denied
    case tooManyCodes
    case misconfigured
    case badRefreshToken
    /// No connectivity (`URLError.Code.meansOffline`).
    case network
    /// Carries only an error code, "HTTP <status>", "malformed response" or a transport failure's
    /// `URLError.Code.unreachableReason`, never a response body.
    case unexpected(String)
}
