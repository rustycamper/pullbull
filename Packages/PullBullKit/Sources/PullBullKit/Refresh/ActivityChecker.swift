import Foundation

/// What one activity check found.
public enum ActivityChange: Equatable, Sendable {
    /// The notifications changed since the last check: worth a full refresh now, unless the last
    /// refresh started after the change (`ActivityCheck.modifiedAt`).
    case changed
    /// Nothing new (a 304), or the first answer, which only records where to compare from.
    case unchanged
    /// This token can't read notifications (a GitHub App sign-in): don't ask again.
    case unsupported
}

public struct ActivityCheck: Equatable, Sendable {
    public let change: ActivityChange
    /// When to check next: GitHub's `X-Poll-Interval`, never under a minute.
    public let pollInterval: Duration
    /// For `.changed`: the new `Last-Modified` on this Mac's clock, or nil when it couldn't be read
    /// (then the change counts as new).
    public let modifiedAt: Date?

    public init(change: ActivityChange, pollInterval: Duration, modifiedAt: Date? = nil) {
        self.change = change
        self.pollInterval = pollInterval
        self.modifiedAt = modifiedAt
    }

    /// `Last-Modified` has whole seconds, so a change up to this long before a refresh started may
    /// have come after it.
    public static let modifiedSlack: TimeInterval = 1

    /// Whether a change at `modifiedAt` may be newer than what a refresh started at `start` read.
    /// In doubt (no time, or within the slack) it is.
    public static func isNewer(_ modifiedAt: Date?, than start: Date?) -> Bool {
        guard let modifiedAt, let start else { return true }
        return modifiedAt > start.addingTimeInterval(-modifiedSlack)
    }

    public static let minimumPollInterval: Duration = .seconds(60)

    /// `X-Poll-Interval` (seconds), floored at a minute; a minute when missing or malformed.
    public static func pollInterval(header: String?) -> Duration {
        guard let seconds = header.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else {
            return minimumPollInterval
        }
        return max(.seconds(seconds), minimumPollInterval)
    }
}

/// A cheap check for new activity between full refreshes.
public protocol ActivityChecking: Sendable {
    /// Throws what the API path throws (offline, a rate limit, a rejected token, …).
    func check() async throws -> ActivityCheck
}

/// Asks `GET /notifications` whether anything changed, conditionally on the last `Last-Modified`, so an
/// unchanged answer is a 304 that costs no rate limit. Only reads; nothing is marked read. Classic
/// tokens (`gh`, OAuth) can read notifications; a GitHub App's user token is refused (`.unsupported`).
public actor NotificationsActivityChecker: ActivityChecking {
    private let transport: any HTTPTransport
    private let auth: any TokenSource
    private let now: @Sendable () -> Date
    private var lastModified: String?

    private static let url = URL(string: "https://api.github.com/notifications")!

    public init(transport: any HTTPTransport, auth: any TokenSource, now: @escaping @Sendable () -> Date = Date.init) {
        self.transport = transport
        self.auth = auth
        self.now = now
    }

    public func check() async throws -> ActivityCheck {
        try Task.checkCancellation()
        let since = lastModified
        let (data, response) = try await Self.get(since: since, transport: transport, auth: auth)
        let poll = ActivityCheck.pollInterval(header: response.value(forHTTPHeaderField: "X-Poll-Interval"))
        if let sso = APIError.ssoRequired(in: response) { throw sso }
        switch response.statusCode {
        case 304:
            return ActivityCheck(change: .unchanged, pollInterval: poll)
        case 200..<300:
            // Without `Last-Modified` this answer says nothing; the baseline stays as it was.
            guard let modified = response.value(forHTTPHeaderField: "Last-Modified") else {
                return ActivityCheck(change: .unchanged, pollInterval: poll)
            }
            // A newer answer than the last; the first only sets where to compare from.
            let changed = since != nil && modified != since
            lastModified = modified
            guard changed else { return ActivityCheck(change: .unchanged, pollInterval: poll) }
            return ActivityCheck(
                change: .changed, pollInterval: poll,
                modifiedAt: Self.localTime(
                    of: modified, serverDate: response.value(forHTTPHeaderField: "Date"), now: now()))
        case 401:
            throw APIError.unauthorized
        case 403, 404, 429:
            if let limited = APIError.rateLimited(in: response, body: data, now: now()) { throw limited }
            return ActivityCheck(change: .unsupported, pollInterval: poll)
        default:
            throw APIError.server(response.statusCode)
        }
    }

    /// `lastModified` on this Mac's clock: shifted by how far the server's `Date` is from `now`, so a
    /// skewed clock doesn't misplace it against refresh start times. Nil when either doesn't parse
    /// (or `Date` is missing): unplaceable, so the change counts as new.
    static func localTime(of lastModified: String, serverDate: String?, now: Date) -> Date? {
        guard let modified = httpDate(lastModified), let server = serverDate.flatMap(httpDate) else { return nil }
        return modified.addingTimeInterval(now.timeIntervalSince(server))
    }

    /// An IMF-fixdate (`Tue, 27 Oct 2026 09:00:00 GMT`), the form GitHub sends.
    private static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// The GET, through the same authorized path as every other request (a 401 renews the token once).
    private static func get(
        since: String?, transport: any HTTPTransport, auth: any TokenSource
    ) async throws -> (Data, HTTPURLResponse) {
        try await sendAuthorized(with: auth) { token in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            if let since { request.setValue(since, forHTTPHeaderField: "If-Modified-Since") }
            return try await transport.send(request)
        }
    }
}
