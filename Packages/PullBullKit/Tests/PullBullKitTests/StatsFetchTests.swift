import Foundation
import Testing
@testable import PullBullKit

private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!, statusCode: status,
        httpVersion: nil, headerFields: headers)!
}

private final class StubTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Data, HTTPURLResponse)]
    private var sent: [Data] = []

    init(_ responses: [(Data, HTTPURLResponse)]) { queue = responses }

    var bodies: [Data] { lock.withLock { sent } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
    }
}

private func api(_ transport: StubTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"), now: { Date() })
}

private func fixture(_ name: String) throws -> (Data, HTTPURLResponse) {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return (try Data(contentsOf: url), response(200))
}

private func json(_ text: String) -> (Data, HTTPURLResponse) { (Data(text.utf8), response(200)) }

private func variables(_ body: Data) throws -> [String: Any] {
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try #require(object["variables"] as? [String: Any])
}

private func contributions(repos: [String], hasNext: Bool) -> (Data, HTTPURLResponse) {
    let nodes = repos.map {
        #"{"pullRequest":{"author":{"login":"a"},"repository":{"nameWithOwner":"\#($0)"},"timelineItems":{"nodes":[]},"reviews":{"nodes":[]}}}"#
    }.joined(separator: ",")
    return json(#"{"data":{"viewer":{"contributionsCollection":{"pullRequestReviewContributions":{"pageInfo":{"hasNextPage":\#(hasNext),"endCursor":"E"},"nodes":[\#(nodes)]}}}}}"#)
}

private func iso(_ text: String) -> Date { try! Decoding.date(text) }

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let now = iso("2026-11-04T13:30:00Z")
private let week = StatsPeriod.week.window(now: now, calendar: utc)

@Suite struct StatsFetchTests {
    @Test func reviewedPRsDecodes() async throws {
        let stub = StubTransport([try fixture("stats-contributions")])
        let result = try await api(stub).reviewedPRs(
            window: week, orgID: "O_kgDOTest", login: "me", scope: .org("acme"))
        #expect(result.items.map(\.author) == ["me", "alice", "bob"])
        #expect(result.capped == false)
        #expect(result.items[1].requests == [
            ReviewRequestEvent(at: iso("2026-11-02T08:00:00Z"), reviewer: .team(slug: "ios", name: "ios"))])
        #expect(result.items[2].requests.first?.reviewer == .user("me"))
        #expect(result.items[2].myReviews.map(\.submittedAt) == [
            iso("2026-11-01T09:00:00Z"), iso("2026-11-01T12:00:00Z")])
        let sent = try variables(try #require(stub.bodies.first))
        #expect(sent["org"] as? String == "O_kgDOTest")
        #expect(sent["login"] as? String == "me")
        #expect(sent["from"] as? String == "2026-10-29T00:00:00Z")
        #expect(sent["to"] as? String == "2026-11-04T13:29:59Z")
    }

    @Test func orgScopeWithoutIDThrows() async {
        let stub = StubTransport([])
        await #expect(throws: APIError.graphQL("missing organization ID")) {
            try await api(stub).reviewedPRs(window: week, orgID: nil, login: "me", scope: .org("acme"))
        }
        #expect(stub.bodies.isEmpty)
    }

    @Test func personalForeignPageNotCapped() async throws {
        let stub = StubTransport([contributions(repos: Array(repeating: "other/x", count: 100), hasNext: false)])
        let result = try await api(stub).reviewedPRs(
            window: week, orgID: nil, login: "me", scope: .personal(login: "me"))
        #expect(result.items.isEmpty)
        #expect(result.capped == false)
    }

    @Test func personalScopePages() async throws {
        let stub = StubTransport([
            contributions(repos: ["other/x"], hasNext: true), try fixture("stats-contributions-page2"),
        ])
        let result = try await api(stub).reviewedPRs(
            window: week, orgID: nil, login: "me", scope: .personal(login: "me"))
        #expect(result.items.map(\.repo) == ["me/app"])
        #expect(stub.bodies.count == 2)
        #expect(result.capped == false)
        #expect(try variables(stub.bodies[0])["org"] is NSNull)
        #expect(try variables(stub.bodies[1])["after"] as? String == "E")
    }

    @Test func personalScopeStopsAtThreePages() async throws {
        let page = contributions(repos: ["other/x"], hasNext: true)
        let stub = StubTransport([page, page, page])
        let result = try await api(stub).reviewedPRs(
            window: week, orgID: nil, login: "me", scope: .personal(login: "me"))
        #expect(stub.bodies.count == 3)
        #expect(result.capped)
    }

    @Test func searchQueries() async throws {
        let stub = StubTransport([try fixture("stats-opened"), try fixture("stats-merged")])
        _ = try await api(stub).openedPRs(window: week, scope: .org("acme"))
        _ = try await api(stub).mergedPRs(window: week, scope: .org("acme"))
        #expect(try variables(stub.bodies[0])["q"] as? String
            == "is:pr author:@me created:2026-10-29T00:00:00Z..2026-11-04T13:29:59Z archived:false sort:created-desc org:acme")
        #expect(try variables(stub.bodies[1])["q"] as? String
            == "is:pr author:@me is:merged merged:2026-10-29T00:00:00Z..2026-11-04T13:29:59Z archived:false sort:created-desc org:acme")
    }

    @Test func issueQueryStrings() {
        let scope = FetchScope.personal(login: "me")
        #expect(StatsQueries.closedIssues(window: week, scope: scope)
            == "is:issue assignee:@me closed:2026-10-29T00:00:00Z..2026-11-04T13:29:59Z archived:false user:me")
        #expect(StatsQueries.openedIssues(window: week, scope: scope)
            == "is:issue author:@me created:2026-10-29T00:00:00Z..2026-11-04T13:29:59Z archived:false user:me")
    }

    @Test func openedDecodes() async throws {
        let stub = StubTransport([try fixture("stats-opened")])
        let result = try await api(stub).openedPRs(window: week, scope: .org("acme"))
        #expect(result.total == 3)
        #expect(result.items.count == 2)
        #expect(result.capped)
        #expect(result.items[0].isDraft)
        #expect(result.items[0].readyAt == nil)
        let ready = result.items[1]
        #expect(ready.isOpen)
        #expect(ready.readyAt == iso("2026-11-02T09:00:00Z"))
        #expect(ready.reviews.map(\.byBot) == [true, false, false])
        #expect(ready.reviews.map(\.pending) == [false, false, true])
        #expect(ready.reviews[1].author == "alice")
        #expect(ready.reviews[1].avatarURL == URL(string: "https://a/alice.png"))
    }

    @Test func mergedAndCounts() async throws {
        let stub = StubTransport([try fixture("stats-merged"), try fixture("stats-count")])
        let merged = try await api(stub).mergedPRs(window: week, scope: .org("acme"))
        #expect(merged.total == 150)
        #expect(merged.items.first == MergedPR(
            createdAt: iso("2026-11-01T08:00:00Z"), mergedAt: iso("2026-11-02T08:00:00Z")))
        #expect(merged.capped)
        #expect(try await api(stub).issueCount("is:issue") == 7)
        #expect(try variables(stub.bodies[1])["q"] as? String == "is:issue")
    }

    @Test func organizationIDDecodes() async throws {
        let stub = StubTransport([try fixture("stats-org-id")])
        #expect(try await api(stub).organizationID("acme") == "O_kgDOTest")
    }

    @Test func commentsPageBackwards() async throws {
        let stub = StubTransport([try fixture("stats-comments"), try fixture("stats-comments-page2")])
        let result = try await api(stub).myComments(window: week, scope: .personal(login: "acme"))
        #expect(stub.bodies.count == 2)
        #expect(result.items == [
            iso("2026-10-31T10:00:00Z"), iso("2026-11-01T10:00:00Z"), iso("2026-11-03T10:00:00Z")])
        #expect(result.capped == false)
        #expect(try variables(stub.bodies[1])["before"] as? String == "K1")
    }

    @Test func commentsCapAtFivePages() async throws {
        let page = json(#"{"data":{"viewer":{"issueComments":{"pageInfo":{"hasPreviousPage":true,"startCursor":"K"},"nodes":[{"createdAt":"2026-11-01T10:00:00Z","repository":{"nameWithOwner":"acme/web"}}]}}}}"#)
        let stub = StubTransport(Array(repeating: page, count: 5))
        let result = try await api(stub).myComments(window: week, scope: .org("acme"))
        #expect(stub.bodies.count == 5)
        #expect(result.items.count == 5)
        #expect(result.capped)
    }

    @Test func rateLimitedPropagates() async {
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1793050000"]
        let stub = StubTransport([(Data("{}".utf8), response(403, headers: headers))])
        await #expect(throws: APIError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_793_050_000))) {
            try await api(stub).myComments(window: week, scope: .org("acme"))
        }
    }
}
