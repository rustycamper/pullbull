import Foundation

/// Sends a request with the source's token. A 401 is reported to the source; the request is sent again,
/// once, when `rejected` says a new token is available. `URLError` becomes `APIError.network` when it
/// means no connectivity, else `APIError.unreachable`.
func sendAuthorized(
    with auth: any TokenSource,
    _ send: (String) async throws -> (Data, HTTPURLResponse)
) async throws -> (Data, HTTPURLResponse) {
    var (data, response, token) = try await attempt(auth, send)
    if response.statusCode == 401, try await auth.rejected(token) {
        try Task.checkCancellation()
        (data, response, token) = try await attempt(auth, send)
        if response.statusCode == 401 { _ = try await auth.rejected(token) }
    }
    return (data, response)
}

private func attempt(
    _ auth: any TokenSource,
    _ send: (String) async throws -> (Data, HTTPURLResponse)
) async throws -> (Data, HTTPURLResponse, String) {
    let token = try await auth.token()
    do {
        let (data, response) = try await send(token)
        return (data, response, token)
    } catch let error as APIError {
        throw error
    } catch let error as URLError {
        if error.code == .cancelled { throw CancellationError() }
        throw error.code.meansOffline ? APIError.network(error.localizedDescription) : APIError.unreachable(error.code)
    }
}

extension URLError.Code {
    /// The codes that mean no connectivity (no network, no route, no DNS, no answer), shown as offline.
    /// Any other failure reached, or may have reached, a server.
    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .callIsActive,
    ]

    private static let secureConnectionCodes: Set<URLError.Code> = [
        .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
        .clientCertificateRequired,
    ]

    public var meansOffline: Bool { Self.offlineCodes.contains(self) }

    /// Why GitHub couldn't be reached, for a code that isn't offline: "secure connection failed" (TLS or
    /// a certificate), "bad response", else "error <code>".
    public var unreachableReason: String {
        if Self.secureConnectionCodes.contains(self) { return "secure connection failed" }
        if self == .badServerResponse || self == .cannotParseResponse { return "bad response" }
        return "error \(rawValue)"
    }
}

extension APIError {
    /// `.ssoRequired` for a 403 carrying `X-GitHub-SSO: required; url=…`, else nil.
    static func ssoRequired(in response: HTTPURLResponse) -> APIError? {
        guard response.statusCode == 403,
              let header = response.value(forHTTPHeaderField: "X-GitHub-SSO"),
              header.hasPrefix("required")
        else { return nil }
        let url = header.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("url=") }
            .flatMap { URL(string: String($0.dropFirst(4))) }
        return .ssoRequired(url)
    }

    /// The wait after a rate limit that names no time.
    static let defaultRateLimitWait: TimeInterval = 60

    /// `.rateLimited` for a 429, or a 403 that GitHub marks as a rate limit (`x-ratelimit-remaining: 0`,
    /// `retry-after` or a secondary-limit message), else nil. Check `ssoRequired(in:)` first: SSO wins.
    static func rateLimited(in response: HTTPURLResponse, body: Data, now: Date) -> APIError? {
        guard response.statusCode == 403 || response.statusCode == 429 else { return nil }
        let text = String(data: body, encoding: .utf8) ?? ""
        guard response.statusCode == 429
            || response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0"
            || response.value(forHTTPHeaderField: "retry-after") != nil
            || text.localizedCaseInsensitiveContains("secondary rate limit")
        else { return nil }
        return .rateLimited(resetAt: rateLimitEnd(response, now: now))
    }

    /// When a rate limit lifts: `retry-after` (secondary limits) first, then the primary limit's
    /// `x-ratelimit-reset` once it is used up, else a minute from now.
    static func rateLimitEnd(_ response: HTTPURLResponse, now: Date) -> Date {
        if let wait = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
            return now.addingTimeInterval(wait)
        }
        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            return Date(timeIntervalSince1970: reset)
        }
        return now.addingTimeInterval(defaultRateLimitWait)
    }
}
