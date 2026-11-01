import Foundation
import Testing
@testable import PullBullKit

/// Answers each request in turn and records the bodies.
private final class QueueTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data]
    private var sent: [Data] = []

    init(_ json: [String]) { queue = json.map { Data($0.utf8) } }

    var bodies: [[String: Any]] {
        lock.withLock { sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }

    /// The first mutation or query field each request named, in order.
    var operations: [String] {
        let names = ["addLabelsToLabelable", "removeLabelsFromLabelable", "addAssigneesToAssignable",
                     "removeAssigneesFromAssignable", "issueOrPullRequest"]
        return bodies.compactMap { body in
            let query = body["query"] as? String ?? ""
            return names.first { query.contains($0) }
        }
    }

    func variables(_ index: Int) -> [String: Any]? {
        bodies.indices.contains(index) ? bodies[index]["variables"] as? [String: Any] : nil
    }

    /// REST requests as "METHOD path", in order; each answered 200 with an empty object.
    private(set) var rest: [String] = []

    func send(_ method: String, path: String, body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { rest.append("\(method) \(path)") }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com\(path)")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data("{}".utf8), response)
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let data = lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private let k412 = editKey(412)
private let bug = LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")
private let docs = LabelRef(id: "LA_docs", name: "docs", color: nil)
private let alice = PersonRef(id: "U_alice", login: "alice", avatarURL: nil)
private let bob = PersonRef(id: "U_bob", login: "bob", avatarURL: nil)

private let both = #"{"data":{"add":{"clientMutationId":null},"remove":{"clientMutationId":null}}}"#
private let addOnly = #"{"data":{"add":{"clientMutationId":null}}}"#
private let found = #"{"data":{"repository":{"issueOrPullRequest":{"id":"I_1"}}}}"#
private let refused = #"{"data":{"add":null,"remove":null},"errors":[{"type":"FORBIDDEN","message":"nope"}]}"#

private func editor(_ t: QueueTransport) -> SetEditor {
    SetEditor(api: GitHubAPI(transport: t, auth: StaticTokenSource("test-token")))
}

@Suite struct SetEditorTests {
    @Test func labelsSendBothHalvesInOneRequest() async throws {
        let t = QueueTransport([both])
        let result = try await editor(t).apply(.labels(added: [docs], removed: [bug]), on: k412, contentId: "I_1")
        #expect(result == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
        #expect(t.operations == ["addLabelsToLabelable"])
        let variables = try #require(t.variables(0))
        #expect(variables["subject"] as? String == "I_1")
        #expect(variables["add"] as? [String] == ["LA_docs"])
        #expect(variables["remove"] as? [String] == ["LA_bug"])
    }

    @Test func assigneesSendUserIds() async throws {
        let t = QueueTransport([addOnly])
        _ = try await editor(t).apply(.assignees(added: [alice, bob], removed: []), on: k412, contentId: "I_1")
        #expect(t.operations == ["addAssigneesToAssignable"])
        let variables = try #require(t.variables(0))
        #expect(variables["subject"] as? String == "I_1")
        #expect(variables["add"] as? [String] == ["U_alice", "U_bob"])
        #expect(variables["remove"] == nil)
    }

    @Test func aMissingContentIdIsLookedUpFirst() async throws {
        let t = QueueTransport([found, both])
        _ = try await editor(t).apply(.labels(added: [docs], removed: [bug]), on: k412, contentId: nil)
        #expect(t.operations == ["issueOrPullRequest", "addLabelsToLabelable"])
        #expect(t.variables(1)?["subject"] as? String == "I_1")
    }

    @Test func aStatusChangeSendsNothing() async throws {
        let t = QueueTransport([])
        let change = EditChange.status(
            from: nil, to: BoardStatusValue(optionId: "o1", name: "Todo"), placement: .already)
        let result = try await editor(t).apply(change, on: k412, contentId: "I_1")
        #expect(t.bodies.isEmpty)
        #expect(result == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
    }

    @Test func editorSendsReviewersOverREST() async throws {
        let t = QueueTransport([])
        let change = EditChange.reviewers(added: [.user("alice")], removed: [.team(slug: "core", name: "Core")])
        let result = try await editor(t).apply(change, on: k412, contentId: nil)
        #expect(result == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
        #expect(t.bodies.isEmpty)
        #expect(t.rest == ["POST /repos/o/r/pulls/412/requested_reviewers", "DELETE /repos/o/r/pulls/412/requested_reviewers"])
    }

    @Test func bothHalvesRefusedThrowsWriteRefused() async {
        let t = QueueTransport([refused])
        await #expect(throws: APIError.writeRefused("nope")) {
            try await editor(t).apply(.labels(added: [docs], removed: [bug]), on: k412, contentId: "I_1")
        }
    }
}
