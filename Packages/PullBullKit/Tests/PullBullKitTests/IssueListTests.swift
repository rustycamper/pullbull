import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

private let todo = StatusOption(id: "opt1", name: "Todo")
private let inProgress = StatusOption(id: "opt2", name: "In Progress")
private let doneOption = StatusOption(id: "opt3", name: "Done")
private let options = [todo, inProgress, doneOption]

private func issue(
    _ n: Int, repo: String = "o/r", status: StatusOption? = nil, updated: Date = ago(1), open: Bool = true
) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: n), title: "i\(n)", url: URL(string: "https://x/\(n)")!,
        isOpen: open, createdAt: nil, updatedAt: updated, closedAt: nil,
        status: status.map { BoardStatusValue(optionId: $0.id, name: $0.name) })
}

private func snap(
    assigned: [BoardIssue]? = [], created: [BoardIssue]? = [], board: [BoardIssue] = [],
    boardError: String? = nil, assignedError: String? = nil, createdError: String? = nil
) -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: board,
        boardProject: 3, boardError: boardError,
        assignedIssues: assigned, createdIssues: created, boardStatusOptions: options,
        assignedIssuesError: assignedError, createdIssuesError: createdError,
        assignedIssuesFetchedAt: assigned == nil ? nil : ago(0.5))
}

private func built(_ s: Snapshot, settings: AppSettings = AppSettings()) -> (BuiltIssueTabs, IssueList) {
    let tabs = IssueTabBuilder.build(s, settings: settings, now: now)
    return (tabs, IssueList.build(tabs, snap: s, settings: settings))
}

private func numbers(_ list: IssueList, _ section: IssueSection) -> [Int]? {
    list.sections.first { $0.section == section }?.issues.map(\.key.number)
}

@Suite struct IssueListTests {
    @Test func anIssueAssignedAndCreatedShowsOnceUnderAssigned() {
        let mine = issue(1)
        let (tabs, list) = built(snap(assigned: [mine], created: [mine, issue(2)]))
        #expect(numbers(list, .assignedToYou) == [1])
        #expect(numbers(list, .youOpened) == [2])
        #expect(list.rowCount == 2)
        #expect(tabs.count(of: .created) == .current(2))
        #expect(tabs.count(of: .all) == nil)
    }

    @Test func createdCountKeepsTheDuplicate() {
        let mine = issue(1)
        let (tabs, _) = built(snap(assigned: [mine], created: [mine]))
        #expect(tabs.count(of: .created) == .current(1))
    }

    @Test func doneOnTheBoardLeavesAllEntirely() {
        let both = issue(1), createdOnly = issue(2), live = issue(3)
        let board = [issue(1, status: doneOption), issue(2, status: doneOption), issue(3, status: todo)]
        let (tabs, list) = built(snap(assigned: [both, live], created: [both, createdOnly], board: board))
        #expect(!list.sections.flatMap(\.issues).contains { [1, 2].contains($0.key.number) })
        #expect(numbers(list, .assignedToYou) == [3])
        #expect(tabs.created.issues.map(\.key.number).sorted() == [1, 2])
        #expect(IssueList.doneKeys(in: snap(board: board)) == [PRKey(repo: "o/r", number: 1), PRKey(repo: "o/r", number: 2)])
    }

    @Test func restOfTheBoardLeavesOutMineAndDone() {
        let board = [
            issue(1, status: todo), issue(2, status: todo), issue(3, status: doneOption), issue(4, status: inProgress),
        ]
        let (_, list) = built(snap(assigned: [issue(1)], created: [issue(2)], board: board))
        #expect(numbers(list, .assignedToYou) == [1])
        #expect(numbers(list, .youOpened) == [2])
        #expect(numbers(list, .restOfBoard) == [4])
    }

    @Test func noReadableBoardMeansNoRestAndNoDoneFiltering() {
        let (_, list) = built(snap(assigned: [issue(1)], board: [issue(1, status: doneOption)], boardError: "x"))
        #expect(!list.sections.contains { $0.section == .restOfBoard })
        #expect(numbers(list, .assignedToYou) == [1])
        #expect(list.status.isEmpty)
        #expect(IssueList.doneKeys(in: snap(board: [issue(1, status: doneOption)], boardError: "x")).isEmpty)
    }

    @Test func notLoadedAndFailedAreNeverEmpty() {
        let (_, loading) = built(snap(assigned: nil, created: [issue(2)]))
        let section = loading.sections.first { $0.section == .assignedToYou }
        #expect(section?.state == .loading)
        #expect(section?.issues.isEmpty == true)
        #expect(!loading.nothingAssigned)
        let (_, none) = built(snap(assigned: nil, created: nil))
        #expect(!none.isEmpty)

        let (_, failed) = built(snap(assigned: [], assignedError: "boom"))
        #expect(failed.sections.first?.state == .failed("boom"))
        #expect(!failed.isEmpty)

        let (_, stale) = built(snap(assigned: [issue(1)], assignedError: "boom"))
        #expect(stale.sections.first?.state == .stale("boom", since: ago(0.5)))
    }

    @Test func nothingAssignedOnlyWhenAssignedLoadedAndEmpty() {
        let (_, some) = built(snap(assigned: [], created: [issue(1)]))
        #expect(some.nothingAssigned)
        #expect(!some.isEmpty)
        let (_, empty) = built(snap(assigned: [], created: []))
        #expect(empty.isEmpty)
        #expect(!empty.nothingAssigned)
        let (_, withAssigned) = built(snap(assigned: [issue(1)]))
        #expect(!withAssigned.nothingAssigned)
    }

    @Test func boardStatusSortFollowsColumnOrder() {
        let board = [
            issue(1, status: inProgress, updated: ago(1)), issue(2, status: todo, updated: ago(5)),
            issue(3, updated: ago(0.1)), issue(4, status: todo, updated: ago(2)),
        ]
        var settings = AppSettings()
        settings.setSort(.boardStatus, for: IssueScope.all)
        let (_, list) = built(snap(board: board), settings: settings)
        #expect(numbers(list, .restOfBoard) == [4, 2, 1, 3])

        let (_, plain) = built(snap(board: board, boardError: "x"), settings: settings)
        #expect(plain.sections.isEmpty)
        let (_, unavailable) = built(snap(assigned: board.map { issue($0.key.number, updated: $0.updatedAt!) }, boardError: "x"), settings: settings)
        #expect(numbers(unavailable, .assignedToYou) == [3, 1, 4, 2])
    }

    @Test func noSectionSharesAPRFoldKey() {
        #expect(Set(IssueSection.allCases.map(\.rawValue)).isDisjoint(with: PRSection.allCases.map(\.rawValue)))
        #expect(IssueSection.doneStillOpen.title == "Done")
        #expect(IssueSection.allCases.map(\.rowTab) == [.assigned, .created, .board, .board, .board])
    }

    @Test func staleTabsNamesAssignedAndCreated() {
        let (tabs, _) = built(snap(created: [issue(1)], createdError: "boom"))
        #expect(tabs.staleTabs == [.created])
        let (both, _) = built(snap(assigned: [issue(2)], created: [issue(1)], assignedError: "a", createdError: "b"))
        #expect(both.staleTabs == [.assigned, .created])
    }

    @Test func aFocusNarrowsSectionsAndCountsHidden() {
        let (_, list) = built(snap(
            assigned: [issue(1, repo: "o/a"), issue(2, repo: "o/b")], created: [issue(3, repo: "o/b")],
            board: [issue(4, repo: "o/a", status: todo)]))
        let scoped = ListFocus(repo: RepoFocus(repo: "o/a"), time: nil).scope(list)
        #expect(scoped.list.sections.map(\.section) == [.assignedToYou, .restOfBoard])
        #expect(numbers(scoped.list, .assignedToYou) == [1])
        #expect(scoped.hiddenCount == 2)

        let (_, loading) = built(snap(assigned: nil, created: [issue(3, repo: "o/b")]))
        let kept = ListFocus(repo: RepoFocus(repo: "o/a"), time: nil).scope(loading)
        #expect(kept.list.sections.map(\.section) == [.assignedToYou])
        #expect(ScopedIssueList(unscoped: list).hiddenCount == 0)
    }
}
