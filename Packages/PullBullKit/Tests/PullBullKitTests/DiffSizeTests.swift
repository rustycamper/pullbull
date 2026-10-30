import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_793_000_000)
private let repo = "initech/gadgets"

private func pr(_ number: Int, additions: Int?, deletions: Int?) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "someone",
        authorAvatarURL: nil, state: .open, isDraft: false, createdAt: now, updatedAt: now, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
        latestReviews: [], reviewRequests: [], additions: additions, deletions: deletions)
}

private func matches(_ raw: String, _ pr: PullRequest) -> Bool {
    SearchQuery.parse(raw).matches(pr, viewer: "me", now: now, calendar: .current)
}

private final class RecordingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    var bodies: [String] { lock.withLock { sent } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sent.append(String(decoding: body, as: UTF8.self)) }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let page = #"{"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":false},"nodes":[]}}}"#
        return (Data(page.utf8), response)
    }
}

@Suite struct DiffSizeTests {
    @Test func buckets() {
        #expect(SizeFilter.of(additions: 50, deletions: 0) == .s)
        #expect(SizeFilter.of(additions: 30, deletions: 21) == .m)
        #expect(SizeFilter.of(additions: 300, deletions: 0) == .m)
        #expect(SizeFilter.of(additions: 250, deletions: 51) == .l)
        #expect(SizeFilter.of(additions: nil, deletions: 3) == nil)
        #expect(SizeFilter.of(additions: 3, deletions: nil) == nil)
        #expect(SizeFilter.s.token == "size:s")
    }

    @Test func text() {
        #expect(DiffSize.text(additions: 120, deletions: 30) == "+120 \u{2212}30")
        #expect(DiffSize.text(additions: 0, deletions: 0) == "+0 \u{2212}0")
        #expect(DiffSize.text(additions: nil, deletions: 0) == nil)
        #expect(DiffSize.text(additions: 0, deletions: nil) == nil)
    }

    @Test func sizeQuery() {
        let small = pr(1, additions: 8, deletions: 2)
        let mid = pr(2, additions: 100, deletions: 20)
        let big = pr(3, additions: 390, deletions: 10)
        let unknown = pr(4, additions: nil, deletions: nil)
        #expect(matches("size:s", small))
        #expect(!matches("size:s", big))
        #expect(matches("size:s size:m", small) && matches("size:s size:m", mid))
        #expect(!matches("size:s size:m", big))
        #expect(!matches("-size:l", big))
        #expect(matches("-size:l", small))
        #expect(!matches("size:s", unknown))
        #expect(!matches("-size:s", unknown))
        #expect(SearchQuery.parse("size:xl") == .text(["size:xl"]))
        #expect(SearchQuery.parse("size:S").filter?.include.sizes == [.s])
        #expect(SearchQuery.parse("size:s -size:l").filter?.tokens == ["size:s", "-size:l"])
    }

    @Test func sizeIsLocalAndPROnly() async throws {
        let filter = try #require(SearchQuery.parse("size:s fix").filter)
        #expect(filter.prOnly)
        #expect(try #require(SearchQuery.parse("-size:l fix").filter).prOnly)
        let remote = SearchEngine.remoteQuery(
            kind: "pr", scope: .org("initech"), filter: filter, now: now, calendar: .current)
        #expect(!remote.contains("size:"))
        let negated = try #require(SearchQuery.parse("-size:l fix").filter)
        #expect(!SearchEngine.remoteQuery(
            kind: "pr", scope: .org("initech"), filter: negated, now: now, calendar: .current).contains("size:"))
        let transport = RecordingTransport()
        let engine = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        let snap = Snapshot(
            fetchedAt: now,
            org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [])
        for await _ in engine.results(.parse("size:s fix"), snap: snap) {}
        #expect(!transport.bodies.contains { $0.contains("is:issue") })
        #expect(!transport.bodies.contains { $0.contains("size:") })
    }

    @Test func contextNamesIt() throws {
        let filter = try #require(SearchQuery.parse("size:s -size:l").filter)
        #expect(SearchContext.filterDescription(filter) == "Filtered by size: small, excluding size: large")
    }
}
