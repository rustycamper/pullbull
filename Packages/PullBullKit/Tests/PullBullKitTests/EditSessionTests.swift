import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_100)
private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let options = [StatusOption(id: "o1", name: "Todo"), StatusOption(id: "o2", name: "Doing")]
private let k412 = editKey(412)
private let k413 = editKey(413)
private let bug = LabelRef(id: "LA_bug", name: "bug", color: nil)
private let docs = LabelRef(id: "LA_docs", name: "docs", color: nil)
private let url412 = URL(string: "https://github.com/o/r/issues/412")!
private let move = EditChange.status(from: todo, to: doing, placement: .already)
private let snap = editSnapshot(board: [editIssue(412, status: todo), editIssue(413, status: todo)], options: options)

private func status(_ key: PRKey, _ session: EditSession, in snapshot: Snapshot = snap) -> BoardStatusValue? {
    session.overrides.apply(to: snapshot).boardIssues.first { $0.key == key }?.status
}

@Suite struct EditSessionTests {
    @Test func beginShowsTheEditAndClearsTheFailure() {
        var s = EditSession()
        let first = s.begin(move, on: k412, at: t0)
        s.failed(first, change: move, on: k412, url: url412, error: APIError.writeRefused("nope"))
        #expect(s.failure != nil)
        _ = s.begin(move, on: k412, at: t0 + 1)
        #expect(s.failure == nil)
        #expect(status(k412, s) == doing)
    }

    @Test func appliedEditCanBeUndoneOnce() {
        var s = EditSession()
        let id = s.begin(move, on: k412, at: t0)
        let record = EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil)
        s.applied(id, record)
        #expect(s.canUndo(now: t0 + 9))
        #expect(s.takeUndo(now: t0 + 9) == record)
        #expect(s.takeUndo(now: t0 + 9) == nil)
    }

    @Test func aNewEditClearsTheOldUndo() {
        var s = EditSession()
        let id = s.begin(move, on: k412, at: t0)
        s.applied(id, EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil))
        _ = s.begin(move, on: k413, at: t0 + 1)
        #expect(!s.canUndo(now: t0 + 2))
    }

    /// Edit A, then edit B before A's answer: A landing late doesn't make ⌘Z take back A.
    @Test func aLateAnswerToAnOlderEditIsNotUndoable() {
        var s = EditSession()
        let a = s.begin(move, on: k412, at: t0)
        _ = s.begin(move, on: k413, at: t0 + 0.2)
        s.applied(a, EditRecord(key: k412, change: move, madeAt: t0 + 0.5, addedItemId: nil))
        #expect(!s.canUndo(now: t0 + 1))
    }

    /// Typing in the search field after an edit hands ⌘Z to the text, also when the edit's answer
    /// lands after the typing.
    @Test func typingAfterAnEditHandsUndoToTheText() {
        var s = EditSession()
        let a = s.begin(move, on: k412, at: t0)
        s.applied(a, EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil))
        s.typed()
        #expect(!s.canUndo(now: t0 + 1))
        let b = s.begin(move, on: k413, at: t0 + 2)
        s.typed()
        s.applied(b, EditRecord(key: k413, change: move, madeAt: t0 + 2, addedItemId: nil))
        #expect(!s.canUndo(now: t0 + 3))
        #expect(status(k413, s) == doing)
    }

    /// Another board's fetch drops the edits shown and the undo, so ⌘Z can't write to the new board.
    @Test func switchingBoardsForgetsTheEdits() {
        var s = EditSession()
        s.reconcile(with: snap, now: t0)
        let id = s.begin(move, on: k412, at: t0)
        s.applied(id, EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil))
        let other = editSnapshot(
            board: [editIssue(412, status: todo), editIssue(413, status: todo)], options: options, boardProject: 2)
        s.reconcile(with: other, now: t0 + 1)
        #expect(s.overrides.isEmpty)
        #expect(!s.canUndo(now: t0 + 2))
    }

    @Test func theSameBoardKeepsTheUndo() {
        var s = EditSession()
        s.reconcile(with: snap, now: t0)
        let id = s.begin(move, on: k412, at: t0)
        s.applied(id, EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil))
        s.reconcile(with: snap, now: t0 + 1)
        #expect(s.canUndo(now: t0 + 2))
    }

    @Test func failedDropsOnlyItsOverrideAndSaysWhy() {
        var s = EditSession()
        let a = s.begin(move, on: k412, at: t0)
        _ = s.begin(move, on: k413, at: t0 + 1)
        s.failed(a, change: move, on: k412, url: url412, error: APIError.writeRefused("nope"))
        #expect(status(k412, s) == todo)
        #expect(status(k413, s) == doing)
        #expect(s.failure == EditFailure(text: "Couldn't set Status on #412: nope", url: url412))
    }

    @Test func staleFetchKeepsTheEdit() {
        var s = EditSession()
        _ = s.begin(move, on: k412, at: t0)
        s.reconcile(with: snap, now: t0 + 5)
        #expect(status(k412, s) == doing)
    }

    @Test func agreeingFetchEndsTheOverride() {
        var s = EditSession()
        _ = s.begin(move, on: k412, at: t0)
        let fetched = editSnapshot(board: [editIssue(412, status: doing)], options: options)
        s.reconcile(with: fetched, now: t0 + 5)
        #expect(s.overrides.isEmpty)
    }

    @Test func dismissFailure() {
        var s = EditSession()
        let a = s.begin(move, on: k412, at: t0)
        s.failed(a, change: move, on: k412, url: url412, error: APIError.writeRefused("nope"))
        s.dismissFailure()
        #expect(s.failure == nil)
    }

    // MARK: Partly applied

    private let swap = EditChange.labels(added: [docs], removed: [bug])
    private let addedOnly = SetChangeResult(addApplied: true, removeApplied: false, refusal: "nope")

    private func labels(_ session: EditSession) -> [String] {
        session.overrides.apply(to: editIssue(412, labels: ["bug"])).labels
    }

    @Test func partlyAppliedKeepsTheAppliedHalfAndArmsUndoForIt() {
        var s = EditSession()
        let id = s.begin(swap, on: k412, at: t0)
        #expect(labels(s) == ["docs"])
        s.partlyApplied(id, change: swap, result: addedOnly, on: k412, url: url412, isUndo: false, at: t0 + 1)
        #expect(labels(s) == ["bug", "docs"])
        #expect(s.failure?.text == "Added docs to #412, but couldn't remove bug: nope")
        #expect(s.failure?.url == url412)
        #expect(s.takeUndo(now: t0 + 2)?.change == .labels(added: [docs], removed: []))
    }

    @Test func partlyAppliedToAnOlderEditDoesNotArmUndo() {
        var s = EditSession()
        let id = s.begin(swap, on: k412, at: t0)
        _ = s.begin(move, on: k413, at: t0 + 0.2)
        s.partlyApplied(id, change: swap, result: addedOnly, on: k412, url: url412, isUndo: false, at: t0 + 1)
        #expect(labels(s) == ["bug", "docs"])
        #expect(!s.canUndo(now: t0 + 2))
    }

    @Test func aPartlyAppliedUndoDoesNotArmUndo() {
        var s = EditSession()
        let id = s.begin(swap, on: k412, at: t0)
        s.partlyApplied(id, change: swap, result: addedOnly, on: k412, url: url412, isUndo: true, at: t0 + 1)
        #expect(s.failure != nil)
        #expect(!s.canUndo(now: t0 + 2))
    }

    @Test func keepingDropsTheRefusedHalf() {
        #expect(swap.keeping(addedOnly) == .labels(added: [docs], removed: []))
        let removedOnly = SetChangeResult(addApplied: false, removeApplied: true, refusal: "nope")
        #expect(swap.keeping(removedOnly) == .labels(added: [], removed: [bug]))
        let alice = PersonRef(id: "U_a", login: "alice", avatarURL: nil)
        #expect(EditChange.assignees(added: [alice], removed: []).keeping(removedOnly) == .assignees(added: [], removed: []))
        #expect(move.keeping(addedOnly) == move)
    }
}
