import Foundation
import Testing
@testable import PullBullKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

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

    convenience init(json: [String]) {
        self.init(json.map { (Data($0.utf8), response(200)) })
    }

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

private func api(_ transport: StubTransport, now: Date = Date()) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"), now: { now })
}

private func node(_ json: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
}

/// A minimal issue node; `extra` is spliced in as further top-level fields.
private func issueJSON(state: String = "OPEN", stateReason: String = "null", extra: String = "") -> String {
    """
    {"number":7,"title":"T","url":"https://github.com/o/r/issues/7","state":"\(state)",\
    "stateReason":\(stateReason),"repository":{"nameWithOwner":"o/r"}\(extra)}
    """
}

@Suite struct IssueDecodingTests {
    @Test func issueReadsNodeIdAndBoardItemNodeId() throws {
        let issue = Decoding.issue(
            from: try node(issueJSON(extra: #","id":"I_kwDOB2""#)), boardItemId: 7, boardItemNodeId: "PVTI_x")
        #expect(issue?.nodeId == "I_kwDOB2")
        #expect(issue?.boardItemNodeId == "PVTI_x")
        #expect(issue?.boardItemId == 7)
        #expect(Queries.issueRowFields.contains("fragment issueRowFields on Issue {\n  id "))
    }

    @Test func decodesIssueSearchPage() async throws {
        let page = try await api(StubTransport([(try fixture("issue_search_page"), response(200))]))
            .searchIssues("q", assignmentFor: "devon")
        let first = try #require(page.issues.first)
        #expect(first.key == PRKey(repo: "initech/gadgets", number: 231))
        #expect(first.labels == ["bug", "backend"])
        #expect(first.labelColors == ["d73a4a", nil])
        #expect(first.labelColor(at: 1) == nil)
        #expect(first.assignees.map(\.login) == ["devon", "dev-a"])
        #expect(first.commentCount == 5)
        #expect(first.author == "dev-b")
        #expect(first.myAssignment == Assignment(actor: "dev-b", at: try Decoding.date("2026-10-25T09:00:00Z")))
        #expect(first.glyph == .open)
        #expect(first.createdAt == (try Decoding.date("2026-10-20T08:00:00Z")))
        #expect(first.updatedAt == (try Decoding.date("2026-10-26T10:15:00Z")))
        #expect(first.closedAt == nil)
        #expect(first.status == nil)
        #expect(first.boardItemId == nil)
        #expect(page.issues.count == 2)
        #expect(page.issues[1].stateReason == .reopened)
        #expect(page.issues[1].myAssignment == nil)
        #expect(!page.hasMore)
    }

    @Test func searchAsksForAssignmentsOnlyWithViewer() async throws {
        let empty = #"{"data":{"search":{"pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":[]}}}"#
        let stub = StubTransport(json: [empty, empty])
        _ = try await api(stub).searchIssues("is:issue")
        _ = try await api(stub).searchIssues("is:issue", assignmentFor: "me")
        #expect(!stub.bodies[0].contains("timelineItems"))
        #expect(stub.bodies[0].contains("fragment issueRowFields on Issue"))
        #expect(stub.bodies[1].contains("ASSIGNED_EVENT"))
    }

    @Test func searchFollowsPagesUpToMax() async throws {
        let issue = issueJSON()
        let pageA = #"{"data":{"search":{"pageInfo":{"endCursor":"A","hasNextPage":true},"nodes":["# + issue + "]}}}"
        let stub = StubTransport(json: [pageA, pageA])
        let result = try await api(stub).searchIssues("q", maxPages: 2)
        #expect(result.issues.count == 2)
        #expect(result.hasMore)
        #expect(stub.bodies[1].contains("\"after\":\"A\""))
    }

    @Test func assignmentPicksLatestEventForViewerOnly() throws {
        let events = """
        ,"timelineItems":{"nodes":[\
        {"createdAt":"2026-10-25T09:00:00Z","actor":{"login":"dev-b"},"assignee":{"__typename":"User","login":"dev-a"}},\
        {"createdAt":"2026-10-20T09:00:00Z","actor":{"login":"dev-c"},"assignee":{"__typename":"User","login":"devon"}},\
        {"createdAt":"2026-10-26T09:00:00Z","actor":{"login":"devon"},"assignee":{"__typename":"User","login":"devon"}},\
        {"createdAt":"2026-10-27T09:00:00Z","actor":{"login":"dev-b"},"assignee":{"__typename":"Bot"}}\
        ]}
        """
        let issue = try #require(Decoding.issue(from: try node(issueJSON(extra: events)), assignmentFor: "Devon"))
        #expect(issue.myAssignment == Assignment(actor: "devon", at: try Decoding.date("2026-10-26T09:00:00Z")))
        let other = try #require(Decoding.issue(from: try node(issueJSON(extra: events)), assignmentFor: "nobody"))
        #expect(other.myAssignment == nil)
        let noViewer = try #require(Decoding.issue(from: try node(issueJSON(extra: events))))
        #expect(noViewer.myAssignment == nil)
    }

    @Test func ghostActorAssignmentHasNilActor() throws {
        let events = """
        ,"timelineItems":{"nodes":[\
        {"createdAt":"2026-10-25T09:00:00Z","actor":null,"assignee":{"__typename":"User","login":"me"}}]}
        """
        let issue = try #require(Decoding.issue(from: try node(issueJSON(extra: events)), assignmentFor: "me"))
        #expect(issue.myAssignment == Assignment(actor: nil, at: try Decoding.date("2026-10-25T09:00:00Z")))
    }

    @Test func ghostAuthorAndNoLabelsDecode() throws {
        let extra = #","author":null,"labels":{"nodes":[]},"assignees":{"nodes":[]},"comments":{"totalCount":0}"#
        let issue = try #require(Decoding.issue(from: try node(issueJSON(extra: extra))))
        #expect(issue.author == nil)
        #expect(issue.labels == [])
        #expect(issue.assignees == [])
        #expect(issue.commentCount == 0)
    }

    @Test func missingRequiredFieldIsNil() throws {
        #expect(Decoding.issue(from: try node(#"{"title":"T","url":"https://x","state":"OPEN"}"#)) == nil)
        #expect(Decoding.issue(from: [:]) == nil)
    }

    @Test func closedNotPlannedGlyph() throws {
        let notPlanned = try #require(Decoding.issue(from: try node(
            issueJSON(state: "CLOSED", stateReason: #""NOT_PLANNED""#))))
        #expect(!notPlanned.isOpen)
        #expect(notPlanned.stateReason == .notPlanned)
        #expect(notPlanned.glyph == .notPlanned)
        let duplicate = try #require(Decoding.issue(from: try node(
            issueJSON(state: "CLOSED", stateReason: #""DUPLICATE""#))))
        #expect(duplicate.glyph == .notPlanned)
        let completed = try #require(Decoding.issue(from: try node(issueJSON(state: "CLOSED"))))
        #expect(completed.stateReason == nil)
        #expect(completed.glyph == .completed)
        let unknown = try #require(Decoding.issue(from: try node(
            issueJSON(state: "CLOSED", stateReason: #""SOMETHING_NEW""#))))
        #expect(unknown.stateReason == nil)
        #expect(unknown.glyph == .completed)
    }

    @Test func statusValueNeedsNameAndOptionId() {
        #expect(Decoding.statusValue(["name": "Todo", "optionId": "o1"]) == BoardStatusValue(optionId: "o1", name: "Todo"))
        #expect(Decoding.statusValue(["name": "Todo"]) == nil)
        #expect(Decoding.statusValue(["optionId": "o1"]) == nil)
        #expect(Decoding.statusValue(nil) == nil)
        #expect(Decoding.statusValue(NSNull()) == nil)
    }

    @Test func boardDecodesStatusAndOptions() async throws {
        let stub = StubTransport([(try fixture("board_items_status"), response(200))])
        let board = try await api(stub).board(.org("initech", 3))
        #expect(board.title == "Team Board")
        #expect(board.statusOptions.map(\.name) == ["Todo", "In progress", "Done"])
        #expect(board.statusOptions.first == StatusOption(id: "opt1", name: "Todo"))
        #expect(board.issues.first?.status == BoardStatusValue(optionId: "opt2", name: "In progress"))
        #expect(board.issues.first?.boardItemId == 1001)
        #expect(board.issues.first?.labels == ["bug"])
        #expect(board.issues.count == 2)
        #expect(board.issues[1].status == nil)
        #expect(board.issues[1].boardItemId == 1002)
        #expect(board.issues[1].glyph == .completed)
        let body = stub.bodies[0]
        #expect(body.contains("fieldValueByName(name:\\\"Status\\\")"))
        #expect(body.contains("...issueRowFields"))
    }

    @Test func boardWithoutStatusFieldHasNoOptions() async throws {
        let json = """
        {"data":{"organization":{"projectV2":{"title":"B","field":null,"items":{\
        "pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":[\
        {"databaseId":5,"fieldValueByName":null,"content":{"__typename":"Issue",\
        "number":1,"title":"T","url":"https://github.com/o/r/issues/1","state":"OPEN","repository":{"nameWithOwner":"o/r"}}}\
        ]}}}}}
        """
        let board = try await api(StubTransport(json: [json])).board(.org("o", 1))
        #expect(board.statusOptions == [])
        #expect(board.issues.count == 1)
        #expect(board.issues[0].status == nil)
        #expect(board.issues[0].boardItemId == 5)
    }

    @Test func boardOptionsComeFromFirstPage() async throws {
        let item = #"{"databaseId":1,"content":{"__typename":"Issue","number":1,"title":"T","url":"https://github.com/o/r/issues/1","state":"OPEN","repository":{"nameWithOwner":"o/r"}}}"#
        let first = #"{"data":{"organization":{"projectV2":{"title":"B","field":{"options":[{"id":"a","name":"A"}]},"items":{"pageInfo":{"endCursor":"C","hasNextPage":true},"nodes":["# + item + "]}}}}}"
        let second = #"{"data":{"organization":{"projectV2":{"title":"B","field":{"options":[{"id":"a","name":"A"}]},"items":{"pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":["# + item + "]}}}}}"
        let board = try await api(StubTransport(json: [first, second])).board(.org("o", 1))
        #expect(board.statusOptions == [StatusOption(id: "a", name: "A")])
        #expect(board.issues.count == 2)
    }

    @Test func boardOptionsDecodeColor() async throws {
        let item = #"{"databaseId":1,"content":{"__typename":"Issue","number":1,"title":"T","url":"https://github.com/o/r/issues/1","state":"OPEN","repository":{"nameWithOwner":"o/r"}}}"#
        let options = #"[{"id":"a","name":"A","color":"YELLOW"},{"id":"b","name":"B"},{"id":"c","name":"C","color":"TEAL"},{"id":"d","name":"D","color":null}]"#
        let json = #"{"data":{"organization":{"projectV2":{"title":"B","field":{"options":"# + options
            + #"},"items":{"pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":["# + item + "]}}}}}"
        let stub = StubTransport(json: [json])
        let board = try await api(stub).board(.org("o", 1))
        #expect(board.statusOptions.map(\.color) == [.yellow, nil, nil, nil])
        #expect(stub.bodies[0].contains("options{id name color}"))
    }

    @Test func statusOptionCodableRoundTripsColor() throws {
        let option = StatusOption(id: "a", name: "In review", color: .blue)
        let data = try JSONEncoder().encode(option)
        #expect(try JSONDecoder().decode(StatusOption.self, from: data) == option)
        let uncolored = StatusOption(id: "a", name: "Todo")
        #expect(try JSONDecoder().decode(StatusOption.self, from: JSONEncoder().encode(uncolored)) == uncolored)
    }

    @Test func statusOptionUnknownColorIsNil() throws {
        let json = #"{"id":"a","name":"A","color":"TEAL"}"#
        let option = try JSONDecoder().decode(StatusOption.self, from: Data(json.utf8))
        #expect(option == StatusOption(id: "a", name: "A"))
    }

    @Test func legacyBoardIssueDecodes() throws {
        let json = #"{"key":{"repo":"o/r","number":9},"title":"i","url":"https://x/9","isOpen":true}"#
        let issue = try JSONDecoder().decode(BoardIssue.self, from: Data(json.utf8))
        #expect(issue == BoardIssue(key: PRKey(repo: "o/r", number: 9), title: "i", url: URL(string: "https://x/9")!, isOpen: true))
        #expect(issue.labels == [])
        #expect(issue.labelColors == [])
        #expect(issue.labelColor(at: 0) == nil)
        #expect(issue.commentCount == 0)
        #expect(issue.assignees == [])
        #expect(issue.glyph == .open)
    }

    @Test func richBoardIssueRoundTrips() throws {
        let issue = BoardIssue(
            key: PRKey(repo: "o/r", number: 1), title: "t", url: URL(string: "https://x/1")!, isOpen: false,
            author: "a", stateReason: .notPlanned, createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2), closedAt: Date(timeIntervalSince1970: 3),
            commentCount: 4, labels: ["x", "y"], labelColors: ["a2eeef", nil], assignees: [Assignee(login: "me", avatarURL: URL(string: "https://a/1"))],
            status: BoardStatusValue(optionId: "o", name: "Todo"), boardItemId: 77,
            myAssignment: Assignment(actor: "b", at: Date(timeIntervalSince1970: 5)))
        let data = try JSONEncoder().encode(issue)
        #expect(try JSONDecoder().decode(BoardIssue.self, from: data) == issue)
    }

    @Test func boardIssueCachedWithLabelNamesOnlyDecodes() throws {
        let json = #"{"key":{"repo":"o/r","number":9},"title":"i","url":"https://x/9","isOpen":true,"labels":["bug"]}"#
        let issue = try JSONDecoder().decode(BoardIssue.self, from: Data(json.utf8))
        #expect(issue.labels == ["bug"])
        #expect(issue.labelColor(at: 0) == nil)
    }
}
