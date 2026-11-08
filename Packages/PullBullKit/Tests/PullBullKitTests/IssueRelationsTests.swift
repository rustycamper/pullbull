import Foundation
import Testing
@testable import PullBullKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!, statusCode: status,
        httpVersion: nil, headerFields: [:])!
}

private final class StubTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Data, HTTPURLResponse)]
    private var sent: [Data] = []

    init(_ responses: [(Data, HTTPURLResponse)]) { queue = responses }

    var bodies: [String] {
        lock.withLock { sent.map { String(decoding: $0, as: UTF8.self) } }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
    }
}

private func api(_ transport: StubTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"))
}

@Suite struct IssueRelationsTests {
    private let key = PRKey(repo: "initech/gadgets", number: 231)

    private func related(_ n: Int, open: Bool, reason: IssueStateReason? = nil) -> RelatedIssue {
        RelatedIssue(
            key: PRKey(repo: "initech/gadgets", number: n), title: "Issue \(n)",
            url: URL(string: "https://github.com/initech/gadgets/issues/\(n)")!, isOpen: open, stateReason: reason)
    }

    @Test func relationsParse() async throws {
        let d = try await api(StubTransport([(try fixture("issue_detail_relations"), response(200))])).issueDetail(key)
        let r = try #require(d.relations)
        #expect(r.parent?.key == PRKey(repo: "initech/gadgets", number: 200))
        #expect(r.subIssues.items.map(\.key.number) == [232, 233])
        #expect(r.subIssues.moreCount == 0)
        #expect(r.subIssuesSummary == "1 of 3 done")
        #expect(r.blockedBy.items.map(\.glyph) == [.open, .notPlanned])
        #expect(r.blockedBySummary == "1 open")
        #expect(r.blockingSummary == "all closed")
        #expect(r.blocking.items.count == 20 && r.blocking.moreCount == 5)
        #expect(r.hasDependencies)
    }

    @Test func referenceNamesOtherRepos() async throws {
        let r = try #require(
            try await api(StubTransport([(try fixture("issue_detail_relations"), response(200))])).issueDetail(key).relations)
        #expect(r.blockedBy.items[0].reference(from: "initech/gadgets") == "other-org/tools#240")
        #expect(r.parent?.reference(from: "Initech/Gadgets") == "#200")
    }

    @Test func noRelationsIsEmpty() async throws {
        let d = try await api(StubTransport([(try fixture("issue_detail"), response(200))])).issueDetail(key)
        #expect(d.relations == IssueRelations.empty)
        #expect(d.relations?.hasDependencies == false)
    }

    @Test func summariesFallBackToOpenRows() {
        let open = related(1, open: true), closed = related(2, open: false, reason: .completed)
        let r = IssueRelations(
            blockedBy: RelatedIssues(items: [open, closed], totalCount: 2, returned: 2), openBlockedBy: nil,
            blocking: RelatedIssues(items: [closed], totalCount: 1, returned: 1), openBlocking: nil)
        #expect(r.blockedBySummary == "1 open")
        #expect(r.blockingSummary == "all closed")
    }

    @Test func subIssuesSummaryFallsBackToRows() async throws {
        var object = try #require(JSONSerialization.jsonObject(with: fixture("issue_detail_relations")) as? [String: Any])
        var data = try #require(object["data"] as? [String: Any])
        var repository = try #require(data["repository"] as? [String: Any])
        var issue = try #require(repository["issue"] as? [String: Any])
        issue["subIssuesSummary"] = nil
        repository["issue"] = issue
        data["repository"] = repository
        object["data"] = data
        let stub = StubTransport([(try JSONSerialization.data(withJSONObject: object), response(200))])
        let r = try #require(try await api(stub).issueDetail(key).relations)
        // Three sub-issues on GitHub; of the two rows read (a third node is null), one is closed.
        #expect(r.subIssuesTotal == 3)
        #expect(r.subIssuesCompleted == 1)
        #expect(r.subIssuesSummary == "1 of 3 done")
    }

    @Test func onlyNullNodesIsNotShown() {
        let g = RelatedIssues(items: [], totalCount: 1, returned: 1)
        #expect(!g.isShown && g.moreCount == 0)
    }

    @Test func legacyCachedIssueDetailDecodes() async throws {
        let d = try await api(StubTransport([(try fixture("issue_detail_relations"), response(200))])).issueDetail(key)
        let data = try JSONEncoder().encode(d)
        #expect(try JSONDecoder().decode(IssueDetail.self, from: data) == d)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["relations"] = nil
        let old = try JSONDecoder().decode(IssueDetail.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.relations == nil)
    }

    @Test func issueDetailQueryAsksForRelations() {
        let q = Queries.issueDetail
        for part in [
            "parent{...relatedIssue}", "subIssues(first:20)", "blockedBy(first:20)", "blocking(first:20)",
            "issueDependenciesSummary", "subIssuesSummary", "fragment relatedIssue on Issue",
        ] {
            #expect(q.contains(part), "missing \(part)")
        }
    }
}
