import Foundation
import Testing
@testable import PullBullKit

private let key = PRKey(repo: "o/r", number: 7)

private func api(_ t: any GraphQLTransport) -> GitHubAPI { GitHubAPI(transport: t, auth: StaticTokenSource("t")) }

/// Answers each GraphQL request in turn.
private final class HeadTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data]

    init(_ json: [String]) { queue = json.map { Data($0.utf8) } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let data = lock.withLock { queue.removeFirst() }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

@Suite struct ReviewWriteTests {
    @Test func submitsToPullReviews() async throws {
        let t = RESTQueue([(200, #"{"id":1}"#)])
        try await api(t).submitReview(on: key, verdict: .approve, body: "  ok\n", commit: "abc")
        #expect(t.sent.count == 1)
        #expect(t.sent[0].method == "POST")
        #expect(t.sent[0].path == "/repos/o/r/pulls/7/reviews")
        #expect(t.sent[0].body["event"] as? String == "APPROVE")
        #expect(t.sent[0].body["commit_id"] as? String == "abc")
        #expect(t.sent[0].body["body"] as? String == "ok")
    }

    @Test func requestChangesSendsItsEvent() async throws {
        let t = RESTQueue([(200, "{}")])
        try await api(t).submitReview(on: key, verdict: .requestChanges, body: "no", commit: "abc")
        #expect(t.sent[0].body["event"] as? String == "REQUEST_CHANGES")
    }

    @Test func emptyBodyIsLeftOut() async throws {
        let t = RESTQueue([(200, "{}")])
        try await api(t).submitReview(on: key, verdict: .approve, body: " \n", commit: "abc")
        #expect(t.sent[0].body["body"] == nil)
        #expect(t.sent[0].body["event"] as? String == "APPROVE")
    }

    @Test func validationFailedUsesErrorsMessage() async {
        let t = RESTQueue([(422, #"{"message":"Unprocessable Entity","errors":[{"message":"Can not approve your own pull request"}]}"#)])
        await #expect(throws: APIError.writeRefused("Can not approve your own pull request")) {
            try await api(t).submitReview(on: key, verdict: .approve, body: "", commit: "abc")
        }
    }

    @Test func validationFailedUsesErrorsString() async {
        let t = RESTQueue([(422, #"{"message":"Unprocessable Entity","errors":["Can not approve your own pull request"]}"#)])
        await #expect(throws: APIError.writeRefused("Can not approve your own pull request")) {
            try await api(t).submitReview(on: key, verdict: .approve, body: "", commit: "abc")
        }
    }

    @Test func timeoutIsUnknown() async {
        let t = RESTQueue(failing: URLError(.timedOut))
        do {
            try await api(t).submitReview(on: key, verdict: .approve, body: "", commit: "abc")
            Issue.record("submit succeeded")
        } catch {
            #expect(CommentFailure.classify(error) == .unknown)
        }
    }

    @Test func verdictsMapToStatesAndTitles() {
        #expect(ReviewVerdict.approve.state == .approved)
        #expect(ReviewVerdict.requestChanges.state == .changesRequested)
        #expect(ReviewVerdict.approve.title == "Approve")
        #expect(ReviewVerdict.requestChanges.title == "Request changes")
    }

    @Test func prHeadDecodesOidAndState() async throws {
        let cases: [(String, PRState)] = [("OPEN", .open), ("CLOSED", .closed), ("MERGED", .merged)]
        for (raw, state) in cases {
            let t = HeadTransport([#"{"data":{"repository":{"pullRequest":{"headRefOid":"abc123","state":"\#(raw)"}}}}"#])
            #expect(try await api(t).prHead(key) == PRHead(oid: "abc123", state: state))
        }
    }
}
