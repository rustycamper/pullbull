import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

private let todo = StatusOption(id: "opt1", name: "Todo")
private let inProgress = StatusOption(id: "opt2", name: "In progress")
private let done = StatusOption(id: "opt3", name: "Done")
private let options = [todo, inProgress, done]

private func issue(
    _ n: Int, repo: String = "o/r", open: Bool = true, status: String? = nil, updated: Date,
    closed: Date? = nil
) -> BoardIssue {
    let value = status.map { id in
        BoardStatusValue(optionId: id, name: options.first { $0.id == id }?.name ?? "Gone")
    }
    return BoardIssue(
        key: PRKey(repo: repo, number: n), title: "i\(n)", url: URL(string: "https://x/\(n)")!,
        isOpen: open, updatedAt: updated, closedAt: closed, status: value)
}

private func snap(
    assigned: [BoardIssue]? = [], created: [BoardIssue]? = [], board: [BoardIssue] = [],
    statusOptions: [StatusOption]? = options, boardProject: Int? = 3, boardError: String? = nil,
    review: [PullRequest] = []
) -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: review, mine: [], team: [], recentlyClosed: [], boardIssues: board,
        boardProject: boardProject, boardError: boardError,
        assignedIssues: assigned, createdIssues: created, boardStatusOptions: statusOptions)
}

private func reviewPR(_ n: Int) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "o/r", number: n), title: "p\(n)", url: URL(string: "https://x/p\(n)")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: ago(2), updatedAt: ago(1), closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil, latestReviews: [],
        reviewRequests: [.user("me")])
}

private func isRepo(_ group: IssueGroup) -> Bool {
    if case .repo = group.kind { return true }
    return false
}

@Suite struct IssueTabBuilderTests {
    @Test func countEqualsCountedGroupRows() {
        let board = [
            issue(1, status: "opt1", updated: ago(1)), issue(2, status: "opt3", updated: ago(2)),
            issue(3, open: false, updated: ago(3), closed: ago(3)), issue(4, updated: ago(4)),
        ]
        let tabs = IssueTabBuilder.build(
            snap(
                assigned: [issue(1, updated: ago(1)), issue(5, repo: "o/s", updated: ago(2))],
                created: [issue(6, updated: ago(1)), issue(7, repo: "o/s", updated: ago(5))],
                board: board),
            settings: AppSettings(), now: now)
        for tab in IssueTab.allCases {
            let contents = tabs.contents(tab)!
            #expect(contents.count == contents.groups.filter(\.counted).flatMap(\.issues).count)
            #expect(contents.issues == contents.groups.flatMap(\.issues))
        }
        #expect(tabs.board?.count == 2)
    }

    @Test func assignedFollowsBoardOptionOrder() {
        let board = [
            issue(1, status: "opt2", updated: ago(1)), issue(2, status: "opt1", updated: ago(1)),
            issue(4, updated: ago(1)),
        ]
        let assigned = [
            issue(1, updated: ago(1)), issue(2, updated: ago(2)), issue(3, updated: ago(3)),
            issue(4, updated: ago(4)),
        ]
        let tabs = IssueTabBuilder.build(snap(assigned: assigned, board: board), settings: AppSettings(), now: now)
        #expect(tabs.statusKnown)
        #expect(tabs.assigned.groups.map(\.title) == ["Todo", "In progress", "No status", "Not on board"])
        #expect(tabs.assigned.groups.map(\.kind) == [.status(todo), .status(inProgress), .noStatus, .notOnBoard])
        #expect(tabs.assigned.groups.map { $0.issues.map(\.key.number) } == [[2], [1], [4], [3]])
        #expect(tabs.assigned.groups.allSatisfy { $0.counted })
        #expect(tabs.assigned.count == 4)
    }

    @Test func groupsSortByUpdatedThenRepoThenNumber() {
        let assigned = [
            issue(3, updated: ago(1)), issue(1, repo: "o/a", updated: ago(1)),
            BoardIssue(key: PRKey(repo: "o/r", number: 9), title: "x", url: URL(string: "https://x/9")!, isOpen: true),
            issue(2, updated: ago(1)), issue(5, updated: ago(0.5)), issue(2, updated: ago(1)),
        ]
        var s = AppSettings()
        s.grouping = .none
        let tabs = IssueTabBuilder.build(snap(created: assigned), settings: s, now: now)
        #expect(tabs.created.groups.map(\.kind) == [.all])
        #expect(tabs.created.issues.map(\.key.number) == [5, 1, 2, 3, 9])
    }

    @Test func boardFoldsDoneLast14DaysNotCounted() {
        let board = [
            issue(1, status: "opt1", updated: ago(1)),
            issue(2, status: "opt3", updated: ago(3)),
            issue(3, open: false, status: "opt2", updated: ago(1), closed: ago(10)),
            issue(4, open: false, status: "opt3", updated: ago(1), closed: ago(20)),
        ]
        let tabs = IssueTabBuilder.build(snap(board: board), settings: AppSettings(), now: now)
        #expect(tabs.board?.groups.map(\.kind) == [.status(todo), .done])
        #expect(tabs.board?.groups.last?.issues.map(\.key.number) == [2, 3])
        #expect(tabs.board?.groups.last?.counted == false)
        #expect(tabs.board?.groups.last?.title == "Done")
        #expect(tabs.board?.count == 1)
    }

    @Test func noDoneOptionFoldsClosedOnly() {
        let backlog = StatusOption(id: "b", name: "Backlog")
        let doing = StatusOption(id: "d", name: "Doing")
        let board = [
            BoardIssue(
                key: PRKey(repo: "o/r", number: 5), title: "i5", url: URL(string: "https://x/5")!, isOpen: false,
                updatedAt: ago(2), closedAt: ago(2), status: BoardStatusValue(optionId: "d", name: "Doing")),
            BoardIssue(
                key: PRKey(repo: "o/r", number: 6), title: "i6", url: URL(string: "https://x/6")!, isOpen: true,
                updatedAt: ago(1), status: BoardStatusValue(optionId: "d", name: "Doing")),
        ]
        let tabs = IssueTabBuilder.build(
            snap(board: board, statusOptions: [backlog, doing]), settings: AppSettings(), now: now)
        #expect(tabs.board?.groups.map(\.kind) == [.status(doing), .done])
        #expect(tabs.board?.groups.last?.issues.map(\.key.number) == [5])
        #expect(tabs.board?.count == 1)
    }

    @Test func unknownOptionGoesToNoStatus() {
        let board = [issue(1, status: "gone", updated: ago(1)), issue(2, status: "opt1", updated: ago(1))]
        let tabs = IssueTabBuilder.build(
            snap(assigned: [issue(1, updated: ago(1))], board: board), settings: AppSettings(), now: now)
        #expect(tabs.board?.groups.map(\.kind) == [.status(todo), .noStatus])
        #expect(tabs.board?.groups.last?.issues.map(\.key.number) == [1])
        #expect(tabs.board?.groups.last?.counted == true)
        #expect(tabs.board?.count == 2)
        #expect(tabs.assigned.groups.map(\.kind) == [.noStatus])
    }

    @Test func boardWithoutStatusFieldGroupsByRepo() {
        let board = [
            issue(1, repo: "o/a", updated: ago(1)), issue(2, repo: "o/b", updated: ago(2)),
            issue(3, open: false, updated: ago(1), closed: ago(1)),
        ]
        let tabs = IssueTabBuilder.build(
            snap(assigned: [issue(1, repo: "o/a", updated: ago(1))], board: board, statusOptions: []),
            settings: AppSettings(), now: now)
        #expect(!tabs.statusKnown)
        #expect(tabs.board?.groups.map(\.kind) == [.repo("o/a"), .repo("o/b"), .done])
        #expect(tabs.board?.groups.map(\.title) == ["a", "b", "Done"])
        #expect(tabs.board?.groups.last?.issues.map(\.key.number) == [3])
        #expect(tabs.board?.count == 2)
        #expect(tabs.assigned.groups.map(\.kind) == [.repo("o/a")])
    }

    @Test func boardUnavailableGroupsAssignedByRepo() {
        let board = [issue(1, status: "opt1", updated: ago(1))]
        let assigned = [
            issue(1, updated: ago(3)), issue(2, repo: "o/s", updated: ago(1)), issue(3, updated: ago(2)),
        ]
        let tabs = IssueTabBuilder.build(
            snap(assigned: assigned, board: board, boardError: "Token is missing a required scope"),
            settings: AppSettings(), now: now)
        #expect(tabs.board == nil)
        #expect(tabs.contents(.board) == nil)
        #expect(!tabs.statusKnown)
        #expect(tabs.assigned.groups.allSatisfy(isRepo))
        #expect(tabs.assigned.groups.map(\.kind) == [.repo("o/s"), .repo("o/r")])
        #expect(tabs.assigned.groups.map(\.title) == ["s", "r"])
        #expect(tabs.assigned.groups.last?.issues.map(\.key.number) == [3, 1])
        #expect(tabs.assigned.count == 3)
    }

    @Test func noBoardChosenHasNoBoardTab() {
        let tabs = IssueTabBuilder.build(
            snap(assigned: [issue(1, updated: ago(1))], boardProject: nil), settings: AppSettings(), now: now)
        #expect(tabs.board == nil)
        #expect(tabs.assigned.groups.map(\.kind) == [.repo("o/r")])
    }

    @Test func createdHonoursGroupingSetting() {
        let created = [issue(1, repo: "o/a", updated: ago(2)), issue(2, repo: "o/b", updated: ago(1))]
        var s = AppSettings()
        s.grouping = .none
        let flat = IssueTabBuilder.build(snap(created: created), settings: s, now: now)
        #expect(flat.created.groups.map(\.kind) == [.all])
        #expect(flat.created.groups.first?.title == "")
        #expect(flat.created.issues.map(\.key.number) == [2, 1])
        #expect(flat.created.count == 2)
        s.grouping = .repository
        let grouped = IssueTabBuilder.build(snap(created: created), settings: s, now: now)
        #expect(grouped.created.groups.map(\.kind) == [.repo("o/b"), .repo("o/a")])
        #expect(grouped.created.groups.allSatisfy { $0.counted })
        #expect(grouped.created.count == 2)
    }

    @Test func closedNodeFromLaggingSearchIsDropped() {
        let assigned = [issue(9, open: false, updated: ago(0)), issue(1, updated: ago(1))]
        let created = [issue(9, open: false, updated: ago(0))]
        let tabs = IssueTabBuilder.build(snap(assigned: assigned, created: created), settings: AppSettings(), now: now)
        #expect(!tabs.assigned.issues.contains { $0.key.number == 9 })
        #expect(tabs.assigned.count == 1)
        #expect(tabs.created.issues.isEmpty)
        #expect(tabs.created.count == 0)
    }

    @Test func neverFetchedListsAreEmpty() {
        let tabs = IssueTabBuilder.build(snap(assigned: nil, created: nil), settings: AppSettings(), now: now)
        #expect(tabs.assigned.groups.isEmpty)
        #expect(tabs.assigned.count == 0)
        #expect(tabs.created.groups.isEmpty)
        #expect(tabs.created.count == 0)
    }

    @Test func neverFetchedListsAreNotLoaded() {
        let none = IssueTabBuilder.build(snap(assigned: nil, created: nil), settings: AppSettings(), now: now)
        #expect(!none.assignedLoaded)
        #expect(!none.createdLoaded)
        #expect(!none.isLoaded(.assigned))
        #expect(!none.isLoaded(.created))
        #expect(none.isLoaded(.board))
        // The badge still counts a never-fetched Assigned list as 0.
        var settings = AppSettings()
        settings.countAssignedIssues = true
        let prs = TabBuilder.build(snap(), settings: settings, now: now)
        #expect(Badge.count(prs: prs, issues: none, settings: settings) == 0)

        let one = IssueTabBuilder.build(snap(assigned: nil, created: []), settings: AppSettings(), now: now)
        #expect(!one.isLoaded(.assigned))
        #expect(one.isLoaded(.created))
    }

    @Test func emptyFetchedListsAreLoaded() {
        let tabs = IssueTabBuilder.build(snap(assigned: [], created: []), settings: AppSettings(), now: now)
        #expect(tabs.isLoaded(.assigned))
        #expect(tabs.isLoaded(.created))
        #expect(tabs.assigned.count == 0)
    }

    @Test func shownStatusFollowsTheLists() {
        let value = BoardStatusValue(optionId: "opt2", name: "In progress")
        #expect(IssueTabBuilder.shownStatus(value, in: snap()) == value)
        #expect(IssueTabBuilder.shownStatus(nil, in: snap()) == nil)
        // Board unavailable: the kept items still carry a Status, but the lists hide it.
        #expect(IssueTabBuilder.shownStatus(value, in: snap(boardError: "Token is missing a required scope")) == nil)
        // An option that no longer exists is "No status" in the lists.
        let gone = BoardStatusValue(optionId: "deleted", name: "Blocked")
        #expect(IssueTabBuilder.shownStatus(gone, in: snap()) == nil)
        #expect(IssueTabBuilder.shownStatus(value, in: snap(statusOptions: nil)) == nil)
        #expect(IssueTabBuilder.shownStatus(value, in: snap(boardProject: nil)) == nil)
    }

    @Test func isDoneTrimsAndIgnoresCase() {
        let named = BoardIssue(
            key: PRKey(repo: "o/r", number: 1), title: "t", url: URL(string: "https://x/1")!, isOpen: true,
            status: BoardStatusValue(optionId: "z", name: " done "))
        #expect(IssueTabBuilder.isDone(named))
        #expect(IssueTabBuilder.isDone(issue(2, open: false, updated: now)))
        #expect(!IssueTabBuilder.isDone(issue(3, status: "opt1", updated: now)))
    }

    @Test func badgeIgnoresIssuesByDefault() {
        let s = snap(assigned: [issue(1, updated: ago(1))], review: [reviewPR(1), reviewPR(2)])
        let settings = AppSettings()
        let prs = TabBuilder.build(s, settings: settings, now: now)
        let issues = IssueTabBuilder.build(s, settings: settings, now: now)
        #expect(Badge.count(prs: prs, issues: issues, settings: settings) == prs.badgeCount(.review))
        #expect(Badge.count(prs: prs, issues: issues, settings: settings) == 2)
    }

    @Test func badgeAddsAssignedWhenOn() {
        let s = snap(
            assigned: [issue(1, updated: ago(1)), issue(2, updated: ago(2)), issue(3, updated: ago(3))],
            board: [issue(1, status: "opt1", updated: ago(1))],
            review: [reviewPR(1), reviewPR(2)])
        var settings = AppSettings()
        settings.countAssignedIssues = true
        let prs = TabBuilder.build(s, settings: settings, now: now)
        let issues = IssueTabBuilder.build(s, settings: settings, now: now)
        #expect(Badge.count(prs: prs, issues: issues, settings: settings) == 5)
        #expect(Badge.count(prs: prs, issues: nil, settings: settings) == 2)
    }

    // MARK: Tab counts

    @Test func countIsCurrentOnlyAfterASuccessfulSearch() {
        let tabs = IssueTabBuilder.build(
            snap(assigned: [issue(1, updated: ago(1))], created: [], board: [issue(2, status: "opt1", updated: ago(1))]),
            settings: AppSettings(), now: now)
        #expect(tabs.count(.assigned) == .current(1))
        // An empty list that loaded is a real zero.
        #expect(tabs.count(.created) == .current(0))
        #expect(tabs.count(.board) == .current(1))
        let none = IssueTabBuilder.build(snap(assigned: nil, created: nil), settings: AppSettings(), now: now)
        #expect(none.count(.assigned) == .unavailable)
        #expect(none.count(.created) == .unavailable)
        let noBoard = IssueTabBuilder.build(snap(boardError: "Token is missing a required scope"), settings: AppSettings(), now: now)
        #expect(noBoard.count(.board) == .unavailable)
    }

    @Test func failedSearchShowsStaleCountOrNone() {
        var s = snap(assigned: [issue(1, updated: ago(1)), issue(2, updated: ago(2))], created: [])
        s.assignedIssuesError = "GitHub server error 502"
        s.assignedIssuesFetchedAt = ago(0.01)
        s.createdIssuesError = "incomplete created issues list"
        s.createdIssuesFetchedAt = ago(1)
        let tabs = IssueTabBuilder.build(s, settings: AppSettings(), now: now)
        #expect(tabs.count(.assigned) == .stale(2, error: "GitHub server error 502", since: ago(0.01)))
        #expect(tabs.count(.assigned).value == 2)
        // Nothing kept: "–", never "0".
        #expect(tabs.count(.created) == .unavailable)
        #expect(tabs.count(.created).value == nil)
        // A list that never loaded and failed is unavailable too.
        var never = snap(assigned: nil)
        never.assignedIssuesError = "GitHub server error 502"
        #expect(IssueTabBuilder.build(never, settings: AppSettings(), now: now).count(.assigned) == .unavailable)
    }

    @Test func failedSearchKeepingOnlyDoneIssuesShowsNone() {
        // The kept Assigned issue is done on the board, so it sits in the uncounted Done group.
        var s = snap(assigned: [issue(1, updated: ago(1))], board: [issue(1, status: "opt3", updated: ago(1))])
        s.assignedIssuesError = "GitHub server error 502"
        let tabs = IssueTabBuilder.build(s, settings: AppSettings(), now: now)
        #expect(tabs.assigned.groups.map(\.kind) == [.done])
        #expect(tabs.count(.assigned) == .unavailable)
    }

    @Test func badgeDimsWhenAssignedCountIsNotCurrent() {
        var on = AppSettings()
        on.countAssignedIssues = true
        var failed = snap(assigned: [issue(1, updated: ago(1))])
        failed.assignedIssuesError = "Offline"
        let failedTabs = IssueTabBuilder.build(failed, settings: on, now: now)
        #expect(Badge.issuesIncomplete(issues: failedTabs, settings: on))
        // Off: the badge doesn't add issues, so their state doesn't matter.
        #expect(!Badge.issuesIncomplete(issues: failedTabs, settings: AppSettings()))
        let never = IssueTabBuilder.build(snap(assigned: nil), settings: on, now: now)
        #expect(Badge.issuesIncomplete(issues: never, settings: on))
        let ok = IssueTabBuilder.build(snap(assigned: [issue(1, updated: ago(1))]), settings: on, now: now)
        #expect(!Badge.issuesIncomplete(issues: ok, settings: on))
        #expect(!Badge.issuesIncomplete(issues: nil, settings: on))
        // A Created failure doesn't feed the badge.
        var created = snap(assigned: [])
        created.createdIssuesError = "Offline"
        #expect(!Badge.issuesIncomplete(issues: IssueTabBuilder.build(created, settings: on, now: now), settings: on))
    }

    @Test func headerCountCapsAt99() {
        #expect(TabCountText.header(0) == "0")
        #expect(TabCountText.header(1) == "1")
        #expect(TabCountText.header(8) == "8")
        #expect(TabCountText.header(51) == "51")
        #expect(TabCountText.header(99) == "99")
        #expect(TabCountText.header(100) == "99+")
        #expect(TabCountText.header(136) == "99+")
        #expect(TabCountText.header(1234) == "99+")
        #expect(TabCountText.header(Int.max) == "99+")
    }

    // MARK: Assigned and the Done column

    @Test func assignedFoldsOpenDoneIssuesUncounted() {
        let board = [
            issue(1, status: "opt1", updated: ago(1)), issue(2, status: "opt3", updated: ago(2)),
            issue(3, status: "opt3", updated: ago(1)),
        ]
        let assigned = [
            issue(1, updated: ago(1)), issue(2, updated: ago(2)), issue(3, updated: ago(1)),
            issue(4, updated: ago(4)),
        ]
        let tabs = IssueTabBuilder.build(snap(assigned: assigned, board: board), settings: AppSettings(), now: now)
        #expect(tabs.assigned.groups.map(\.kind) == [.status(todo), .notOnBoard, .done])
        #expect(tabs.assigned.groups.last?.title == "Done")
        #expect(tabs.assigned.groups.last?.counted == false)
        #expect(tabs.assigned.groups.last?.issues.map(\.key.number) == [3, 2])
        // Still open, so the rows keep the open glyph.
        #expect(tabs.assigned.groups.last?.issues.allSatisfy(\.isOpen) == true)
        #expect(tabs.assigned.count == 2)
        #expect(tabs.count(.assigned) == .current(2))
        // The same rule as Board, where the item isn't counted either.
        #expect(tabs.board?.count == 1)
    }

    @Test func assignedFoldsIssueClosedOnBoardButOpenInSearch() {
        // The search lags the board: the item is closed there, the Assigned search still says open.
        let board = [issue(1, open: false, status: "opt2", updated: ago(1), closed: ago(1))]
        let tabs = IssueTabBuilder.build(
            snap(assigned: [issue(1, updated: ago(1))], board: board), settings: AppSettings(), now: now)
        #expect(tabs.assigned.groups.map(\.kind) == [.done])
        #expect(tabs.assigned.count == 0)
    }

    @Test func assignedWithoutBoardStatusHasNoDoneGroup() {
        let board = [issue(1, status: "opt3", updated: ago(1))]
        let tabs = IssueTabBuilder.build(
            snap(assigned: [issue(1, updated: ago(1))], board: board, boardError: "Offline"),
            settings: AppSettings(), now: now)
        #expect(tabs.assigned.groups.map(\.kind) == [.repo("o/r")])
        #expect(tabs.assigned.count == 1)
    }

    @Test func badgeLeavesOutAssignedDoneIssues() {
        let s = snap(
            assigned: [issue(1, updated: ago(1)), issue(2, updated: ago(2)), issue(3, updated: ago(3))],
            board: [issue(1, status: "opt1", updated: ago(1)), issue(2, status: "opt3", updated: ago(2))],
            review: [reviewPR(1)])
        var settings = AppSettings()
        settings.countAssignedIssues = true
        let prs = TabBuilder.build(s, settings: settings, now: now)
        let issues = IssueTabBuilder.build(s, settings: settings, now: now)
        #expect(issues.assigned.count == 2)
        #expect(Badge.count(prs: prs, issues: issues, settings: settings) == 3)
    }

    // MARK: Row rules

    @Test func chipsCapAtTwoWithMore() {
        #expect(IssueRowRules.chips(["bug", "backend", "perf"]) == (["bug", "backend"], 1))
    }

    @Test func longLabelTruncated() {
        #expect(IssueRowRules.chips([String(repeating: "x", count: 40)]).shown == [String(repeating: "x", count: 17) + "…"])
    }

    @Test func labelAtMaxLengthKept() {
        let label = String(repeating: "y", count: IssueRowRules.maxChipLength)
        #expect(IssueRowRules.chips([label]) == ([label], 0))
        #expect(IssueRowRules.chips([]) == ([], 0))
    }

    @Test func searchedLabelsLeadTheChips() {
        let labels = ["bug", "backend", "Chore", "perf"]
        #expect(IssueRowRules.chipOrder(labels, first: []) == [0, 1, 2, 3])
        #expect(IssueRowRules.chipOrder(labels, first: ["chore"]) == [2, 0, 1, 3])
        #expect(IssueRowRules.chipOrder(labels, first: ["perf", "BUG"]) == [0, 3, 1, 2])
        #expect(IssueRowRules.chipOrder(labels, first: ["missing"]) == [0, 1, 2, 3])
        #expect(IssueRowRules.chipOrder([], first: ["bug"]) == [])
    }

    @Test func assignedHidesMeOthersKeepMe() {
        let me = Assignee(login: "Devon", avatarURL: nil)
        let other = Assignee(login: "dev-a", avatarURL: nil)
        let i = BoardIssue(
            key: PRKey(repo: "o/r", number: 1), title: "t", url: URL(string: "https://x/1")!, isOpen: true,
            assignees: [me, other])
        #expect(IssueRowRules.avatars(i, tab: .assigned, me: "devon") == [other])
        #expect(IssueRowRules.avatars(i, tab: .board, me: "devon") == [me, other])
        #expect(IssueRowRules.avatars(i, tab: .created, me: "devon") == [me, other])
    }
}
