import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_100)
private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let options = [StatusOption(id: "o1", name: "Todo"), StatusOption(id: "o2", name: "Doing")]
private let k412 = editKey(412)
private let k413 = editKey(413)
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
        _ = s.begin(move, on: k412, at: t0)
        let record = EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil)
        s.applied(record)
        #expect(s.canUndo(now: t0 + 9))
        #expect(s.takeUndo(now: t0 + 9) == record)
        #expect(s.takeUndo(now: t0 + 9) == nil)
    }

    @Test func aNewEditClearsTheOldUndo() {
        var s = EditSession()
        _ = s.begin(move, on: k412, at: t0)
        s.applied(EditRecord(key: k412, change: move, madeAt: t0, addedItemId: nil))
        _ = s.begin(move, on: k413, at: t0 + 1)
        #expect(!s.canUndo(now: t0 + 2))
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
}
