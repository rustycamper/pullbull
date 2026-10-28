import Foundation
import Testing
@testable import PullBullKit

private let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)
private let focus = RepoFocus(repo: "o/a")
private let todo = StatusOption(id: "s1", name: "Todo")
private let inProgress = StatusOption(id: "s2", name: "In progress")

private func key(_ n: Int, repo: String) -> PRKey { PRKey(repo: repo, number: n) }

private func pr(
    _ n: Int, repo: String, author: String = "alice", requests: [Reviewer] = [],
    reviews: [Review] = []
) -> PullRequest {
    PullRequest(
        key: key(n, repo: repo), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: fixtureNow, updatedAt: fixtureNow, closedAt: nil,
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests)
}

private func row(_ n: Int, repo: String, dimmed: Bool = false, counted: Bool = true) -> Row {
    Row(pr: pr(n, repo: repo), dimmed: dimmed, counted: counted)
}

private func issue(_ n: Int, repo: String) -> BoardIssue {
    BoardIssue(key: key(n, repo: repo), title: "i\(n)", url: URL(string: "https://x/\(n)")!, isOpen: true)
}

@Suite struct RepoFocusTests {
    @Test func scopeKeepsOrderAndFlags() {
        let contents = TabContents(rows: [
            row(1, repo: "o/a"), row(2, repo: "o/b"), row(3, repo: "o/a", dimmed: true, counted: false),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.contents.rows.map(\.id) == [key(1, repo: "o/a"), key(3, repo: "o/a")])
        #expect(scoped.contents.rows[1].dimmed)
        #expect(scoped.otherCount == 1)
    }

    @Test func dimmedRowsAreListedButNotCounted() {
        let contents = TabContents(rows: [
            row(1, repo: "o/a", dimmed: true, counted: false),
            row(2, repo: "o/b", dimmed: true, counted: false),
            row(3, repo: "o/b"),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.contents.rows.count == 1)
        #expect(scoped.contents.count == 0)
        #expect(scoped.otherCount == 1)
    }

    @Test func dimmedRowsInOtherReposAreStated() {
        let contents = TabContents(rows: [
            row(1, repo: "o/a"), row(2, repo: "o/a"),
            row(3, repo: "o/b", dimmed: true, counted: false),
            row(4, repo: "o/b", dimmed: true, counted: false),
            row(5, repo: "o/b", dimmed: true, counted: false),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.contents.rows.count == 2)
        #expect(scoped.otherCount == 0)
        #expect(scoped.hiddenCount == 3)
    }

    @Test func uncountedIssuesInOtherReposAreStated() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .status(todo), issues: [issue(1, repo: "o/a"), issue(2, repo: "o/b")], counted: true),
            IssueGroup(kind: .done, issues: [issue(3, repo: "o/b"), issue(4, repo: "o/b")], counted: false),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.otherCount == 1)
        #expect(scoped.hiddenCount == 3)
        let unscoped = ScopedIssueTab(unscoped: contents)
        #expect(unscoped.hiddenCount == 0)
        #expect(ScopedTab(unscoped: TabContents(rows: [row(1, repo: "o/b")])).hiddenCount == 0)
    }

    @Test func matchesIgnoringCase() {
        let upper = RepoFocus(repo: "O/A")
        #expect(upper.matches(key(1, repo: "o/a")))
        #expect(!upper.matches(key(1, repo: "o/b")))
        #expect(upper.name == "A")
    }

    @Test func recentlyClosedFiltered() {
        let closed = focus.scope([pr(1, repo: "o/a"), pr(2, repo: "o/b")])
        #expect(closed.map(\.key.repo) == ["o/a"])
    }

    @Test func issueStatusGroupsFilteredEmptyDropped() {
        let contents = IssueTabContents(groups: [
            IssueGroup(
                kind: .status(todo), issues: [issue(1, repo: "o/a"), issue(2, repo: "o/b")], counted: true),
            IssueGroup(kind: .status(inProgress), issues: [issue(3, repo: "o/b")], counted: true),
            IssueGroup(
                kind: .done, issues: [issue(4, repo: "o/a"), issue(5, repo: "o/b")], counted: false),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.contents.groups.map(\.kind) == [.status(todo), .done])
        #expect(scoped.contents.groups.map(\.issues.count) == [1, 1])
        #expect(scoped.contents.groups[1].counted == false)
        #expect(scoped.otherCount == 2)
    }

    @Test func issueRepoGroupsCollapseToOne() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .repo("o/a"), issues: [issue(1, repo: "o/a")], counted: true),
            IssueGroup(kind: .repo("o/b"), issues: [issue(2, repo: "o/b")], counted: true),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.contents.groups.count == 1)
        #expect(scoped.contents.groups[0].kind == .all)
        #expect(scoped.contents.groups[0].issues.map(\.key.number) == [1])
        #expect(scoped.contents.groups[0].counted)
        #expect(scoped.otherCount == 1)
    }

    @Test func selectionOutsideFocusIsNotShown() {
        let contents = TabContents(rows: [row(1, repo: "o/a"), row(2, repo: "o/b")])
        let keys = ListNavigation.prKeys(
            tab: .review, contents: focus.scope(contents).contents, groupedByRepo: true,
            recentlyClosed: [], closedExpanded: false)
        let outside = key(2, repo: "o/b")
        #expect(!keys.contains(outside))
        #expect(ListNavigation.shown(outside, in: keys) == nil)
        #expect(ListNavigation.shown(key(1, repo: "o/a"), in: keys) == key(1, repo: "o/a"))
    }

    @Test func repoGroupsCollapseWhenFirstFiltersToEmpty() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .repo("o/b"), issues: [issue(2, repo: "o/b")], counted: true),
            IssueGroup(kind: .repo("o/a"), issues: [issue(1, repo: "o/a")], counted: true),
        ])
        let scoped = focus.scope(contents)
        #expect(scoped.contents.groups.map(\.kind) == [.all])
        #expect(scoped.contents.groups[0].issues.map(\.key.number) == [1])
        #expect(scoped.otherCount == 1)
    }

    @Test func unscopedTabKeepsContentsWithNoOthers() {
        let contents = TabContents(rows: [row(1, repo: "o/a"), row(2, repo: "o/b", dimmed: true, counted: false)])
        let scoped = ScopedTab(unscoped: contents)
        #expect(scoped.contents.rows.map(\.id) == contents.rows.map(\.id))
        #expect(scoped.contents.count == contents.count)
        #expect(scoped.otherCount == 0)
    }

    @Test func unscopedIssueTabKeepsContentsWithNoOthers() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .repo("o/a"), issues: [issue(1, repo: "o/a")], counted: true),
            IssueGroup(kind: .done, issues: [issue(2, repo: "o/b")], counted: false),
        ])
        let scoped = ScopedIssueTab(unscoped: contents)
        #expect(scoped.contents == contents)
        #expect(scoped.otherCount == 0)
    }

    @Test func scopedPlusOtherIsTabCount() {
        let now = fixtureNow
        var settings = AppSettings()
        settings.hideApprovedByMe = false
        settings.badge = .all
        settings.countAssignedIssues = true
        let approved = Review(author: "me", state: .approved, submittedAt: now, commitOid: nil)
        let snapshot = Snapshot(
            fetchedAt: now,
            org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
            reviewCandidates: [
                pr(1, repo: "o/a", requests: [.user("me")]), pr(2, repo: "o/b", requests: [.user("me")]),
                pr(3, repo: "o/b", reviews: [approved]),
            ],
            mine: [pr(4, repo: "o/a", author: "me"), pr(5, repo: "o/b", author: "me")],
            team: [pr(6, repo: "o/a"), pr(7, repo: "o/b"), pr(8, repo: "o/b")],
            recentlyClosed: [], boardIssues: [], boardProject: nil, boardError: nil,
            assignedIssues: [issue(10, repo: "o/a"), issue(11, repo: "o/b"), issue(12, repo: "o/b")],
            createdIssues: [], boardStatusOptions: nil)
        let built = TabBuilder.build(snapshot, settings: settings, now: now)
        let issues = IssueTabBuilder.build(snapshot, settings: settings, now: now)

        // Fixture sanity: values derived from the fixture, not from the builder.
        #expect(built.review.count == 2)
        #expect(built.review.rows.contains { !$0.counted })
        #expect(built.mine.count == 2)
        #expect(built.team.count == 3)
        #expect(issues.assigned.count == 3)
        #expect(Badge.count(prs: built, issues: issues, settings: settings) == 2 + 2 + 3 + 3)

        for repo in ["o/a", "o/b", "x/none"] {
            let repoFocus = RepoFocus(repo: repo)
            for tab in [built.review, built.mine, built.team] {
                let scoped = repoFocus.scope(tab)
                #expect(scoped.contents.count + scoped.otherCount == tab.count)
            }
            let scopedIssues = repoFocus.scope(issues.assigned)
            #expect(scopedIssues.contents.count + scopedIssues.otherCount == issues.assigned.count)
        }
    }

    // MARK: Menu choices and validity

    private func tabs(
        review: [Row] = [], mine: [Row] = [], team: [Row] = [], closed: [PullRequest] = []
    ) -> BuiltTabs {
        BuiltTabs(
            review: TabContents(rows: review), mine: TabContents(rows: mine),
            team: TabContents(rows: team), recentlyClosed: closed, hiddenApprovedCount: 0)
    }

    private func issueTabs(
        assigned: [IssueGroup] = [], created: [IssueGroup] = [], board: [IssueGroup]? = nil
    ) -> BuiltIssueTabs {
        BuiltIssueTabs(
            assigned: IssueTabContents(groups: assigned), created: IssueTabContents(groups: created),
            board: board.map { IssueTabContents(groups: $0) }, statusKnown: false)
    }

    private func org(repos: [String], name: String = "o", complete: Bool = true) -> OrgContext {
        OrgContext(org: name, viewer: "me", members: [], myTeams: [], repos: repos, reposComplete: complete)
    }

    @Test func choicesUnionAllListsDeduped() {
        let built = tabs(
            review: [row(1, repo: "o/a")], mine: [row(2, repo: "O/A")],
            team: [row(1, repo: "o/a"), row(3, repo: "o/b")], closed: [pr(4, repo: "o/closed")])
        let issues = issueTabs(
            assigned: [IssueGroup(kind: .all, issues: [issue(5, repo: "o/b")], counted: true)],
            board: [IssueGroup(kind: .done, issues: [issue(6, repo: "o/done")], counted: false)])
        let choices = RepoFocus.choices(prs: built, issues: issues, current: nil)
        let byId = Dictionary(uniqueKeysWithValues: choices.map { ($0.id, $0) })
        #expect(Set(byId.keys) == ["o/a", "o/b", "o/closed", "o/done"])
        #expect(byId["o/a"]?.openCount == 2)
        #expect(byId["o/a"]?.reviewCount == 1)
        #expect(byId["o/a"]?.repo == "o/a")
        #expect(byId["o/b"]?.openCount == 2)
        #expect(byId["o/closed"]?.openCount == 0)
        #expect(byId["o/done"]?.openCount == 0)
        #expect(byId["o/done"]?.reviewCount == 0)
    }

    @Test func choicesOrdering() {
        let built = tabs(
            review: [
                row(1, repo: "o/a"), row(2, repo: "o/b"), row(3, repo: "o/b"),
                row(4, repo: "o/a"),
            ],
            mine: [row(5, repo: "o/b")], team: [row(6, repo: "o/b"), row(7, repo: "o/c")],
            closed: [])
        let issues = issueTabs(
            assigned: [
                IssueGroup(
                    kind: .all,
                    issues: [issue(8, repo: "o/c"), issue(9, repo: "o/c"), issue(10, repo: "o/c"),
                             issue(11, repo: "o/c"), issue(12, repo: "o/d"), issue(13, repo: "o/d"),
                             issue(14, repo: "o/d"), issue(15, repo: "o/d"), issue(16, repo: "o/d")],
                    counted: true)
            ])
        let choices = RepoFocus.choices(prs: built, issues: issues, current: nil)
        #expect(choices.map(\.repo) == ["o/b", "o/a", "o/c", "o/d"])
        #expect(choices.map(\.reviewCount) == [2, 2, 0, 0])
        #expect(choices.map(\.openCount) == [4, 2, 5, 5])
    }

    @Test func choicesIncludeCurrentFocusWithNothingListed() {
        let choices = RepoFocus.choices(
            prs: tabs(), issues: nil, current: RepoFocus(repo: "o/gone"))
        #expect(choices == [RepoChoice(repo: "o/gone", reviewCount: 0, openCount: 0)])
        #expect(choices.first?.name == "gone")
    }

    @Test func uncountedRowsAddNoCounts() {
        let built = tabs(review: [row(1, repo: "o/a", dimmed: true, counted: false)])
        let choices = RepoFocus.choices(prs: built, issues: nil, current: nil)
        #expect(choices == [RepoChoice(repo: "o/a", reviewCount: 0, openCount: 0)])
    }

    @Test func focusDroppedWhenRepoLeavesOrg() {
        #expect(
            !RepoFocus(repo: "o/gone").isValid(prs: tabs(), issues: nil, org: org(repos: ["a"])))
    }

    @Test func focusKeptWhileListed() {
        let built = tabs(team: [row(1, repo: "o/gone")])
        #expect(RepoFocus(repo: "o/gone").isValid(prs: built, issues: nil, org: org(repos: ["a"])))
        let closed = tabs(closed: [pr(1, repo: "O/Gone")])
        #expect(RepoFocus(repo: "o/gone").isValid(prs: closed, issues: nil, org: org(repos: ["a"])))
        let done = issueTabs(board: [IssueGroup(kind: .done, issues: [issue(2, repo: "o/gone")], counted: false)])
        #expect(RepoFocus(repo: "o/gone").isValid(prs: tabs(), issues: done, org: org(repos: ["a"])))
    }

    @Test func otherOwnerFocusIsKept() {
        #expect(RepoFocus(repo: "x/lib").isValid(prs: tabs(), issues: nil, org: org(repos: ["a"])))
    }

    @Test func truncatedRepoListKeepsFocus() {
        let truncated = org(repos: ["a"], complete: false)
        #expect(RepoFocus(repo: "o/gone").isValid(prs: tabs(), issues: nil, org: truncated))
    }

    @Test func emptyOrgReposKeepsFocus() {
        #expect(RepoFocus(repo: "o/gone").isValid(prs: tabs(), issues: nil, org: org(repos: [])))
    }

    @Test func orgRepoNameIgnoresCase() {
        #expect(RepoFocus(repo: "o/widgets").isValid(prs: tabs(), issues: nil, org: org(repos: ["WIDGETS"])))
        #expect(!RepoFocus(repo: "O/gone").isValid(prs: tabs(), issues: nil, org: org(repos: ["a"])))
    }

    @Test func sameNameDifferentOwnersOrderIsStable() {
        let built = tabs(team: [row(1, repo: "x/lib"), row(2, repo: "o/lib")])
        for _ in 0..<20 {
            let choices = RepoFocus.choices(prs: built, issues: nil, current: nil)
            #expect(choices.map(\.repo) == ["o/lib", "x/lib"])
        }
    }

    @Test func displayNameQualifiesDuplicateNames() {
        let choices = [
            RepoChoice(repo: "o/lib", reviewCount: 0, openCount: 1),
            RepoChoice(repo: "x/Lib", reviewCount: 0, openCount: 1),
            RepoChoice(repo: "o/app", reviewCount: 0, openCount: 1),
        ]
        #expect(RepoFocus(repo: "o/lib").displayName(among: choices, org: "o") == "o/lib")
        #expect(choices[0].displayName(among: choices, org: "o") == "o/lib")
        #expect(choices[1].displayName(among: choices, org: "o") == "x/Lib")
        #expect(choices[2].displayName(among: choices, org: "o") == "app")
    }

    @Test func displayNameQualifiesOtherOwners() {
        let choices = [RepoChoice(repo: "x/tool", reviewCount: 0, openCount: 1)]
        #expect(RepoFocus(repo: "x/tool").displayName(among: choices, org: "o") == "x/tool")
        #expect(choices[0].displayName(among: choices, org: "o") == "x/tool")
        #expect(RepoFocus(repo: "O/tool").displayName(among: [], org: "o") == "tool")
    }

    @Test func displayNamePlainForOrgRepos() {
        let choices = [
            RepoChoice(repo: "o/widgets", reviewCount: 2, openCount: 5),
            RepoChoice(repo: "o/gadgets", reviewCount: 0, openCount: 1),
        ]
        #expect(RepoFocus(repo: "o/widgets").displayName(among: choices, org: "O") == "widgets")
        #expect(choices[1].displayName(among: choices, org: "o") == "gadgets")
    }

    @Test func nameTieBreakIgnoresCase() {
        let built = tabs(team: [row(1, repo: "o/B"), row(2, repo: "o/a")])
        let choices = RepoFocus.choices(prs: built, issues: nil, current: nil)
        #expect(choices.map(\.repo) == ["o/a", "o/B"])
    }

    @Test func focusKeptWhileListedInAssignedOrCreated() {
        let group = [IssueGroup(kind: .all, issues: [issue(1, repo: "o/gone")], counted: true)]
        let focusGone = RepoFocus(repo: "o/gone")
        #expect(focusGone.isValid(prs: tabs(), issues: issueTabs(assigned: group), org: org(repos: ["a"])))
        #expect(focusGone.isValid(prs: tabs(), issues: issueTabs(created: group), org: org(repos: ["a"])))
    }
}
