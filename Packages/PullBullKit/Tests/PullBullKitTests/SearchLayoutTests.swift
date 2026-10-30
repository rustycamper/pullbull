import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3_600) }

private let todo = StatusOption(id: "opt1", name: "Todo")
private let inProgress = StatusOption(id: "opt2", name: "In progress")
private let done = StatusOption(id: "opt3", name: "Done")
private let options = [todo, inProgress, done]

private let org = OrgContext(org: "o", viewer: "me", members: [], myTeams: ["core"], repos: [])

private func pr(
    _ n: Int, repo: String = "o/a", author: String = "alice", state: PRState = .open, created: Double = 48,
    updated: Double = 1, closed: Double? = nil, reviews: [Review] = [], requests: [Reviewer] = []
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: n), title: "p\(n)", url: URL(string: "https://x/p\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: false,
        createdAt: hoursAgo(created), updatedAt: hoursAgo(updated), closedAt: closed.map(hoursAgo),
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests)
}

private func issue(
    _ n: Int, repo: String = "o/a", open: Bool = true, status: String? = nil, updated: Double = 1,
    closed: Double? = nil
) -> BoardIssue {
    let value = status.map { id in
        BoardStatusValue(optionId: id, name: options.first { $0.id == id }?.name ?? "Gone")
    }
    return BoardIssue(
        key: PRKey(repo: repo, number: n), title: "i\(n)", url: URL(string: "https://x/i\(n)")!,
        isOpen: open, updatedAt: hoursAgo(updated), closedAt: closed.map(hoursAgo), status: value)
}

private func snap(board: [BoardIssue] = [], statusOptions: [StatusOption]? = options) -> Snapshot {
    Snapshot(
        fetchedAt: now, org: org, reviewCandidates: [], mine: [], team: [], recentlyClosed: [],
        boardIssues: board, boardProject: 3, assignedIssues: [], createdIssues: [],
        boardStatusOptions: statusOptions)
}

private func results(prs: [PullRequest] = [], issues: [BoardIssue] = []) -> SearchResults {
    SearchResults(
        openPRs: prs.filter { $0.state == .open }, closedPRs: prs.filter { $0.state != .open }, issues: issues,
        phase: .done)
}

private func layout(
    _ prs: [PullRequest], on tab: PRTab, grouping: PRGrouping = .repository, settings: AppSettings = AppSettings()
) -> SearchPRLayout {
    SearchLayout.pullRequests(results(prs: prs), on: tab, grouping: grouping, settings: settings, org: org)
}

private func layout(
    _ issues: [BoardIssue], on tab: IssueTab, board: [BoardIssue] = [], statusOptions: [StatusOption]? = options,
    settings: AppSettings = AppSettings(), focus: RepoFocus? = nil
) -> SearchIssueLayout {
    SearchLayout.issues(
        results(issues: issues), on: tab, settings: settings, focus: focus,
        snap: snap(board: board, statusOptions: statusOptions))
}

private func key(_ n: Int, _ repo: String = "o/a") -> PRKey { PRKey(repo: repo, number: n) }

@Suite struct SearchLayoutTests {
    @Test func rowFollowsReviewRules() {
        let again = pr(1, reviews: [Review(author: "me", state: .commented, submittedAt: hoursAgo(5))],
                       requests: [.user("me")])
        let againRow = TabBuilder.row(for: again, on: .review, me: "me", myTeams: ["core"])
        #expect(againRow.counted && !againRow.dimmed && againRow.reviewReason == .reRequested)

        let approved = pr(2, reviews: [Review(author: "me", state: .approved, submittedAt: hoursAgo(5))])
        let approvedRow = TabBuilder.row(for: approved, on: .review, me: "me", myTeams: ["core"])
        #expect(approvedRow.dimmed && !approvedRow.counted && approvedRow.reviewReason == nil)

        let unasked = TabBuilder.row(for: pr(3), on: .review, me: "me", myTeams: ["core"])
        #expect(!unasked.dimmed && !unasked.counted)

        for tab in [PRTab.mine, .team] {
            for pr in [again, approved, pr(3)] {
                let row = TabBuilder.row(for: pr, on: tab, me: "me", myTeams: ["core"])
                #expect(row.counted && !row.dimmed)
            }
        }
    }

    @Test func chipTabForOthersOnMine() {
        #expect(SearchLayout.chipTab(for: pr(1, author: "alice"), on: .mine, viewer: "me") == .team)
        #expect(SearchLayout.chipTab(for: pr(1, author: "ME"), on: .mine, viewer: "me") == .mine)
        #expect(SearchLayout.chipTab(for: pr(1, author: "alice"), on: .review, viewer: "me") == .review)
        #expect(SearchLayout.chipTab(for: pr(1, author: "alice"), on: .team, viewer: "me") == .team)
        let approved = pr(1, author: "alice", reviews: [Review(author: "bob", state: .approved, submittedAt: hoursAgo(5))])
        let chips = RowChips(row: Row(pr: approved, dimmed: false, counted: true), tab: .team)
        #expect(chips.action != .readyToMerge)
        let mine = pr(1, author: "me", reviews: [Review(author: "bob", state: .approved, submittedAt: hoursAgo(5))])
        let mineChips = RowChips(row: Row(pr: mine, dimmed: false, counted: true), tab: .mine)
        #expect(mineChips.action == .readyToMerge)
    }

    @Test func showsRepoOutsideFocus() {
        let focus = RepoFocus(repo: "o/a")
        #expect(!SearchLayout.showsRepo(key(1), underRepoHeader: false, focus: focus))
        #expect(SearchLayout.showsRepo(key(2, "o/b"), underRepoHeader: false, focus: focus))
        #expect(!SearchLayout.showsRepo(key(2, "o/b"), underRepoHeader: true, focus: nil))
        #expect(SearchLayout.showsRepo(key(1), underRepoHeader: false, focus: nil))
    }

    @Test func prGroupsByRepoAsTheTab() {
        let prs = [pr(1, author: "me", updated: 1), pr(2, repo: "o/b", author: "me", updated: 2),
                   pr(3, author: "me", updated: 3)]
        let shown = layout(prs, on: .mine)
        #expect(shown.groups(closedExpanded: false) == [[key(1), key(3)], [key(2, "o/b")]])
        let tab = TabBuilder.build(
            Snapshot(fetchedAt: now, org: org, reviewCandidates: [], mine: prs, team: [], recentlyClosed: [],
                     boardIssues: []),
            settings: AppSettings(), now: now)
        #expect(shown.contents.rows.map(\.pr.key) == tab.mine.rows.map(\.pr.key))
    }

    @Test func teamByAuthor() {
        let shown = layout([pr(1, author: "bob"), pr(2, author: "Ann"), pr(3, author: "bob")], on: .team, grouping: .author)
        #expect(shown.groups(closedExpanded: false) == [[key(2)], [key(1), key(3)]])
        #expect(shown.groups(closedExpanded: false)
            == ListNavigation.authorGroups(shown.contents.rows).map { $0.rows.map(\.pr.key) })
    }

    @Test func ungroupedIsOneGroup() {
        let shown = layout([pr(1), pr(2, repo: "o/b")], on: .mine, grouping: .none)
        #expect(shown.groups(closedExpanded: false).count == 1)
        #expect(!shown.isGrouped)
        #expect(layout([pr(1)], on: .mine).isGrouped)
    }

    @Test func reviewOldestFirst() {
        var settings = AppSettings()
        settings.reviewOldestFirst = true
        let prs = [pr(1, created: 10, updated: 1), pr(2, created: 30, updated: 2), pr(3, created: 20, updated: 3)]
        let shown = layout(prs, on: .review, grouping: .none, settings: settings)
        #expect(shown.contents.rows.map(\.pr.key.number) == [2, 3, 1])
        settings.reviewOldestFirst = false
        #expect(layout(prs, on: .review, grouping: .none, settings: settings).contents.rows.map(\.pr.key.number)
            == [1, 2, 3])
    }

    @Test func endedGoInClosed() {
        let merged = pr(1, state: .merged, closed: 24)
        let closed = pr(2, state: .closed, closed: 2)
        let open = pr(3)
        let shown = layout([merged, closed, open], on: .mine)
        #expect(shown.ended.map(\.key) == [closed.key, merged.key])
        #expect(shown.groups(closedExpanded: true).last == [closed.key, merged.key])
        #expect(shown.keys(closedExpanded: false) == [open.key])
        #expect(shown.keys(closedExpanded: true) == [open.key, closed.key, merged.key])
    }

    @Test func noEndedAddsNoGroup() {
        let shown = layout([pr(1)], on: .mine)
        #expect(shown.groups(closedExpanded: true) == [[key(1)]])
    }

    // MARK: Issues

    private var board: [BoardIssue] {
        [issue(1, status: "opt1"), issue(2, status: "opt2"), issue(4, status: "opt3")]
    }

    private var found: [BoardIssue] {
        [issue(1, updated: 1), issue(2, updated: 2), issue(3, updated: 3), issue(4, updated: 4),
         issue(5, open: false, updated: 5, closed: 5)]
    }

    @Test func issuesInLanesOnAssigned() {
        let shown = layout(found, on: .assigned, board: board)
        #expect(shown.contents.groups.map(\.kind) == [.status(todo), .status(inProgress), .notOnBoard, .done])
        #expect(shown.contents.groups.first { $0.kind == .done }?.counted == false)
        #expect(shown.contents.groups.first { $0.kind == .done }?.issues.map(\.key) == [key(4)])
        #expect(shown.contents.count == 3)
        #expect(shown.ended.map(\.key) == [key(5)])
        #expect(shown.isGrouped)
    }

    @Test func boardReferenceSendsOffBoardToNotOnBoard() {
        let shown = layout(found, on: .board, board: board)
        #expect(shown.contents.groups.map(\.kind) == [.status(todo), .status(inProgress), .notOnBoard, .done])
        #expect(shown.contents.groups.first { $0.kind == .notOnBoard }?.issues.map(\.key) == [key(3)])
    }

    @Test func goneStatusGoesToNoStatus() {
        let shown = layout([issue(1)], on: .assigned, board: [issue(1, status: "gone")])
        #expect(shown.contents.groups.map(\.kind) == [.noStatus])
    }

    @Test func noStatusOptionsGroupByRepo() {
        let issues = [issue(1, repo: "o/a", updated: 5), issue(2, repo: "o/b", updated: 1), issue(3, repo: "o/a", updated: 3)]
        let shown = layout(issues, on: .assigned, board: board, statusOptions: [])
        #expect(shown.contents.groups.map(\.kind) == [.repo("o/b"), .repo("o/a")])
        #expect(shown.contents.groups.last?.issues.map(\.key.number) == [3, 1])
    }

    @Test func createdFollowsGrouping() {
        let issues = [issue(1, repo: "o/a"), issue(2, repo: "o/b", updated: 2)]
        var settings = AppSettings()
        settings.grouping = .none
        #expect(layout(issues, on: .created, board: board, settings: settings).contents.groups.map(\.kind) == [.all])
        settings.grouping = .repository
        #expect(layout(issues, on: .created, board: board, settings: settings).contents.groups.map(\.kind)
            == [.repo("o/a"), .repo("o/b")])
    }

    @Test func focusMergesRepoGroups() {
        var settings = AppSettings()
        settings.grouping = .repository
        let issues = [issue(1, repo: "o/a"), issue(2, repo: "o/b", updated: 2)]
        let shown = layout(issues, on: .created, settings: settings, focus: RepoFocus(repo: "o/a"))
        #expect(shown.contents.groups.map(\.kind) == [.all])
        #expect(shown.contents.groups.first?.issues.map(\.key) == [key(1), key(2, "o/b")])
        #expect(!shown.isGrouped)
    }

    @Test func closedIssuesNewestFirst() {
        let issues = [
            issue(1, open: false, updated: 1, closed: 10), issue(2, open: false, updated: 3),
            issue(3, open: false, updated: 1, closed: 5),
        ]
        let shown = layout(issues, on: .created)
        #expect(shown.ended.map(\.key.number) == [2, 3, 1])
    }

    @Test func foldedClosedLeavesKeys() {
        let shown = layout(found, on: .assigned, board: board)
        #expect(shown.keys(closedExpanded: false, doneExpanded: false) == [key(1), key(2), key(3)])
        let groups = shown.groups(closedExpanded: true, doneExpanded: true)
        #expect(groups.suffix(2) == [[key(4)], [key(5)]])
        #expect(shown.keys(closedExpanded: true, doneExpanded: false) == [key(1), key(2), key(3), key(5)])
    }

    @Test func issueTabsUnchanged() {
        let snapshot = Snapshot(
            fetchedAt: now, org: org, reviewCandidates: [], mine: [], team: [], recentlyClosed: [],
            boardIssues: board + [issue(6, status: "opt1", updated: 6)], boardProject: 3,
            assignedIssues: found.filter(\.isOpen), createdIssues: found.filter(\.isOpen),
            boardStatusOptions: options)
        let tabs = IssueTabBuilder.build(snapshot, settings: AppSettings(), now: now)
        for tab in [IssueTab.assigned, .created] {
            let groups = IssueTabBuilder.groups(of: found.filter(\.isOpen), on: tab, in: snapshot, settings: AppSettings())
            #expect(groups == tabs.contents(tab)?.groups)
        }
    }
}
