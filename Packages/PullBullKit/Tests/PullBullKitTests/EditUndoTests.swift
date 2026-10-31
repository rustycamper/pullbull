import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_100)
private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let bug = LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")
private let triage = LabelRef(id: "LA_triage", name: "triage", color: nil)
private let alice = PersonRef(id: "U_alice", login: "alice", avatarURL: nil)
private let bob = PersonRef(id: "U_bob", login: "bob", avatarURL: nil)
private let k412 = editKey(412)

private func record(at date: Date, _ change: EditChange = .labels(added: [bug], removed: [])) -> EditRecord {
    EditRecord(key: k412, change: change, madeAt: date, addedItemId: nil)
}

@Suite struct EditUndoTests {
    // MARK: Undo

    @Test func undoWithinTenSecondsOnce() {
        var undo = EditUndo()
        undo.remember(record(at: t0))
        #expect(undo.canUndo(now: t0 + 9.9))
        #expect(undo.take(now: t0 + 9.9) == record(at: t0))
        #expect(undo.take(now: t0 + 9.9) == nil)
        #expect(!undo.canUndo(now: t0 + 9.9))
    }

    @Test func undoExpires() {
        var undo = EditUndo()
        undo.remember(record(at: t0))
        #expect(!undo.canUndo(now: t0 + 10))
        #expect(undo.take(now: t0 + 10) == nil)
    }

    @Test func onlyTheLastEdit() {
        var undo = EditUndo()
        let a = record(at: t0)
        let b = record(at: t0 + 1, .assignees(added: [alice], removed: []))
        undo.remember(a)
        undo.remember(b)
        #expect(undo.take(now: t0 + 2) == b)
        #expect(undo.take(now: t0 + 2) == nil)
    }

    @Test func nothingToUndo() {
        var undo = EditUndo()
        #expect(!undo.canUndo(now: t0))
        #expect(undo.take(now: t0) == nil)
    }

    // MARK: Failure

    @Test func failureCopy() {
        let refused = APIError.writeRefused("you need write access to the acme board")
        #expect(EditMessage.failure(.status(from: todo, to: doing, placement: .already), on: k412, error: refused)
            == "Couldn't set Status on #412: you need write access to the acme board")
        #expect(EditMessage.failure(.status(from: todo, to: nil, placement: .already), on: k412, error: refused)
            == "Couldn't clear Status on #412: you need write access to the acme board")
        #expect(EditMessage.failure(.status(from: nil, to: todo, placement: .added), on: k412, error: refused)
            == "Couldn't add #412 to the board: you need write access to the acme board")
        #expect(EditMessage.failure(.labels(added: [bug], removed: []), on: k412, error: refused)
            == "Couldn't change labels on #412: you need write access to the acme board")
        #expect(EditMessage.failure(.assignees(added: [alice], removed: []), on: k412, error: refused)
            == "Couldn't change assignees on #412: you need write access to the acme board")
    }

    /// Undoing an add to the board takes it off again.
    @Test func failureToRemoveFromTheBoard() {
        let refused = APIError.writeRefused("nope")
        #expect(EditMessage.failure(.status(from: todo, to: nil, placement: .removed), on: k412, error: refused)
            == "Couldn't remove #412 from the board: nope")
    }

    @Test func failureOfflineUsesRefreshWording() {
        let offline = APIError.network("offline")
        #expect(EditMessage.failure(.status(from: todo, to: doing, placement: .already), on: k412, error: offline)
            == "Couldn't set Status on #412: " + RefreshError(offline).message)
    }

    // MARK: Partial

    @Test func partialCopy() {
        let result = SetChangeResult(addApplied: true, removeApplied: false, refusal: "nope")
        #expect(EditMessage.partial(.labels(added: [bug], removed: [triage]), on: k412, result: result)
            == "Added bug to #412, but couldn't remove triage: nope")
        #expect(EditMessage.partial(.labels(added: [bug], removed: []), on: k412,
            result: SetChangeResult(addApplied: true, removeApplied: true, refusal: nil)) == nil)
    }

    @Test func partialWhenTheAddFailed() {
        let result = SetChangeResult(addApplied: false, removeApplied: true, refusal: "nope")
        #expect(EditMessage.partial(.labels(added: [bug], removed: [triage]), on: k412, result: result)
            == "Removed triage from #412, but couldn't add bug: nope")
    }

    @Test func partialNamesPeopleByLoginCommaJoined() {
        let result = SetChangeResult(addApplied: true, removeApplied: false, refusal: "nope")
        #expect(EditMessage.partial(.assignees(added: [alice, bob], removed: [carol]), on: k412, result: result)
            == "Added alice, bob to #412, but couldn't remove carol: nope")
    }

    @Test func neitherPartAppliedReadsAsAFailure() {
        let result = SetChangeResult(addApplied: false, removeApplied: false, refusal: "nope")
        #expect(EditMessage.partial(.labels(added: [bug], removed: [triage]), on: k412, result: result)
            == "Couldn't change labels on #412: nope")
    }
}

private let carol = PersonRef(id: "U_carol", login: "carol", avatarURL: nil)
