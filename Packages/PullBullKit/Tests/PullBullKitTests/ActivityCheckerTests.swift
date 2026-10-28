import Foundation
import Testing
@testable import PullBullKit

private struct Reply {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
}

private actor StubHTTP: HTTPTransport {
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let reply = replies.count > 1 ? replies.removeFirst() : replies[0]
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (reply.body, response)
    }
}

private struct FailingHTTP: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
}

private actor CountingSource: TokenSource {
    private(set) var rejectedTokens: [String] = []
    func token() async throws -> String { "t" }
    func rejected(_ token: String) async throws -> Bool {
        rejectedTokens.append(token)
        return false
    }
}

private let monday = "Mon, 26 Oct 2026 10:00:00 GMT"
private let tuesday = "Tue, 27 Oct 2026 09:00:00 GMT"

private func modified(_ date: String, poll: String? = "60") -> Reply {
    var headers = ["Last-Modified": date]
    if let poll { headers["X-Poll-Interval"] = poll }
    return Reply(headers: headers, body: Data("[]".utf8))
}

private let notModified = Reply(status: 304, headers: ["X-Poll-Interval": "60"])

private func checker(_ http: any HTTPTransport, auth: any TokenSource = StaticTokenSource("t"))
    -> NotificationsActivityChecker {
    NotificationsActivityChecker(transport: http, auth: auth)
}

@Suite struct ActivityCheckerTests {
    @Test func firstAnswerIsTheBaselineThenA304IsUnchanged() async throws {
        let http = StubHTTP([modified(monday), notModified])
        let activity = checker(http)
        #expect(try await activity.check() == ActivityCheck(change: .unchanged, pollInterval: .seconds(60)))
        #expect(try await activity.check() == ActivityCheck(change: .unchanged, pollInterval: .seconds(60)))
        let requests = await http.requests
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "If-Modified-Since") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "If-Modified-Since") == monday)
    }

    @Test func readsNotificationsWithDefaultParamsAndNeverWrites() async throws {
        let http = StubHTTP([modified(monday)])
        _ = try await checker(http).check()
        let request = try #require(await http.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.github.com/notifications")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.httpBody == nil)
    }

    @Test func aNewLastModifiedIsChanged() async throws {
        let http = StubHTTP([modified(monday), notModified, modified(tuesday), notModified])
        let activity = checker(http)
        #expect(try await activity.check().change == .unchanged)
        #expect(try await activity.check().change == .unchanged)
        #expect(try await activity.check().change == .changed)
        #expect(try await activity.check().change == .unchanged)
        #expect(await http.requests.last?.value(forHTTPHeaderField: "If-Modified-Since") == tuesday)
    }

    @Test func sameLastModifiedIsUnchanged() async throws {
        let activity = checker(StubHTTP([modified(monday), modified(monday)]))
        _ = try await activity.check()
        #expect(try await activity.check().change == .unchanged)
    }

    @Test func pollIntervalHonouredAndFlooredAtAMinute() async throws {
        let activity = checker(StubHTTP([modified(monday, poll: "120"), modified(monday, poll: "30"), modified(monday, poll: nil)]))
        #expect(try await activity.check().pollInterval == .seconds(120))
        #expect(try await activity.check().pollInterval == .seconds(60))
        #expect(try await activity.check().pollInterval == .seconds(60))
        #expect(ActivityCheck.pollInterval(header: "abc") == .seconds(60))
        #expect(ActivityCheck.pollInterval(header: " 90 ") == .seconds(90))
    }

    @Test(arguments: [403, 404])
    func forbiddenOrMissingIsUnsupported(status: Int) async throws {
        let activity = checker(StubHTTP([Reply(status: status, body: Data(#"{"message":"Resource not accessible by integration"}"#.utf8))]))
        #expect(try await activity.check().change == .unsupported)
    }

    @Test func noLastModifiedSaysNothingAndKeepsNoBaseline() async throws {
        let bare = Reply(headers: [:], body: Data("[]".utf8))
        let http = StubHTTP([bare, modified(monday), bare, modified(tuesday)])
        let activity = checker(http)
        #expect(try await activity.check().change == .unchanged)
        // The next answer is the baseline, not a change.
        #expect(try await activity.check().change == .unchanged)
        #expect(try await activity.check().change == .unchanged)
        #expect(try await activity.check().change == .changed)
        let since = await http.requests.map { $0.value(forHTTPHeaderField: "If-Modified-Since") }
        #expect(since == [nil, nil, monday, monday])
    }

    @Test func changedCarriesLastModifiedOnTheLocalClock() async throws {
        // The server's clock reads 09:00:30 when this Mac's reads 10:00:30: an hour behind.
        let local = Date(timeIntervalSince1970: 1_793_095_230)
        var reply = modified(tuesday)
        reply.headers["Date"] = "Tue, 27 Oct 2026 09:00:30 GMT"
        let activity = NotificationsActivityChecker(
            transport: StubHTTP([modified(monday), reply]), auth: StaticTokenSource("t"), now: { local })
        _ = try await activity.check()
        let check = try await activity.check()
        #expect(check.change == .changed)
        #expect(check.modifiedAt == local.addingTimeInterval(-30))
    }

    @Test func modifiedTimeIsUnknownWithoutAUsableServerDate() {
        let now = Date(timeIntervalSince1970: 0)
        let server = "Tue, 27 Oct 2026 09:00:30 GMT"
        #expect(NotificationsActivityChecker.localTime(of: tuesday, serverDate: server, now: now)
            == Date(timeIntervalSince1970: -30))
        #expect(NotificationsActivityChecker.localTime(of: tuesday, serverDate: nil, now: now) == nil)
        #expect(NotificationsActivityChecker.localTime(of: tuesday, serverDate: "soon", now: now) == nil)
        #expect(NotificationsActivityChecker.localTime(of: "yesterday", serverDate: server, now: now) == nil)
    }

    @Test func changedWithoutServerDateHasNoTime() async throws {
        let activity = checker(StubHTTP([modified(monday), modified(tuesday)]))
        _ = try await activity.check()
        let check = try await activity.check()
        #expect(check.change == .changed)
        #expect(check.modifiedAt == nil)
    }

    @Test func newerAllowsASecondOfSlackAndRefreshesWhenUnsure() {
        let start = Date(timeIntervalSince1970: 1_000)
        #expect(!ActivityCheck.isNewer(start.addingTimeInterval(-1), than: start))
        #expect(ActivityCheck.isNewer(start.addingTimeInterval(-0.5), than: start))
        #expect(ActivityCheck.isNewer(start, than: start))
        #expect(ActivityCheck.isNewer(nil, than: start))
        #expect(ActivityCheck.isNewer(start, than: nil))
    }

    @Test func rateLimited403IsNotUnsupported() async throws {
        let reset = Date(timeIntervalSince1970: 1_900_000_000)
        let activity = checker(StubHTTP([Reply(
            status: 403,
            headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "\(Int(reset.timeIntervalSince1970))"])]))
        await #expect(throws: APIError.rateLimited(resetAt: reset)) { try await activity.check() }
    }

    @Test func secondaryRateLimitIsNotUnsupported() async throws {
        let activity = checker(StubHTTP([Reply(
            status: 403, headers: ["retry-after": "30"],
            body: Data(#"{"message":"You have exceeded a secondary rate limit"}"#.utf8))]))
        await #expect { try await activity.check() } throws: { error in
            if case .rateLimited = error as? APIError { return true }
            return false
        }
    }

    @Test func ssoIsNotUnsupported() async throws {
        let activity = checker(StubHTTP([Reply(
            status: 403, headers: ["X-GitHub-SSO": "required; url=https://github.com/orgs/o/sso?x=1"])]))
        await #expect(throws: APIError.ssoRequired(URL(string: "https://github.com/orgs/o/sso?x=1"))) {
            try await activity.check()
        }
    }

    @Test func unauthorizedGoesToTheTokenSourceAndThrows() async throws {
        let source = CountingSource()
        let activity = checker(StubHTTP([Reply(status: 401)]), auth: source)
        await #expect(throws: APIError.unauthorized) { try await activity.check() }
        #expect(await source.rejectedTokens == ["t"])
    }

    @Test func serverErrorThrows() async throws {
        let activity = checker(StubHTTP([Reply(status: 502)]))
        await #expect(throws: APIError.server(502)) { try await activity.check() }
    }

    @Test func offlineThrowsNetwork() async throws {
        await #expect { try await checker(FailingHTTP()).check() } throws: { error in
            if case .network = error as? APIError { return true }
            return false
        }
    }

    @Test func aFailureKeepsTheBaseline() async throws {
        let http = StubHTTP([modified(monday), Reply(status: 502), notModified])
        let activity = checker(http)
        _ = try await activity.check()
        _ = try? await activity.check()
        #expect(try await activity.check().change == .unchanged)
        #expect(await http.requests.last?.value(forHTTPHeaderField: "If-Modified-Since") == monday)
    }
}
