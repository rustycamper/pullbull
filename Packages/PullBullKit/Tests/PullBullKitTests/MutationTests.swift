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

private func api(_ transport: QueueTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"))
}

private let applied = #"{"clientMutationId":null}"#

@Suite struct MutationTests {
    // MARK: Board

    @Test func setStatusSendsUpdateWithOption() async throws {
        let t = QueueTransport([#"{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_i1"}}}}"#])
        try await api(t).setStatus(project: "PVT_p1", item: "PVTI_i1", field: "PVTSSF_f1", option: "opt2")
        let body = try #require(t.bodies.first)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("updateProjectV2ItemFieldValue"))
        #expect(query.contains("singleSelectOptionId:$option"))
        #expect(body["variables"] as? [String: String]
            == ["project": "PVT_p1", "item": "PVTI_i1", "field": "PVTSSF_f1", "option": "opt2"])
    }

    @Test func setStatusNilClears() async throws {
        let t = QueueTransport([#"{"data":{"clearProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_i1"}}}}"#])
        try await api(t).setStatus(project: "PVT_p1", item: "PVTI_i1", field: "PVTSSF_f1", option: nil)
        let body = try #require(t.bodies.first)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("clearProjectV2ItemFieldValue"))
        #expect(!query.contains("updateProjectV2ItemFieldValue"))
        #expect(body["variables"] as? [String: String] == ["project": "PVT_p1", "item": "PVTI_i1", "field": "PVTSSF_f1"])
    }

    @Test func addToProjectReturnsItemId() async throws {
        let t = QueueTransport([#"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new"}}}}"#])
        #expect(try await api(t).addToProject(project: "PVT_p1", content: "I_kwDOB2") == "PVTI_new")
        let body = try #require(t.bodies.first)
        #expect((body["query"] as? String)?.contains("addProjectV2ItemById") == true)
        #expect(body["variables"] as? [String: String] == ["project": "PVT_p1", "content": "I_kwDOB2"])
    }

    @Test func deleteProjectItemSendsDelete() async throws {
        let t = QueueTransport([#"{"data":{"deleteProjectV2Item":{"deletedItemId":"PVTI_new"}}}"#])
        try await api(t).deleteProjectItem(project: "PVT_p1", item: "PVTI_new")
        let body = try #require(t.bodies.first)
        #expect((body["query"] as? String)?.contains("deleteProjectV2Item") == true)
        #expect(body["variables"] as? [String: String] == ["project": "PVT_p1", "item": "PVTI_new"])
    }

    @Test func refusedMutationThrowsWriteRefused() async {
        let t = QueueTransport([#"""
        {"data":{"updateProjectV2ItemFieldValue":null},\#
        "errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}
        """#])
        await #expect(throws: APIError.writeRefused("Resource not accessible by integration")) {
            try await api(t).setStatus(project: "p", item: "i", field: "f", option: "o")
        }
    }

    /// GitHub may answer a refused mutation with no data object at all.
    @Test func refusedMutationWithNullDataThrowsWriteRefused() async {
        let t = QueueTransport([#"{"data":null,"errors":[{"type":"FORBIDDEN","message":"nope"}]}"#])
        await #expect(throws: APIError.writeRefused("nope")) {
            try await api(t).addToProject(project: "p", content: "c")
        }
    }

    @Test func otherMutationErrorIsGraphQL() async {
        let t = QueueTransport([#"""
        {"data":{"addProjectV2ItemById":null},"errors":[{"type":"NOT_FOUND","message":"Could not resolve"}]}
        """#])
        await #expect(throws: APIError.graphQL("Could not resolve")) {
            try await api(t).addToProject(project: "p", content: "c")
        }
    }

    // MARK: Labels and assignees

    @Test func labelsAddAndRemoveGoInOneRequest() async throws {
        let t = QueueTransport([#"{"data":{"add":\#(applied),"remove":\#(applied)}}"#])
        let result = try await api(t).changeLabels(of: "I_1", adding: ["LA_bug"], removing: ["LA_triage"])
        #expect(t.bodies.count == 1)
        #expect(result == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
        let body = try #require(t.bodies.first)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("add: addLabelsToLabelable"))
        #expect(query.contains("remove: removeLabelsFromLabelable"))
        let variables = try #require(body["variables"] as? [String: Any])
        #expect(variables["subject"] as? String == "I_1")
        #expect(variables["add"] as? [String] == ["LA_bug"])
        #expect(variables["remove"] as? [String] == ["LA_triage"])
    }

    @Test func labelsPartialSuccess() async throws {
        let t = QueueTransport([#"""
        {"data":{"add":\#(applied),"remove":null},\#
        "errors":[{"type":"FORBIDDEN","path":["remove"],"message":"nope"}]}
        """#])
        let result = try await api(t).changeLabels(of: "I_1", adding: ["LA_bug"], removing: ["LA_triage"])
        #expect(result == SetChangeResult(addApplied: true, removeApplied: false, refusal: "nope"))
    }

    @Test func bothPartsRefusedThrows() async {
        let t = QueueTransport([#"""
        {"data":{"add":null,"remove":null},"errors":[{"type":"FORBIDDEN","message":"nope"}]}
        """#])
        await #expect(throws: APIError.writeRefused("nope")) {
            try await api(t).changeLabels(of: "I_1", adding: ["LA_bug"], removing: ["LA_triage"])
        }
    }

    @Test func onlyAddSendsNoRemoveAlias() async throws {
        let t = QueueTransport([#"{"data":{"add":\#(applied)}}"#])
        let result = try await api(t).changeLabels(of: "I_1", adding: ["LA_bug"], removing: [])
        #expect(result == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
        let body = try #require(t.bodies.first)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("addLabelsToLabelable"))
        #expect(!query.contains("removeLabelsFromLabelable"))
        #expect((body["variables"] as? [String: Any])?["remove"] == nil)
    }

    @Test func noChangeSendsNothing() async throws {
        let t = QueueTransport([])
        #expect(try await api(t).changeAssignees(of: "I_1", adding: [], removing: [])
            == SetChangeResult(addApplied: true, removeApplied: true, refusal: nil))
        #expect(t.bodies.isEmpty)
    }

    @Test func assigneesUseAssignableMutations() async throws {
        let t = QueueTransport([#"{"data":{"add":\#(applied),"remove":\#(applied)}}"#])
        _ = try await api(t).changeAssignees(of: "I_1", adding: ["U_alice"], removing: ["U_bob"])
        let body = try #require(t.bodies.first)
        let query = try #require(body["query"] as? String)
        #expect(query.contains("add: addAssigneesToAssignable"))
        #expect(query.contains("remove: removeAssigneesFromAssignable"))
        let variables = try #require(body["variables"] as? [String: Any])
        #expect(variables["add"] as? [String] == ["U_alice"])
        #expect(variables["remove"] as? [String] == ["U_bob"])
    }

    // MARK: Lookup

    @Test func nodeIdLooksUpByNumber() async throws {
        let t = QueueTransport([#"{"data":{"repository":{"issueOrPullRequest":{"id":"I_kwDOB2"}}}}"#])
        #expect(try await api(t).nodeId(of: PRKey(repo: "acme/widgets", number: 412)) == "I_kwDOB2")
        let variables = try #require(t.bodies.first?["variables"] as? [String: Any])
        #expect(variables["owner"] as? String == "acme")
        #expect(variables["name"] as? String == "widgets")
        #expect(variables["n"] as? Int == 412)
    }

    @Test func nodeIdOfAMissingItemIsNotFound() async {
        let t = QueueTransport([#"{"data":{"repository":{"issueOrPullRequest":null}}}"#])
        await #expect(throws: APIError.notFound("acme/widgets#412 not found")) {
            try await api(t).nodeId(of: PRKey(repo: "acme/widgets", number: 412))
        }
    }
}
