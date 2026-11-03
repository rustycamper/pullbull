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
    updated: Double = 1, closed: Double? = nil, reviews: [Review] = [], requests: [Reviewer] = [], draft: Bool = false, ci: CIState = .none
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: n), title: "p\(n)", url: URL(string: "https://x/p\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: draft,
        createdAt: hoursAgo(created), updatedAt: hoursAgo(updated), closedAt: closed.map(hoursAgo),
        headRef: "h", baseRef: "main", ci: ci, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests)
}

private func issue(
    _ n: Int, repo: String = "o/a", open: Bool = true, status: String? = nil, updated: Double = 1,
    closed: Double? = nil, created: Double? = nil
) -> BoardIssue {
    let value = status.map { id in
        BoardStatusValue(optionId: id, name: options.first { $0.id == id }?.name ?? "Gone")
    }
    return BoardIssue(
        key: PRKey(repo: repo, number: n), title: "i\(n)", url: URL(string: "https://x/i\(n)")!,
        isOpen: open, createdAt: created.map(hoursAgo), updatedAt: hoursAgo(updated),
        closedAt: closed.map(hoursAgo), status: value)
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
    SearchLayout.pullRequests(results(prs: prs), on: tab, grouping: grouping, settings: settings, org: org, now: now)
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

private func prTabs(review: [PullRequest] = [], mine: [PullRequest] = [], team: [PullRequest] = []) -> BuiltTabs {
    TabBuilder.build(
        Snapshot(fetchedAt: now, org: org, reviewCandidates: review, mine: mine, team: team, recentlyClosed: [],
                 boardIssues: []),
        settings: AppSettings(), now: now)
}
private func sectioned(
    _ prs: [PullRequest], scope: PRScope = .all, tabs: BuiltTabs, settings: AppSettings = AppSettings()
) -> SearchSectionLayout {
    SearchLayout.sections(results(prs: prs), scope: scope, tabs: tabs, settings: settings, org: org, now: now)
}
private func shape(_ layout: SearchSectionLayout) -> [String] {
    layout.sections.map { "\($0.section.rawValue) \($0.contents.rows.map(\.id.number))" }
}

@Suite struct SearchLayoutTests {
    // MARK: Sections (Everywhere, Mine)

    @Test func everywherePutsEachResultInItsSection() {
        let requested = pr(1, author: "bob", requests: [.user("me")])
        let failing = pr(2, author: "me", ci: .failure)
        let teammate = pr(3, author: "carol")
        let tabs = prTabs(review: [requested], mine: [failing], team: [teammate, requested])
        let layout = sectioned(
            [requested, failing, teammate, pr(4, author: "zed"), pr(6, state: .merged, closed: 2)], tabs: tabs)
        #expect(shape(layout) == ["needsReview [1]", "yourPRs [2]", "team [3]", "otherResults [4]"])
        #expect(layout.ended.map(\.key.number) == [6])
    }

    @Test func aGitHubOnlyResultOfMineIsSplitByTheRule() {
        let layout = sectioned([pr(7, author: "ME", draft: true), pr(8, author: "me", requests: [.user("bob")])], tabs: prTabs())
        #expect(shape(layout) == ["yourPRs [7]", "waiting [8]"])
        #expect(layout.sections.allSatisfy { $0.section.rowTab == .mine })
    }

    @Test func otherResultsTakeTeamsRows() throws {
        // Requested from me but not in the list (say, filtered out as old): a Team row, counted, no reason.
        let layout = sectioned([pr(5, author: "zed", requests: [.user("me")])], tabs: prTabs())
        let row = try #require(layout.sections.first?.contents.rows.first)
        #expect(layout.sections.map(\.section) == [.otherResults])
        #expect(row.reviewReason == nil && row.counted && !row.dimmed)
    }

    @Test func aFoldedSectionsResultsShowAndAreWalked() {
        // Team folds by default in the list; in search its results show, and up/down reach them.
        let tabs = prTabs(team: [pr(3, author: "carol")])
        let layout = sectioned([pr(3, author: "carol"), pr(9, state: .closed, closed: 1)], tabs: tabs)
        #expect(layout.keys(closedExpanded: true).map(\.number) == [3, 9])
        #expect(layout.groups(closedExpanded: false).map { $0.map(\.number) } == [[3]])
    }

    @Test func sectionedResultsFollowTheScopesSort() {
        let a = pr(1, author: "me", created: 10, updated: 1, ci: .failure)
        let b = pr(2, author: "me", created: 50, updated: 2)
        let c = pr(3, author: "me", created: 90, updated: 3)
        let tabs = prTabs(mine: [a, b, c])
        #expect(shape(sectioned([a, b, c], tabs: tabs)) == ["yourPRs [1]", "waiting [2, 3]"])
        var s = AppSettings()
        s.setSort(.oldestFirst, for: PRScope.all)
        #expect(shape(sectioned([a, b, c], tabs: tabs, settings: s)) == ["yourPRs [1]", "waiting [3, 2]"])
        var mineOnly = AppSettings()
        mineOnly.setSort(.oldestFirst, for: PRScope.mine)
        #expect(shape(sectioned([a, b, c], tabs: tabs, settings: mineOnly)) == ["yourPRs [1]", "waiting [2, 3]"])
        #expect(shape(sectioned([a, b, c], scope: .mine, tabs: tabs, settings: mineOnly))
            == ["yourPRs [1]", "waiting [3, 2]"])
    }

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
        let chips = RowChips(row: Row(pr: approved, dimmed: false, counted: true), tab: .team, me: "me", myTeams: [], now: .now)
        #expect(chips.action != .readyToMerge)
        let mine = pr(1, author: "me", reviews: [Review(author: "bob", state: .approved, submittedAt: hoursAgo(5))])
        let mineChips = RowChips(row: Row(pr: mine, dimmed: false, counted: true), tab: .mine, me: "me", myTeams: [], now: .now)
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
        settings.setSort(.oldestFirst, for: PRTab.review)
        let prs = [pr(1, created: 10, updated: 1), pr(2, created: 30, updated: 2), pr(3, created: 20, updated: 3)]
        let shown = layout(prs, on: .review, grouping: .none, settings: settings)
        #expect(shown.contents.rows.map(\.pr.key.number) == [2, 3, 1])
        settings.setSort(.recentlyUpdated, for: PRTab.review)
        #expect(layout(prs, on: .review, grouping: .none, settings: settings).contents.rows.map(\.pr.key.number)
            == [1, 2, 3])
    }

    @Test func searchFollowsTheReferenceTabsSort() {
        var settings = AppSettings()
        settings.setSort(.waitingLongest, for: PRTab.team)
        let dana = Reviewer.user("dana")
        func waiting(_ n: Int, hours: Double, updated: Double) -> PullRequest {
            let p = pr(n, updated: updated, requests: [dana])
            return PullRequest(
                key: p.key, title: p.title, url: p.url, author: p.author, authorAvatarURL: nil, state: .open,
                isDraft: false, createdAt: p.createdAt, updatedAt: p.updatedAt, closedAt: nil, headRef: "h",
                baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
                latestReviews: [], reviewRequests: [dana], reviewRequestTimes: [dana.key: hoursAgo(hours)])
        }
        let prs = [
            waiting(1, hours: 10, updated: 1), waiting(2, hours: 90, updated: 5),
            pr(3, state: .merged, created: 200, closed: 30), pr(4, state: .merged, created: 100, closed: 60),
        ]
        let shown = layout(prs, on: .team, grouping: .none, settings: settings)
        #expect(shown.contents.rows.map(\.pr.key.number) == [2, 1])
        #expect(shown.ended.map(\.key.number) == [3, 4])
    }

    @Test func issueSearchFollowsTheTabsSort() {
        var settings = AppSettings()
        settings.grouping = .none
        settings.setSort(.oldestFirst, for: IssueTab.created)
        let issues = [
            issue(1, updated: 1, created: 10), issue(2, updated: 5, created: 50),
            issue(3, open: false, updated: 30, closed: 30, created: 90),
            issue(4, open: false, updated: 5, closed: 5, created: 20),
        ]
        let shown = layout(issues, on: .created, settings: settings)
        #expect(shown.contents.groups.flatMap(\.issues).map(\.key.number) == [2, 1])
        #expect(shown.ended.map(\.key.number) == [4, 3])
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

    // MARK: Issue sections

    private func mine(_ n: Int, author: String? = nil, assignedToMe: Bool = false, status: String? = nil,
                      updated: Double = 1) -> BoardIssue {
        let base = issue(n, status: status, updated: updated)
        return BoardIssue(
            key: base.key, title: base.title, url: base.url, isOpen: true, author: author,
            updatedAt: base.updatedAt, assignees: assignedToMe ? [Assignee(login: "ME", avatarURL: nil)] : [],
            status: base.status)
    }

    private func issueSnap(
        assigned: [BoardIssue] = [], created: [BoardIssue] = [], board: [BoardIssue] = []
    ) -> (Snapshot, BuiltIssueTabs) {
        let s = Snapshot(
            fetchedAt: now, org: org, reviewCandidates: [], mine: [], team: [], recentlyClosed: [],
            boardIssues: board, boardProject: 3, assignedIssues: assigned, createdIssues: created,
            boardStatusOptions: options)
        return (s, IssueTabBuilder.build(s, settings: AppSettings(), now: now))
    }

    @Test func everywhereIssueResultsTakeAllsSections() {
        let (s, tabs) = issueSnap(
            assigned: [mine(1, assignedToMe: true)], created: [mine(2, author: "me")],
            board: [issue(3, status: "opt1")])
        let found = results(issues: [
            issue(3, status: "opt1"), mine(1, assignedToMe: true), mine(2, author: "me"),
            mine(4, assignedToMe: true), mine(5, author: "Me"), mine(6, author: "bob"),
            issue(7, open: false, closed: 3), issue(8, open: false, closed: 9),
        ])
        let shown = SearchLayout.issueSections(found, tabs: tabs, snap: s, settings: AppSettings(), viewer: "me")
        #expect(shown.sections.map(\.section) == [.assignedToYou, .youOpened, .restOfBoard, .otherResults])
        #expect(shown.sections.allSatisfy { $0.state == .rows })
        #expect(shown.sections.map { $0.issues.map(\.key.number).sorted() } == [[1, 4], [2, 5], [3], [6]])
        #expect(shown.done.isEmpty)
        #expect(shown.ended.map(\.key.number) == [7, 8])
        #expect(shown.status[key(3)]?.optionId == "opt1")
        #expect(shown.keys(closedExpanded: false, doneExpanded: false).count == 6)
        #expect(shown.keys(closedExpanded: true, doneExpanded: false).suffix(2).map(\.number) == [7, 8])
    }

    @Test func aDoneOnTheBoardResultGoesToDone() {
        let (s, tabs) = issueSnap(board: [issue(1, status: "opt3"), issue(2, status: "opt3", updated: 5)])
        let found = results(issues: [mine(1, assignedToMe: true, status: "opt3"), issue(2), issue(3, status: "opt1")])
        let shown = SearchLayout.issueSections(found, tabs: tabs, snap: s, settings: AppSettings(), viewer: "me")
        #expect(shown.done.map(\.key.number) == [1, 2])
        #expect(shown.sections.flatMap(\.issues).map(\.key.number) == [3])
        #expect(!shown.sections.contains { $0.section == .doneStillOpen })
        #expect(shown.keys(closedExpanded: false, doneExpanded: false).map(\.number) == [3])
        #expect(shown.keys(closedExpanded: false, doneExpanded: true).map(\.number) == [3, 1, 2])
    }
}
