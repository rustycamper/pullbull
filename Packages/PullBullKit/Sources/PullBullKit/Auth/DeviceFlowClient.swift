import Foundation

/// GitHub's OAuth device flow. Public client: only `client_id` is ever sent.
public struct DeviceFlowClient: Sendable {
    private static let base = URL(string: "https://github.com/login")!
    private static let deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"

    private let clientID: String
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date

    public init(clientID: String, transport: any HTTPTransport, now: @escaping @Sendable () -> Date = Date.init) {
        self.clientID = clientID
        self.transport = transport
        self.now = now
    }

    /// A 5xx is `.unexpected` (transient, worth retrying). Any other non-200 but 429, an unknown
    /// error code or a malformed body is `.misconfigured`: asking again won't help.
    public func requestCode() async throws -> DeviceCode {
        let (data, status) = try await post("device/code", ["client_id": clientID])
        if status == 429 { throw DeviceFlowError.tooManyCodes }
        if status >= 500 { throw DeviceFlowError.unexpected("HTTP \(status)") }
        do {
            let body = try decode(Wire.Envelope.self, data, status: status)
            if let error = body.error { throw failure(for: error) }
            let wire = try decode(Wire.Code.self, data, status: status)
            return DeviceCode(
                deviceCode: wire.deviceCode, userCode: wire.userCode, verificationURL: wire.verificationURI,
                expiresIn: .seconds(wire.expiresIn), interval: wire.interval)
        } catch DeviceFlowError.unexpected {
            throw DeviceFlowError.misconfigured
        }
    }

    public func poll(_ code: DeviceCode) async throws -> PollResult {
        let (data, status) = try await post(
            "oauth/access_token",
            ["client_id": clientID, "device_code": code.deviceCode, "grant_type": Self.deviceGrantType])
        let body = try decode(Wire.Envelope.self, data, status: status)
        guard let error = body.error else { return .granted(try grant(from: data, status: status)) }
        switch OAuthErrorCode(rawValue: error) {
        case .authorizationPending: return .pending
        case .slowDown: return .slowDown(interval: body.interval ?? code.interval + 5)
        default: throw failure(for: error)
        }
    }

    public func refresh(_ refreshToken: String) async throws -> TokenGrant {
        // Without the app's client ID GitHub would reject the refresh, which reads as a revoked sign-in.
        guard !clientID.isEmpty else { throw DeviceFlowError.misconfigured }
        let (data, status) = try await post(
            "oauth/access_token",
            ["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken])
        let body = try decode(Wire.Envelope.self, data, status: status)
        // A revoked authorization comes back as incorrect_client_credentials, not bad_refresh_token. The client
        // ID was already accepted at sign-in, so on a refresh it means the sign-in is gone.
        if body.error == OAuthErrorCode.incorrectClientCredentials.rawValue { throw DeviceFlowError.badRefreshToken }
        if let error = body.error { throw failure(for: error) }
        return try grant(from: data, status: status)
    }

    private func grant(from data: Data, status: Int) throws -> TokenGrant {
        let wire = try decode(Wire.Grant.self, data, status: status)
        let issued = now()
        return TokenGrant(
            accessToken: wire.accessToken,
            accessExpiresAt: wire.expiresIn.map { issued.addingTimeInterval(TimeInterval($0)) },
            refreshToken: wire.refreshToken,
            refreshExpiresAt: wire.refreshTokenExpiresIn.map { issued.addingTimeInterval(TimeInterval($0)) })
    }

    private func failure(for code: String) -> DeviceFlowError {
        switch OAuthErrorCode(rawValue: code) {
        case .expiredToken: .expired
        case .accessDenied: .denied
        case .badRefreshToken: .badRefreshToken
        case .deviceFlowDisabled, .incorrectClientCredentials, .unsupportedGrantType, .incorrectDeviceCode:
            .misconfigured
        case .authorizationPending, .slowDown, nil: .unexpected(code)
        }
    }

    /// GitHub answers OAuth errors with HTTP 200 and an `error` field, so a non-200 is unexpected.
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, status: Int) throws -> T {
        guard status == 200 else { throw DeviceFlowError.unexpected("HTTP \(status)") }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw DeviceFlowError.unexpected("malformed response")
        }
    }

    private func post(_ path: String, _ form: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.encode(form).utf8)
        do {
            let (data, response) = try await transport.send(request)
            return (data, response.statusCode)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code.meansOffline {
            throw DeviceFlowError.network
        } catch let error as URLError {
            // Reached, or may have reached, GitHub: retried like a 5xx, but never shown as offline.
            throw DeviceFlowError.unexpected(error.code.unreachableReason)
        }
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ form: [String: String]) -> String {
        func escape(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        }
        return form.sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    private enum Wire {
        /// Only the fields shared by every response; decoding it never captures a token.
        struct Envelope: Decodable {
            let error: String?
            let interval: Int?
        }

        struct Code: Decodable {
            let deviceCode: String
            let userCode: String
            let verificationURI: URL
            let expiresIn: Int
            let interval: Int

            enum CodingKeys: String, CodingKey {
                case deviceCode = "device_code"
                case userCode = "user_code"
                case verificationURI = "verification_uri"
                case expiresIn = "expires_in"
                case interval
            }
        }

        struct Grant: Decodable {
            let accessToken: String
            let expiresIn: Int?
            let refreshToken: String?
            let refreshTokenExpiresIn: Int?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case expiresIn = "expires_in"
                case refreshToken = "refresh_token"
                case refreshTokenExpiresIn = "refresh_token_expires_in"
            }
        }
    }
}
