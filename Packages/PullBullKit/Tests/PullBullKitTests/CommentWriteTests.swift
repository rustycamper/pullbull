import Foundation
import Testing
@testable import PullBullKit

private let key = PRKey(repo: "o/r", number: 7)

private func api(_ t: RESTQueue) -> GitHubAPI { GitHubAPI(transport: t, auth: StaticTokenSource("t")) }

private func failure(of t: RESTQueue) async -> CommentFailure {
    do {
        _ = try await api(t).postComment(on: key, body: "hi")
        Issue.record("post succeeded")
        return .unknown
    } catch {
        return CommentFailure.classify(error)
    }
}

@Suite struct CommentWriteTests {
    @Test func postsTrimmedBodyToIssueComments() async throws {
        let t = RESTQueue([(201, #"{"node_id":"IC_1","body":"hi","created_at":"2026-11-02T10:00:00Z","user":{"login":"pb"}}"#)])
        let comment = try await api(t).postComment(on: key, body: "  hi\n")
        #expect(t.sent.count == 1)
        #expect(t.sent[0].method == "POST")
        #expect(t.sent[0].path == "/repos/o/r/issues/7/comments")
        #expect(t.sent[0].body["body"] as? String == "hi")
        #expect(comment == Comment(
            id: "IC_1", author: "pb", body: "hi", createdAt: try Decoding.date("2026-11-02T10:00:00Z")))
    }

    @Test func validationFailedUsesErrorsMessage() async {
        let t = RESTQueue([(422, #"{"message":"Validation Failed","errors":[{"message":"Body is too long (maximum is 65536 characters)"}]}"#)])
        await #expect(throws: APIError.writeRefused("Body is too long (maximum is 65536 characters)")) {
            try await api(t).postComment(on: key, body: "x")
        }
    }

    @Test func goneIsRefusal() async {
        let t = RESTQueue([(410, #"{"message":"Issues are disabled for this repo"}"#)])
        await #expect(throws: APIError.writeRefused("Issues are disabled for this repo")) {
            try await api(t).postComment(on: key, body: "x")
        }
    }

    @Test func lockedIsRefusal() async {
        let message = "Unable to create comment because issue is locked."
        let t = RESTQueue([(403, #"{"message":"\#(message)"}"#)])
        await #expect(throws: APIError.writeRefused(message)) {
            try await api(t).postComment(on: key, body: "x")
        }
    }

    @Test func serverErrorThrowsServer() async {
        let t = RESTQueue([(502, "{}")])
        await #expect(throws: APIError.server(502)) {
            try await api(t).postComment(on: key, body: "x")
        }
    }

    @Test func malformedSuccessIsServerNotRefusal() async {
        let t = RESTQueue([(201, #"{"node_id":"IC_1"}"#)])
        await #expect(throws: APIError.server(201)) {
            try await api(t).postComment(on: key, body: "x")
        }
    }

    @Test func classifiesRefusals() {
        #expect(CommentFailure.classify(APIError.writeRefused("x")) == .refused("x"))
        let errors: [any Error] = [
            APIError.unauthorized, APIError.ssoRequired(nil), APIError.rateLimited(resetAt: nil),
            APIError.forbidden, APIError.insufficientScopes,
        ]
        for error in errors {
            #expect(CommentFailure.classify(error) == .refused(RefreshError(error).message))
        }
    }

    @Test func classifiesNeverSentTransportAsRefused() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
            .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost,
        ]
        for code in codes {
            #expect(CommentFailure.classify(CommentTransportError(code: code))
                == .refused(RefreshError(APIError.network("")).message))
        }
    }

    @Test func classifiesMaybeSentTransportAsUnknown() {
        for code: URLError.Code in [.timedOut, .networkConnectionLost, .badServerResponse, .secureConnectionFailed] {
            #expect(CommentFailure.classify(CommentTransportError(code: code)) == .unknown)
        }
    }

    @Test func classifiesTheRestAsUnknown() {
        #expect(CommentFailure.classify(APIError.server(502)) == .unknown)
        #expect(CommentFailure.classify(APIError.network("offline")) == .unknown)
        #expect(CommentFailure.classify(CancellationError()) == .unknown)
    }

    @Test func timeoutIsUnknownEndToEnd() async {
        #expect(await failure(of: RESTQueue(failing: URLError(.timedOut))) == .unknown)
    }

    @Test func droppedConnectionIsUnknownEndToEnd() async {
        #expect(await failure(of: RESTQueue(failing: URLError(.networkConnectionLost))) == .unknown)
    }

    @Test func noInternetIsRefusedEndToEnd() async {
        #expect(await failure(of: RESTQueue(failing: URLError(.notConnectedToInternet))) == .refused("Offline"))
    }

    @Test func cancellationStaysCancellation() async {
        let t = RESTQueue(failing: URLError(.cancelled))
        await #expect(throws: CancellationError.self) {
            try await api(t).postComment(on: key, body: "x")
        }
    }
}
