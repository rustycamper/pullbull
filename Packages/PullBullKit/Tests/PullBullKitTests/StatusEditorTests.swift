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
        let names = ["updateProjectV2ItemFieldValue", "clearProjectV2ItemFieldValue", "addProjectV2ItemById",
                     "deleteProjectV2Item", "issueOrPullRequest"]
        return bodies.compactMap { body in
            let query = body["query"] as? String ?? ""
            return names.first { query.contains($0) }
        }
    }

    func variables(_ index: Int) -> [String: String]? {
        bodies.indices.contains(index) ? bodies[index]["variables"] as? [String: String] : nil
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

private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let k412 = editKey(412)
private let board = BoardIds(projectId: "PVT_1", statusFieldId: "F_1")

private let updated = #"{"data":{"updateProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_1"}}}}"#
private let cleared = #"{"data":{"clearProjectV2ItemFieldValue":{"projectV2Item":{"id":"PVTI_1"}}}}"#
private let addedNew = #"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_new"}}}}"#
private let addedExisting = #"{"data":{"addProjectV2ItemById":{"item":{"id":"PVTI_1"}}}}"#
private let deleted = #"{"data":{"deleteProjectV2Item":{"deletedItemId":"PVTI_new"}}}"#
private let found = #"{"data":{"repository":{"issueOrPullRequest":{"id":"I_1"}}}}"#
private let refused = #"{"data":null,"errors":[{"type":"FORBIDDEN","message":"nope"}]}"#

private func editor(_ t: QueueTransport) -> StatusEditor {
    StatusEditor(api: GitHubAPI(transport: t, auth: StaticTokenSource("test-token")))
}

@Suite struct StatusEditorTests {
    @Test func setOnTheBoard() async throws {
        let t = QueueTransport([updated])
        let added = try await editor(t).apply(
            .status(from: todo, to: doing, placement: .already), on: k412, itemId: "PVTI_1", contentId: "I_1", board: board)
        #expect(added == nil)
        #expect(t.operations == ["updateProjectV2ItemFieldValue"])
        #expect(t.variables(0) == ["project": "PVT_1", "item": "PVTI_1", "field": "F_1", "option": "o2"])
    }

    @Test func clearOnTheBoard() async throws {
        let t = QueueTransport([cleared])
        _ = try await editor(t).apply(
            .status(from: todo, to: nil, placement: .already), on: k412, itemId: "PVTI_1", contentId: nil, board: board)
        #expect(t.operations == ["clearProjectV2ItemFieldValue"])
    }

    /// A board item cached without its node ID: adding returns the item already on the board.
    @Test func oldCacheItemFoundByAdding() async throws {
        let t = QueueTransport([addedExisting, updated])
        let added = try await editor(t).apply(
            .status(from: todo, to: doing, placement: .already), on: k412, itemId: nil, contentId: "I_1", board: board)
        #expect(added == nil)
        #expect(t.operations == ["addProjectV2ItemById", "updateProjectV2ItemFieldValue"])
        #expect(t.variables(0) == ["project": "PVT_1", "content": "I_1"])
        #expect(t.variables(1)?["item"] == "PVTI_1")
    }

    @Test func addThenSet() async throws {
        let t = QueueTransport([addedNew, updated])
        let added = try await editor(t).apply(
            .status(from: nil, to: todo, placement: .added), on: k412, itemId: nil, contentId: "I_1", board: board)
        #expect(added == "PVTI_new")
        #expect(t.operations == ["addProjectV2ItemById", "updateProjectV2ItemFieldValue"])
        #expect(t.variables(1)?["item"] == "PVTI_new")
        #expect(t.variables(1)?["option"] == "o1")
    }

    @Test func contentLookedUpWhenMissing() async throws {
        let t = QueueTransport([found, addedNew, updated])
        _ = try await editor(t).apply(
            .status(from: nil, to: todo, placement: .added), on: k412, itemId: nil, contentId: nil, board: board)
        #expect(t.operations == ["issueOrPullRequest", "addProjectV2ItemById", "updateProjectV2ItemFieldValue"])
        #expect(t.variables(1)?["content"] == "I_1")
    }

    @Test func addThenSetFailsDeletesTheItem() async throws {
        let t = QueueTransport([addedNew, refused, deleted])
        await #expect(throws: APIError.writeRefused("nope")) {
            _ = try await editor(t).apply(
                .status(from: nil, to: todo, placement: .added), on: k412, itemId: nil, contentId: "I_1", board: board)
        }
        #expect(t.operations == ["addProjectV2ItemById", "updateProjectV2ItemFieldValue", "deleteProjectV2Item"])
        #expect(t.variables(2) == ["project": "PVT_1", "item": "PVTI_new"])
    }

    @Test func undoOfAnAddDeletes() async throws {
        let t = QueueTransport([deleted])
        _ = try await editor(t).apply(
            .status(from: todo, to: nil, placement: .removed), on: k412, itemId: "PVTI_new", contentId: "I_1", board: board)
        #expect(t.operations == ["deleteProjectV2Item"])
        #expect(t.variables(0) == ["project": "PVT_1", "item": "PVTI_new"])
    }

    @Test func withoutBoardIdsThrows() async throws {
        let t = QueueTransport([])
        let change = EditChange.status(from: todo, to: doing, placement: .already)
        await #expect(throws: EditError.boardNotLoaded) {
            _ = try await editor(t).apply(change, on: k412, itemId: "PVTI_1", contentId: "I_1", board: nil)
        }
        #expect(t.bodies.isEmpty)
        #expect(EditMessage.failure(change, on: k412, error: EditError.boardNotLoaded)
            == "Couldn't set Status on #412: the board hasn't finished loading. Try again in a moment")
    }

    @Test func fieldMissingThrows() async throws {
        let t = QueueTransport([])
        await #expect(throws: EditError.boardNotLoaded) {
            _ = try await editor(t).apply(
                .status(from: todo, to: doing, placement: .already), on: k412, itemId: "PVTI_1", contentId: "I_1",
                board: BoardIds(projectId: "PVT_1", statusFieldId: nil))
        }
    }

    @Test func labelChangesSendNothing() async throws {
        let t = QueueTransport([])
        let added = try await editor(t).apply(
            .labels(added: [LabelRef(id: "L", name: "bug", color: nil)], removed: []), on: k412, itemId: "PVTI_1",
            contentId: "I_1", board: board)
        #expect(added == nil)
        #expect(t.bodies.isEmpty)
    }
}
