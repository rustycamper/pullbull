import Foundation
import Testing
@testable import PullBullKit

private func key(_ n: Int, repo: String = "o/a") -> PRKey { PRKey(repo: repo, number: n) }

private func pr(_ n: Int, repo: String = "o/a", state: PRState = .open) -> PullRequest {
    PullRequest(
        key: key(n, repo: repo), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: "alice", authorAvatarURL: nil, state: state, isDraft: false,
        createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0), closedAt: nil,
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func row(_ n: Int, repo: String = "o/a") -> Row { Row(pr: pr(n, repo: repo), dimmed: false, counted: true) }

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
}
