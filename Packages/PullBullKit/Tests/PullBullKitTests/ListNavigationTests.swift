import Foundation
import Testing
@testable import PullBullKit

private func key(_ n: Int, repo: String = "o/a") -> PRKey { PRKey(repo: repo, number: n) }

private func pr(_ n: Int, repo: String = "o/a", state: PRState = .open, author: String = "alice") -> PullRequest {
    PullRequest(
        key: key(n, repo: repo), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: false,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), closedAt: nil,
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func row(_ n: Int, repo: String = "o/a", author: String = "alice") -> Row {
    Row(pr: pr(n, repo: repo, author: author), dimmed: false, counted: true)
}

private func issue(_ n: Int) -> BoardIssue {
    BoardIssue(key: key(n), title: "i\(n)", url: URL(string: "https://x/\(n)")!, isOpen: true)
}

@Suite struct ListNavigationTests {
    // MARK: Rows shown

    @Test func repoGroupsKeepFirstAppearanceOrder() {
        let groups = ListNavigation.repoGroups([row(1, repo: "o/b"), row(2), row(3, repo: "o/b"), row(4)])
        #expect(groups.map(\.repo) == ["o/b", "o/a"])
        #expect(groups.map { $0.rows.map(\.pr.key.number) } == [[1, 3], [2, 4]])
    }

    @Test func prKeysFollowGroupingOrder() {
        let contents = TabContents(rows: [row(1, repo: "o/b"), row(2), row(3, repo: "o/b")])
        let flat = ListNavigation.prKeys(
            tab: .review, contents: contents, groupedByRepo: false, recentlyClosed: [], closedExpanded: false)
        let grouped = ListNavigation.prKeys(
            tab: .review, contents: contents, groupedByRepo: true, recentlyClosed: [], closedExpanded: false)
        #expect(flat.map(\.number) == [1, 2, 3])
        #expect(grouped.map(\.number) == [1, 3, 2])
    }

    @Test func recentlyClosedRowsOnlyWhenExpandedOnMine() {
        let contents = TabContents(rows: [row(1)])
        let closed = [pr(9, state: .merged)]
        func keys(_ tab: PRTab, expanded: Bool) -> [Int] {
            ListNavigation.prKeys(
                tab: tab, contents: contents, groupedByRepo: false, recentlyClosed: closed,
                closedExpanded: expanded
            ).map(\.number)
        }
        #expect(keys(.mine, expanded: false) == [1])
        #expect(keys(.mine, expanded: true) == [1, 9])
        #expect(keys(.team, expanded: true) == [1])
    }

    @Test func doneRowsOnlyWhenExpandedAndLast() {
        let option = StatusOption(id: "s", name: "Todo")
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .status(option), issues: [issue(1), issue(2)], counted: true),
            IssueGroup(kind: .done, issues: [issue(3)], counted: false),
            IssueGroup(kind: .notOnBoard, issues: [issue(4)], counted: true),
        ])
        #expect(ListNavigation.issueKeys(contents, doneExpanded: false).map(\.number) == [1, 2, 4])
        #expect(ListNavigation.issueKeys(contents, doneExpanded: true).map(\.number) == [1, 2, 4, 3])
    }

    // MARK: Moving

    @Test func moveStartsAtTheEndItHeadsFrom() {
        let keys = [key(1), key(2), key(3)]
        #expect(ListNavigation.move(nil, by: 1, in: keys) == key(1))
        #expect(ListNavigation.move(nil, by: -1, in: keys) == key(3))
    }

    @Test func moveStepsAndStopsAtTheEnds() {
        let keys = [key(1), key(2), key(3)]
        #expect(ListNavigation.move(key(1), by: 1, in: keys) == key(2))
        #expect(ListNavigation.move(key(2), by: -1, in: keys) == key(1))
        #expect(ListNavigation.move(key(3), by: 1, in: keys) == key(3))
        #expect(ListNavigation.move(key(1), by: -1, in: keys) == key(1))
    }

    @Test func moveFromAHiddenRowRestartsAtAnEnd() {
        // The selection was in a group that has since folded, or the row left the list.
        let keys = [key(1), key(2)]
        #expect(ListNavigation.move(key(9), by: 1, in: keys) == key(1))
        #expect(ListNavigation.move(key(9), by: -1, in: keys) == key(2))
    }

    @Test func moveInAnEmptyListSelectsNothing() {
        #expect(ListNavigation.move(key(1), by: 1, in: []) == nil)
    }

    @Test func shownDropsAHiddenSelection() {
        #expect(ListNavigation.shown(key(1), in: [key(1)]) == key(1))
        #expect(ListNavigation.shown(key(2), in: [key(1)]) == nil)
        #expect(ListNavigation.shown(nil, in: [key(1)]) == nil)
    }

    // MARK: Sub-tabs and references

    @Test func tabsMoveAlongTheBarAndStopAtTheEnds() {
        #expect(ListNavigation.tab(PRTab.review, movedBy: 1) == .mine)
        #expect(ListNavigation.tab(PRTab.team, movedBy: 1) == .team)
        #expect(ListNavigation.tab(PRTab.review, movedBy: -1) == .review)
        #expect(ListNavigation.tab(IssueTab.board, movedBy: -1) == .created)
        #expect(ListNavigation.tab(IssueTab.assigned, movedBy: 1) == .created)
        // No org: Team isn't shown, so → stops at Mine.
        let shown = PRTab.shown(in: .personal(login: "me"))
        #expect(shown == [.review, .mine])
        #expect(PRTab.shown(in: .org("o")) == [.review, .mine, .team])
        #expect(ListNavigation.tab(PRTab.mine, movedBy: 1, among: shown) == .mine)
        #expect(ListNavigation.tab(PRTab.review, movedBy: 1, among: shown) == .mine)
    }

    @Test func referenceIsOwnerRepoHashNumber() {
        #expect(ListNavigation.reference(PRKey(repo: "initech/widgets", number: 490)) == "initech/widgets#490")
    }

    @Test func fallbackPagesForPRsAndIssues() {
        let key = PRKey(repo: "initech/widgets", number: 490)
        #expect(GitHubLinks.pullRequest(key).absoluteString == "https://github.com/initech/widgets/pull/490")
        #expect(GitHubLinks.issue(key).absoluteString == "https://github.com/initech/widgets/issues/490")
    }

    // MARK: Author grouping

    @Test func authorGroupsSortedByName() {
        let groups = ListNavigation.authorGroups([
            row(1, author: "zoe"), row(2, author: "Ann"), row(3, author: "bob"), row(4, author: "zoe"),
            row(5, author: "Ann"),
        ])
        #expect(groups.map(\.author) == ["Ann", "bob", "zoe"])
        #expect(groups.map { $0.rows.map(\.pr.key.number) } == [[2, 5], [3], [1, 4]])
    }

    @Test func prKeysByAuthorFollowTheGroups() {
        let contents = TabContents(rows: [row(1, author: "zoe"), row(2, author: "ann"), row(3, author: "zoe")])
        let keys = ListNavigation.prKeys(
            tab: .team, contents: contents, grouping: .author, recentlyClosed: [], closedExpanded: false)
        #expect(keys.map(\.number) == [2, 1, 3])
    }

    @Test func prKeysFollowRepositoryAndNoneGrouping() {
        let contents = TabContents(rows: [row(1, repo: "o/b"), row(2), row(3, repo: "o/b")])
        func numbers(_ g: PRGrouping) -> [Int] {
            ListNavigation.prKeys(tab: .review, contents: contents, grouping: g, recentlyClosed: [], closedExpanded: false)
                .map(\.number)
        }
        #expect(numbers(.repository) == [1, 3, 2])
        #expect(numbers(.none) == [1, 2, 3])
    }

    @Test func recentlyClosedComesLastOnMine() {
        let contents = TabContents(rows: [row(1)])
        let groups = ListNavigation.prGroups(
            tab: .mine, contents: contents, grouping: .repository, recentlyClosed: [pr(9, state: .merged)],
            closedExpanded: true)
        #expect(groups.map { $0.map(\.number) } == [[1], [9]])
    }

    // MARK: PRGrouping

    @Test func teamByAuthorWinsOverEverything() {
        var s = AppSettings()
        s.groupTeamByAuthor = true
        for g in [Grouping.repository, .none] {
            s.grouping = g
            #expect(PRGrouping.forTab(.team, settings: s, repoFocused: false) == .author)
            #expect(PRGrouping.forTab(.team, settings: s, repoFocused: true) == .author)
        }
        s.grouping = .repository
        #expect(PRGrouping.forTab(.review, settings: s, repoFocused: false) == .repository)
        #expect(PRGrouping.forTab(.mine, settings: s, repoFocused: false) == .repository)
    }

    @Test func teamWithoutAuthorGroupingFollowsTheRepoRule() {
        var s = AppSettings()
        #expect(PRGrouping.forTab(.team, settings: s, repoFocused: false) == .repository)
        #expect(PRGrouping.forTab(.team, settings: s, repoFocused: true) == .none)
        s.grouping = .none
        #expect(PRGrouping.forTab(.team, settings: s, repoFocused: false) == .none)
        #expect(PRGrouping.forTab(.review, settings: s, repoFocused: false) == .none)
    }
}

// MARK: Group jumps and edges

private let a = key(1), b = key(2), c = key(3), d = key(4), e = key(5)
private let groups: [[PRKey]] = [[a, b], [c], [d, e]]

extension ListNavigationTests {
    @Test func jumpDown() {
        #expect(ListNavigation.jump(b, by: 1, in: groups) == c)
        #expect(ListNavigation.jump(c, by: 1, in: groups) == d)
        #expect(ListNavigation.jump(e, by: 1, in: groups) == nil)
        #expect(ListNavigation.jump(nil, by: 1, in: groups) == a)
    }

    /// ⌥↑ on a row that isn't first in its group goes to its group's first row (Ruling 14).
    @Test func jumpUp() {
        #expect(ListNavigation.jump(e, by: -1, in: groups) == d)
        #expect(ListNavigation.jump(d, by: -1, in: groups) == c)
        #expect(ListNavigation.jump(a, by: -1, in: groups) == nil)
        #expect(ListNavigation.jump(nil, by: -1, in: groups) == d)
    }

    @Test func jumpSkipsEmptyGroupsAndUnshownSelection() {
        #expect(ListNavigation.jump(b, by: 1, in: [[a, b], [], [c]]) == c)
        #expect(ListNavigation.jump(key(99), by: 1, in: groups) == a)
        #expect(ListNavigation.jump(nil, by: 1, in: []) == nil)
    }

    @Test func jumpSkipsFolded() {
        let lane = { (id: String) in IssueGroupKind.status(StatusOption(id: id, name: id)) }
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: lane("1"), issues: [issue(1), issue(2)], counted: true),
            IssueGroup(kind: lane("2"), issues: [issue(3)], counted: true),
            IssueGroup(kind: lane("3"), issues: [issue(4), issue(5)], counted: true),
        ])
        let groups = ListNavigation.issueGroups(contents, doneExpanded: false, folded: [lane("2")])
        #expect(groups.map { $0.map(\.number) } == [[1, 2], [4, 5]])
        #expect(ListNavigation.jump(key(1), by: 1, in: groups) == key(4))
    }

    @Test func doneCountsWhenExpanded() {
        let option = StatusOption(id: "s", name: "Todo")
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .status(option), issues: [issue(1)], counted: true),
            IssueGroup(kind: .done, issues: [issue(3)], counted: false),
            IssueGroup(kind: .notOnBoard, issues: [issue(4)], counted: true),
        ])
        #expect(ListNavigation.issueGroups(contents, doneExpanded: false, folded: []).map { $0.map(\.number) }
            == [[1], [4]])
        #expect(ListNavigation.issueGroups(contents, doneExpanded: true, folded: []).map { $0.map(\.number) }
            == [[1], [4], [3]])
    }

    @Test func ungroupedIsNotGrouped() {
        let created = IssueTabContents(groups: [IssueGroup(kind: .all, issues: [issue(1)], counted: true)])
        #expect(!ListNavigation.isGrouped(created))
        let repos = IssueTabContents(groups: [
            IssueGroup(kind: .repo("o/a"), issues: [issue(1)], counted: true),
            IssueGroup(kind: .repo("o/b"), issues: [issue(2)], counted: true),
        ])
        #expect(ListNavigation.isGrouped(repos))
        let focused = RepoFocus(repo: "o/a").scope(repos)
        #expect(!ListNavigation.isGrouped(focused.contents))
        #expect(!ListNavigation.isGrouped(prGrouping: .none))
        #expect(ListNavigation.isGrouped(prGrouping: .repository))
        #expect(ListNavigation.isGrouped(prGrouping: .author))
    }

    @Test func edge() {
        #expect(ListNavigation.edge(last: false, in: [a, b, c]) == a)
        #expect(ListNavigation.edge(last: true, in: [a, b, c]) == c)
        #expect(ListNavigation.edge(last: true, in: []) == nil)
        #expect(ListNavigation.edge(last: false, in: []) == nil)
    }
}
