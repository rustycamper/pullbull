import Foundation
import Testing
@testable import PullBullKit

private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let options = [StatusOption(id: "o1", name: "Todo"), StatusOption(id: "o2", name: "Doing")]

@Suite struct StatusEditTests {
    @Test func offeredOnTheBoardAndInTheOwnersRepos() {
        let snap = editSnapshot(board: [editIssue(412, status: todo)], options: options)
        #expect(StatusEdit.isOffered(editKey(412), in: snap))
        #expect(StatusEdit.isOffered(editKey(500), in: snap))
        #expect(StatusEdit.isOffered(PRKey(repo: "O/x", number: 1), in: snap))
        #expect(!StatusEdit.isOffered(PRKey(repo: "other/x", number: 1), in: snap))
    }

    /// A personal board takes only its user's own issues.
    @Test func personalBoardTakesItsUsersRepos() {
        let snap = editSnapshot(board: [], options: options, boardOwner: .user("me"))
        #expect(StatusEdit.isOffered(PRKey(repo: "me/x", number: 1), in: snap))
        #expect(!StatusEdit.isOffered(editKey(500), in: snap))
    }

    @Test func notOfferedWithoutABoardOrOptions() {
        #expect(!StatusEdit.isOffered(editKey(412), in: editSnapshot(board: [editIssue(412)], options: nil)))
        #expect(!StatusEdit.isOffered(editKey(412), in: editSnapshot(board: [editIssue(412)], options: [])))
        #expect(!StatusEdit.isOffered(editKey(412), in: editSnapshot(board: [], options: options, boardProject: nil)))
    }

    @Test func notOfferedWhileTheBoardFailed() {
        var snap = editSnapshot(board: [editIssue(412, status: todo)], options: options)
        snap.boardError = "nope"
        #expect(!StatusEdit.isOffered(editKey(412), in: snap))
    }

    @Test func changeOnTheBoard() {
        let snap = editSnapshot(board: [editIssue(412, status: todo)], options: options)
        #expect(StatusEdit.change(for: editKey(412), to: doing, in: snap)
            == .status(from: todo, to: doing, placement: .already))
        #expect(StatusEdit.change(for: editKey(412), to: nil, in: snap)
            == .status(from: todo, to: nil, placement: .already))
        #expect(StatusEdit.change(for: editKey(412), to: todo, in: snap) == nil)
    }

    @Test func changeAddsAnIssueNotOnTheBoard() {
        let snap = editSnapshot(board: [], created: [editIssue(500)], options: options)
        #expect(StatusEdit.change(for: editKey(500), to: todo, in: snap)
            == .status(from: nil, to: todo, placement: .added))
        #expect(StatusEdit.change(for: editKey(500), to: nil, in: snap) == nil)
    }

    @Test func noChangeWhereNotOffered() {
        let snap = editSnapshot(board: [], options: options)
        #expect(StatusEdit.change(for: PRKey(repo: "other/x", number: 1), to: todo, in: snap) == nil)
    }
}
