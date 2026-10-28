import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func pr(
    _ n: Int, _ title: String, repo: String = "o/a", author: String = "alice", state: PRState = .open,
    updated: TimeInterval = 0, labels: [String] = []
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: n), title: title, url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: false,
        createdAt: t0, updatedAt: t0.addingTimeInterval(updated), closedAt: state == .open ? nil : t0,
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [], labels: labels)
}

private func issue(_ n: Int, _ title: String, repo: String = "o/a", isOpen: Bool = true) -> BoardIssue {
    BoardIssue(key: PRKey(repo: repo, number: n), title: title, url: URL(string: "https://x/\(n)")!, isOpen: isOpen)
}

private func row(_ pr: PullRequest, counted: Bool = true) -> Row {
    Row(pr: pr, dimmed: !counted, counted: counted)
}

private let tabs = BuiltTabs(
    review: TabContents(rows: [row(pr(1, "Fix login")), row(pr(2, "Fix logout", repo: "o/b"), counted: false)]),
    mine: TabContents(rows: [row(pr(3, "Add login page", author: "me", updated: 5))]),
    team: TabContents(rows: [row(pr(4, "Refactor", labels: ["bug"]))]),
    recentlyClosed: [pr(5, "Old login fix", author: "me", state: .merged)],
    hiddenApprovedCount: 0)

private let issueTabs = BuiltIssueTabs(
    assigned: IssueTabContents(groups: [
        IssueGroup(kind: .all, issues: [issue(10, "Login broken"), issue(11, "Docs")], counted: true),
    ]),
    created: IssueTabContents(groups: [IssueGroup(kind: .all, issues: [issue(12, "Login slow")], counted: true)]),
    board: IssueTabContents(groups: [
        IssueGroup(kind: .all, issues: [issue(13, "Nothing")], counted: true),
        IssueGroup(kind: .done, issues: [issue(14, "Login done", isOpen: false)], counted: false),
    ]),
    statusKnown: false, assignedLoaded: true, createdLoaded: false,
    assignedError: "offline", assignedFetchedAt: t0)

@Suite struct SearchScopeTests {
    // MARK: Scope

    @Test func pickingATabNarrowsAndPickingItAgainReturnsToEverything() {
        let mine = SearchScope.pullRequests(.mine)
        #expect(SearchScope.everything.picking(mine) == mine)
        #expect(mine.picking(mine) == .everything)
        #expect(mine.picking(.pullRequests(.team)) == .pullRequests(.team))
    }

    @Test func clearingTheFieldResetsTheScope() {
        let mine = SearchScope.pullRequests(.mine)
        #expect(mine.edited(to: "") == .everything)
        #expect(mine.edited(to: "  ") == .everything)
        #expect(mine.edited(to: "login") == mine)
        #expect(mine.edited(to: "@") == mine)
    }

    /// A type-anywhere tab of the other mode is dropped when the mode switches.
    @Test func aTabNamesItsMode() {
        #expect(SearchScope.pullRequests(.mine).mode == .pullRequests)
        #expect(SearchScope.issues(.assigned).mode == .issues)
        #expect(SearchScope.everything.mode == nil)
    }

    @Test func aScopeOutsideTheModeOrShownTabsIsEverything() {
        let team = SearchScope.pullRequests(.team)
        #expect(team.valid(in: .pullRequests, prTabs: [.review, .mine, .team]) == team)
        #expect(team.valid(in: .pullRequests, prTabs: [.review, .mine]) == .everything)
        #expect(team.valid(in: .issues, prTabs: [.review, .mine, .team]) == .everything)
        #expect(SearchScope.issues(.board).valid(in: .issues, prTabs: []) == .issues(.board))
        #expect(SearchScope.issues(.board).valid(in: .pullRequests, prTabs: [.review]) == .everything)
        #expect(!SearchScope.everything.isNarrowed)
        #expect(SearchScope.issues(.created).isNarrowed)
    }

    // MARK: Items and results

    @Test func aPRTabListsEveryRowAndMineItsRecentlyClosed() {
        #expect(SearchNarrowing.items(of: .review, in: tabs).map(\.key.number) == [1, 2])
        #expect(SearchNarrowing.items(of: .mine, in: tabs).map(\.key.number) == [3, 5])
        #expect(SearchNarrowing.items(of: .team, in: tabs).map(\.key.number) == [4])
    }

    @Test func anIssueTabListsEveryGroupDoneIncluded() {
        #expect(SearchNarrowing.items(of: .board, in: issueTabs).map(\.key.number) == [13, 14])
        let noBoard = BuiltIssueTabs(
            assigned: IssueTabContents(groups: []), created: IssueTabContents(groups: []), board: nil,
            statusKnown: false)
        #expect(SearchNarrowing.items(of: .board, in: noBoard).isEmpty)
    }

    @Test func narrowedResultsMatchOnlyThatTabsItems() throws {
        let results = try #require(SearchNarrowing.results(
            .parse("login"), scope: .pullRequests(.mine), tabs: tabs, issueTabs: issueTabs, focus: nil,
            viewer: "me"))
        #expect(results.openPRs.map(\.key.number) == [3])
        #expect(results.closedPRs.map(\.key.number) == [5])
        #expect(results.issues.isEmpty)
        #expect(results.phase == .done)
        #expect(!results.truncated)
    }

    @Test func narrowedResultsUseEveryMatcher() throws {
        func numbers(_ text: String, _ scope: SearchScope) throws -> [Int] {
            let results = try #require(SearchNarrowing.results(
                .parse(text), scope: scope, tabs: tabs, issueTabs: issueTabs, focus: nil, viewer: "me"))
            if case .issues = scope { return results.orderedKeys(mode: .issues).map(\.number) }
            return results.orderedKeys(mode: .pullRequests).map(\.number)
        }
        #expect(try numbers("@me", .pullRequests(.mine)) == [3, 5])
        #expect(try numbers("~bug", .pullRequests(.team)) == [4])
        #expect(try numbers("is:merged", .pullRequests(.mine)) == [5])
        #expect(try numbers("#1", .pullRequests(.review)) == [1])
        #expect(try numbers("#1", .pullRequests(.mine)) == [])
        #expect(try numbers("login", .issues(.assigned)) == [10])
        #expect(try numbers("login", .issues(.board)) == [14])
    }

    @Test func narrowedResultsRespectTheFocus() throws {
        let results = try #require(SearchNarrowing.results(
            .parse("fix"), scope: .pullRequests(.review), tabs: tabs, issueTabs: issueTabs,
            focus: RepoFocus(repo: "o/b"), viewer: "me"))
        #expect(results.openPRs.map(\.key.number) == [2])
    }

    @Test func everythingIsNotNarrowed() {
        #expect(SearchNarrowing.results(
            .parse("login"), scope: .everything, tabs: tabs, issueTabs: issueTabs, focus: nil, viewer: "me") == nil)
    }

    @Test func narrowingWithoutListsFindsNothing() throws {
        let results = try #require(SearchNarrowing.results(
            .parse("login"), scope: .issues(.assigned), tabs: nil, issueTabs: nil, focus: nil, viewer: "me"))
        #expect(results.isEmpty)
        #expect(results.phase == .done)
    }

    // MARK: Counts

    @Test func countsAreMatchesPerTab() {
        let counts = SearchNarrowing.counts(
            .parse("login"), prTabs: [.review, .mine, .team], tabs: tabs, issueTabs: issueTabs, focus: nil,
            viewer: "me")
        #expect(counts[.pullRequests(.review)] == .current(1))
        #expect(counts[.pullRequests(.mine)] == .current(2))
        #expect(counts[.pullRequests(.team)] == .current(0))
        #expect(counts[.issues(.assigned)] == .stale(1, error: "offline", since: t0))
        #expect(counts[.issues(.created)] == .unavailable)
        #expect(counts[.issues(.board)] == .current(1))
    }

    @Test func countsLeaveOutHiddenTabsAndRespectTheFocus() {
        let counts = SearchNarrowing.counts(
            .parse("fix"), prTabs: [.review, .mine], tabs: tabs, issueTabs: nil, focus: RepoFocus(repo: "o/a"),
            viewer: "me")
        #expect(counts[.pullRequests(.review)] == .current(1))
        #expect(counts[.pullRequests(.team)] == nil)
        #expect(counts[.issues(.assigned)] == nil)
    }

    @Test func anEmptyQueryCountsNothing() {
        #expect(SearchNarrowing.counts(
            .empty, prTabs: [.review], tabs: tabs, issueTabs: issueTabs, focus: nil, viewer: "me").isEmpty)
    }

    // MARK: Copy

    @Test func contextNamesTheTabAndMatches() {
        #expect(SearchContext.narrowedText(.parse("fix login"), tab: "Mine", matches: 3)
            == "“fix login” in Mine · 3 matches")
        #expect(SearchContext.narrowedText(.parse("#12"), tab: "Review", matches: 1) == "#12 in Review · 1 match")
        #expect(SearchContext.narrowedText(.parse("@bob ~bug is:open fix"), tab: "Team", matches: 0)
            == "@bob, ~bug and is:open · “fix” in Team · 0 matches")
    }

    @Test func contextAccessibilityLabel() {
        #expect(SearchContext.narrowedAccessibilityLabel(.parse("fix"), tab: "Mine", matches: 1, repo: nil)
            == "Titles matching fix in Mine, 1 match")
        #expect(SearchContext.narrowedAccessibilityLabel(.parse("#7"), tab: "Board", matches: 0, repo: "api")
            == "#7 in Board, in api, 0 matches")
        #expect(SearchContext.narrowedAccessibilityLabel(.parse("@bob fix"), tab: "Team", matches: 2, repo: nil)
            == "Filtered by @bob, titles matching fix, in Team, 2 matches")
    }

    @Test func linkNarrowsByRepoAndNumberIgnoringTheFocus() throws {
        let link = SearchQuery.parse("https://github.com/o/b/pull/2")
        let results = try #require(SearchNarrowing.results(
            link, scope: .pullRequests(.review), tabs: tabs, issueTabs: issueTabs,
            focus: RepoFocus(repo: "o/a"), viewer: "me"))
        #expect(results.openPRs.map(\.key) == [PRKey(repo: "o/b", number: 2)])
        let counts = SearchNarrowing.counts(
            .parse("o/a#2"), prTabs: [.review], tabs: tabs, issueTabs: issueTabs, focus: nil, viewer: "me")
        #expect(counts[.pullRequests(.review)] == .current(0))
        #expect(SearchContext.narrowedText(link, tab: "Review", matches: 1) == "o/b #2 in Review · 1 match")
        #expect(SearchContext.narrowedAccessibilityLabel(link, tab: "Review", matches: 1, repo: "a")
            == "o/b #2 in Review, 1 match")
    }

    @Test func emptyStateAnnouncementsAndSpokenCounts() {
        #expect(SearchContext.noMatches(inTab: "Mine") == "No matches in Mine")
        #expect(SearchContext.scopeAnnouncement(tab: "Mine", matches: 3) == "Searching Mine, 3 matches")
        #expect(SearchContext.scopeAnnouncement(tab: nil, matches: nil) == "Searching everything")
        #expect(SearchContext.spokenMatches(.current(1)) == "1 match")
        #expect(SearchContext.spokenMatches(.stale(4, error: "x", since: nil)) == "4 matches, didn't update")
        #expect(SearchContext.spokenMatches(.unavailable) == "unavailable")
    }
}
