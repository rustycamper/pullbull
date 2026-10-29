import Foundation
import Testing
@testable import PullBullKit

private func key(_ n: Int) -> PRKey { PRKey(repo: "o/a", number: n) }

private func issue(_ n: Int) -> BoardIssue {
    BoardIssue(key: key(n), title: "i\(n)", url: URL(string: "https://x/\(n)")!, isOpen: true)
}

private let todo = StatusOption(id: "opt-todo", name: "Todo")
private let doing = StatusOption(id: "opt-doing", name: "In progress")
private let board = BoardRef.org("acme", 3)

@Suite struct LaneFoldsTests {
    @Test func lanesStartOpen() {
        let folds = LaneFolds()
        #expect(!folds.isFolded(.status(todo), on: board))
        #expect(!folds.isFolded(.noStatus, on: board))
    }

    @Test func toggleFoldsAndOpens() {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        #expect(folds.isFolded(.status(todo), on: board))
        #expect(!folds.isFolded(.status(doing), on: board))
        folds.toggle(.status(todo), on: board)
        #expect(!folds.isFolded(.status(todo), on: board))
        #expect(folds == LaneFolds())
    }

    @Test func noStatusAndNotOnBoardFold() {
        var folds = LaneFolds()
        folds.toggle(.noStatus, on: board)
        folds.toggle(.notOnBoard, on: board)
        #expect(folds.isFolded(.noStatus, on: board))
        #expect(folds.isFolded(.notOnBoard, on: board))
    }

    @Test func repoAllAndDoneNeverFold() {
        var folds = LaneFolds()
        for kind in [IssueGroupKind.repo("o/a"), .all, .done] {
            folds.toggle(kind, on: board)
            #expect(!folds.isFolded(kind, on: board))
        }
        #expect(folds == LaneFolds())
    }

    /// Keyed by option id: a renamed lane keeps its state, a new option with the old name doesn't take it.
    @Test func keyedByOptionIDNotName() {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        #expect(folds.isFolded(.status(StatusOption(id: "opt-todo", name: "Backlog")), on: board))
        #expect(!folds.isFolded(.status(StatusOption(id: "opt-other", name: "Todo")), on: board))
    }

    @Test func keyedByBoard() {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        #expect(folds.isFolded(.status(todo), on: .org("ACME", 3)))
        #expect(!folds.isFolded(.status(todo), on: .org("acme", 4)))
        #expect(!folds.isFolded(.status(todo), on: .user("acme", 3)))
        #expect(!folds.isFolded(.status(todo), on: .org("other", 3)))
    }

    @Test func shownFoldedPerTab() {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        folds.toggle(.status(doing), on: board, in: .assigned)
        let groups = [
            IssueGroup(kind: .status(todo), issues: [issue(1)], counted: true),
            IssueGroup(kind: .status(doing), issues: [issue(2)], counted: true),
        ]
        #expect(folds.shownFolded(groups, tab: .board, board: board, searching: false) == [.status(todo)])
        #expect(folds.shownFolded(groups, tab: .assigned, board: board, searching: false) == [.status(doing)])
        #expect(folds.shownFolded(groups, tab: .created, board: board, searching: false).isEmpty)
        #expect(folds.shownFolded(groups, tab: .board, board: nil, searching: false).isEmpty)
    }

    /// Folding a lane on Assigned leaves the same lane on Board open, and back.
    @Test func tabsFoldSeparately() {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board, in: .assigned)
        #expect(folds.isFolded(.status(todo), on: board, in: .assigned))
        #expect(!folds.isFolded(.status(todo), on: board, in: .board))
        folds.toggle(.status(todo), on: board, in: .board)
        folds.toggle(.status(todo), on: board, in: .assigned)
        #expect(!folds.isFolded(.status(todo), on: board, in: .assigned))
        #expect(folds.isFolded(.status(todo), on: board, in: .board))
    }

    /// Folds saved before Assigned folded are keyed by board alone; they stay Board's.
    @Test func savedBoardFoldsStayOnBoard() throws {
        let saved = #"{"org:acme#3":["opt-todo"]}"#
        let folds = try JSONDecoder().decode(LaneFolds.self, from: Data(saved.utf8))
        #expect(folds.isFolded(.status(todo), on: board, in: .board))
        #expect(!folds.isFolded(.status(todo), on: board, in: .assigned))
    }

    /// Board keeps writing the bare board key; other tabs write theirs prefixed.
    @Test func boardKeyStaysBare() throws {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        folds.toggle(.status(doing), on: board, in: .assigned)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(folds)) as? [String: [String]]
        #expect(json == ["org:acme#3": ["opt-todo"], "assigned|org:acme#3": ["opt-doing"]])
    }

    /// A search shows every lane open and leaves the stored folds as they were.
    @Test func searchShowsEverything() {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        folds.toggle(.noStatus, on: board)
        let before = folds
        let groups = [
            IssueGroup(kind: .status(todo), issues: [issue(1)], counted: true),
            IssueGroup(kind: .noStatus, issues: [issue(2)], counted: true),
        ]
        let shown = folds.shownFolded(groups, tab: .board, board: board, searching: true)
        #expect(shown.isEmpty)
        #expect(ListNavigation.issueKeys(IssueTabContents(groups: groups), doneExpanded: false, folded: shown)
            .map(\.number) == [1, 2])
        #expect(folds == before)
        #expect(folds.shownFolded(groups, tab: .board, board: board, searching: false).count == 2)
    }

    @Test func codableRoundTrip() throws {
        var folds = LaneFolds()
        folds.toggle(.status(todo), on: board)
        folds.toggle(.noStatus, on: .user("me", 1))
        folds.toggle(.status(doing), on: board, in: .assigned)
        let data = try JSONEncoder().encode(folds)
        #expect(try JSONDecoder().decode(LaneFolds.self, from: data) == folds)
    }

    @Test func settingsRoundTripKeepsFolds() throws {
        var settings = AppSettings()
        settings.laneFolds.toggle(.status(doing), on: board)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.laneFolds.isFolded(.status(doing), on: board))
    }

    /// Settings saved before lanes folded have no `laneFolds`: every lane opens, the rest still loads.
    @Test func oldSettingsWithoutFoldsDecode() throws {
        let old = #"{"account":"me","refreshMinutes":5,"projectNumber":3,"projectOwner":{"kind":"org","login":"acme"}}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.laneFolds == LaneFolds())
        #expect(decoded.refreshMinutes == 5)
    }

    // MARK: Navigation

    @Test func foldedLaneRowsAreSkipped() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .status(todo), issues: [issue(1), issue(2)], counted: true),
            IssueGroup(kind: .status(doing), issues: [issue(3)], counted: true),
            IssueGroup(kind: .noStatus, issues: [issue(4)], counted: true),
            IssueGroup(kind: .done, issues: [issue(5)], counted: false),
        ])
        let keys = ListNavigation.issueKeys(contents, doneExpanded: true, folded: [.status(doing)])
        #expect(keys.map(\.number) == [1, 2, 4, 5])
        #expect(ListNavigation.move(key(2), by: 1, in: keys) == key(4))
        #expect(ListNavigation.move(key(4), by: -1, in: keys) == key(2))
    }

    @Test func foldingMovesSelectionToNextShownRow() {
        let old = [key(1), key(2), key(3), key(4)]
        // Lane of 1 and 2 folded: the selection moves below it.
        #expect(ListNavigation.selection(key(1), from: old, to: [key(3), key(4)]) == key(3))
        // A shown selection stays.
        #expect(ListNavigation.selection(key(4), from: old, to: [key(3), key(4)]) == key(4))
        // The last lane folded: nothing below, so the selection clears.
        #expect(ListNavigation.selection(key(4), from: old, to: [key(1), key(2)]) == nil)
        #expect(ListNavigation.selection(nil, from: old, to: old) == nil)
    }
}
