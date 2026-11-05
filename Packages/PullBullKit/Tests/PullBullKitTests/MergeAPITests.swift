import Foundation
import Testing
@testable import PullBullKit

private let key = PRKey(repo: "o/r", number: 88)

private func api(_ t: any GraphQLTransport) -> GitHubAPI { GitHubAPI(transport: t, auth: StaticTokenSource("t")) }

private let accepted = #"{"status":"pending","details":{"message":"Merge request enqueued.","uuid":"1408cfe6-cc5b-442a-9c57-79a41044e2d2","merge_method":"squash","merge_action":"direct_merge","expected_head_sha":"a649","bypass_rules":false}}"#
private let conflict = #"{"status":"pending","details":{"message":"A merge request already exists for this pull request.","uuid":"e9d8","merge_method":"squash","merge_action":"direct_merge","expected_head_sha":"a50c","bypass_rules":false}}"#
private let alreadyMerged = #"{"status":"merged","details":{"message":"Pull request is already merged.","sha":"1886"}}"#
private let pollMerged = #"{"status":"merged","details":{"message":"Pull request was merged.","sha":"9743"}}"#
private let wrongSha = #"{"status":"failed","details":{"message":"Pull request head branch was modified."}}"#

/// Answers each GraphQL request in turn and keeps what it was sent.
private final class GraphQLQueue: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [String]
    private var log: [[String: Any]] = []

    init(_ json: [String]) { queue = json }

    var sent: [[String: Any]] { lock.withLock { log } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let data = lock.withLock {
            log.append((try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:])
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(data.utf8), response)
    }
}

@Suite struct MergeAPITests {
    @Test func requestSendsBypassFalseAndTheSha() async throws {
        let t = RESTQueue([(202, accepted)])
        _ = try await api(t).requestMerge(key, head: "a649", method: .squash)
        #expect(t.sent[0].method == "PUT")
        #expect(t.sent[0].path == "/repos/o/r/pulls/88/merge-async")
        let text = String(decoding: t.sent[0].rawBody, as: UTF8.self)
        #expect(text == #"{"bypass_rules":false,"merge_action":"direct_merge","merge_method":"squash","sha":"a649"}"#)
    }

    @Test func acceptedReturnsPending() async throws {
        let t = RESTQueue([(202, accepted)])
        let state = try await api(t).requestMerge(key, head: "a649", method: .squash)
        #expect(state == .pending(uuid: "1408cfe6-cc5b-442a-9c57-79a41044e2d2"))
    }

    @Test func alreadyMergedReturnsMerged() async throws {
        let t = RESTQueue([(200, alreadyMerged)])
        #expect(try await api(t).requestMerge(key, head: "a", method: .merge) == .merged)
    }

    @Test func conflictReturnsTheExistingRequest() async throws {
        let t = RESTQueue([(409, conflict)])
        #expect(try await api(t).requestMerge(key, head: "a", method: .rebase) == .pending(uuid: "e9d8"))
    }

    @Test func aConflictWithNoUUIDThrows() async {
        let t = RESTQueue([(409, #"{"status":"pending","details":{"message":"A merge request already exists."}}"#)])
        await #expect(throws: (any Error).self) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func anAcceptedAnswerWithNoUUIDThrows() async {
        let t = RESTQueue([(202, #"{"status":"pending","details":{"message":"Merge request enqueued."}}"#)])
        await #expect(throws: (any Error).self) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func notReadyIsARefusal() async {
        let t = RESTQueue([(400, wrongSha)])
        await #expect(throws: APIError.writeRefused("Pull request head branch was modified.")) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func aTopLevelMessageIsTheFallbackForARefusal() async {
        let t = RESTQueue([(400, #"{"message":"Bad request"}"#)])
        await #expect(throws: APIError.writeRefused("Bad request")) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func anUnreadableStatusThrows() async {
        let t = RESTQueue([(200, #"{"status":"wobbling","details":{}}"#)])
        await #expect(throws: (any Error).self) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func anIntegrationRefusalCarriesGitHubsWords() async {
        let t = RESTQueue([(403, #"{"message":"Resource not accessible by integration","documentation_url":"x","status":"403"}"#)])
        await #expect(throws: APIError.writeRefused("Resource not accessible by integration")) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func aTimeoutKeepsItsTransportFailure() async {
        let t = RESTQueue(failing: URLError(.timedOut))
        do {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
            Issue.record("sent")
        } catch {
            #expect(CommentFailure.classify(error) == .unknown)
        }
    }

    @Test func aPollSendsNoBody() async throws {
        let t = RESTQueue([(200, pollMerged)])
        let state = try await api(t).mergeResult(key, uuid: "u1")
        #expect(state == .merged)
        #expect(t.sent[0].method == "GET")
        #expect(t.sent[0].path == "/repos/o/r/pulls/88/merge-async/u1")
        #expect(t.sent[0].rawBody.isEmpty)
        let request = URLSessionTransport.restRequest("GET", path: "/x", body: Data(), token: "t")
        #expect(request.httpBody == nil)
    }

    @Test func aPendingPollKeepsItsUUID() async throws {
        let t = RESTQueue([(200, accepted)])
        #expect(try await api(t).mergeResult(key, uuid: "u1") == .pending(uuid: "u1"))
    }

    @Test func aFailedPollCarriesItsMessage() async throws {
        let t = RESTQueue([(200, #"{"status":"failed","details":{"message":"Required status check is expected."}}"#)])
        #expect(try await api(t).mergeResult(key, uuid: "u1") == .failed("Required status check is expected."))
    }

    @Test func aRulesetFailureReadsOnOneLine() async throws {
        let t = RESTQueue([(200, #"{"status":"failed","details":{"message":"Repository rule violations found\n\nRequired status check \"test\" is failing.\n\n"}}"#)])
        #expect(try await api(t).mergeResult(key, uuid: "u1")
            == .failed(#"Repository rule violations found Required status check "test" is failing."#))
    }

    @Test func aRefusal400ReadsOnOneLine() async {
        let t = RESTQueue([(400, #"{"status":"failed","details":{"message":"  Rule\n\nviolated.\n"}}"#)])
        await #expect(throws: APIError.writeRefused("Rule violated.")) {
            _ = try await api(t).requestMerge(key, head: "a", method: .squash)
        }
    }

    @Test func aFailed400PollCarriesItsMessage() async throws {
        let t = RESTQueue([(400, wrongSha)])
        #expect(try await api(t).mergeResult(key, uuid: "u1") == .failed("Pull request head branch was modified."))
    }

    @Test func aPoll404Throws() async {
        let t = RESTQueue([(404, #"{"message":"Not Found"}"#)])
        await #expect(throws: (any Error).self) {
            _ = try await api(t).mergeResult(key, uuid: "u1")
        }
    }

    @Test func enableAutoMergeSendsExpectedHead() async throws {
        let t = GraphQLQueue([#"{"data":{"enablePullRequestAutoMerge":{"clientMutationId":null}}}"#])
        try await api(t).enableAutoMerge(key, nodeID: "PR_1", head: "abc", method: .squash)
        let variables = t.sent[0]["variables"] as? [String: Any]
        #expect(variables?["pr"] as? String == "PR_1")
        #expect(variables?["head"] as? String == "abc")
        #expect(variables?["method"] as? String == "SQUASH")
        #expect((t.sent[0]["query"] as? String)?.contains("enablePullRequestAutoMerge") == true)
    }

    @Test func autoMergeValidationIsARefusal() async {
        let t = GraphQLQueue([#"{"data":{"enablePullRequestAutoMerge":null},"errors":[{"type":"UNPROCESSABLE","path":["enablePullRequestAutoMerge"],"message":"Pull request Pull request is in clean status"}]}"#])
        await #expect(throws: APIError.writeRefused("Pull request Pull request is in clean status")) {
            try await api(t).enableAutoMerge(key, nodeID: "PR_1", head: "abc", method: .merge)
        }
    }

    @Test func disableAutoMergeSendsTheNode() async throws {
        let t = GraphQLQueue([#"{"data":{"disablePullRequestAutoMerge":{"clientMutationId":null}}}"#])
        try await api(t).disableAutoMerge(key, nodeID: "PR_1")
        let variables = t.sent[0]["variables"] as? [String: Any]
        #expect(variables?["pr"] as? String == "PR_1")
        #expect((t.sent[0]["query"] as? String)?.contains("disablePullRequestAutoMerge") == true)
    }

    @Test func disableValidationIsARefusal() async {
        let t = GraphQLQueue([#"{"data":{"disablePullRequestAutoMerge":null},"errors":[{"type":"UNPROCESSABLE","message":"Auto merge is not enabled"}]}"#])
        await #expect(throws: APIError.writeRefused("Auto merge is not enabled")) {
            try await api(t).disableAutoMerge(key, nodeID: "PR_1")
        }
    }
}
