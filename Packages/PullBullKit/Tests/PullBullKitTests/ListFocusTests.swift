import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()
private let time = TimeFocus(step: .today, now: now, calendar: calendar)
private let recent = time.start.addingTimeInterval(60)
private let old = time.start.addingTimeInterval(-60)
private let repoFocus = RepoFocus(repo: "o/a")
private let todo = StatusOption(id: "s1", name: "Todo")

private func pr(_ n: Int, repo: String, updatedAt: Date) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: updatedAt, updatedAt: updatedAt, closedAt: nil,
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func row(_ n: Int, repo: String, at date: Date, dimmed: Bool = false, counted: Bool = true) -> Row {
    Row(pr: pr(n, repo: repo, updatedAt: date), dimmed: dimmed, counted: counted)
}

private func issue(_ n: Int, repo: String, at date: Date?) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: n), title: "i\(n)", url: URL(string: "https://x/\(n)")!,
        isOpen: true, updatedAt: date)
}

@Suite struct ListFocusTests {
    @Test func timeOnlyHidesOldRowsAndKeepsGroupsSeparate() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .repo("o/a"), issues: [issue(1, repo: "o/a", at: recent), issue(2, repo: "o/a", at: old)], counted: true),
            IssueGroup(kind: .repo("o/b"), issues: [issue(3, repo: "o/b", at: recent)], counted: true),
        ])
        let scoped = ListFocus(repo: nil, time: time).scope(contents)
        #expect(scoped.contents.groups.count == 2)
        #expect(scoped.contents.groups.map { $0.issues.map(\.key.number) } == [[1], [3]])
        #expect(scoped.hiddenCount == 1)
    }

    @Test func bothFocusesCountEachHiddenRowOnce() {
        let contents = TabContents(rows: [
            row(1, repo: "o/a", at: recent), row(2, repo: "o/a", at: old),
            row(3, repo: "o/b", at: recent), row(4, repo: "o/b", at: old),
        ])
        let scoped = ListFocus(repo: repoFocus, time: time).scope(contents)
        #expect(scoped.contents.count == 1)
        #expect(scoped.hiddenCount == 3)
        #expect(scoped.otherCount == 3)
    }

    @Test func dimmedRowsHiddenButNotCounted() {
        let contents = TabContents(rows: [
            row(1, repo: "o/a", at: recent),
            row(2, repo: "o/a", at: old, dimmed: true, counted: false),
        ])
        let scoped = ListFocus(repo: nil, time: time).scope(contents)
        #expect(scoped.contents.rows.map(\.pr.key.number) == [1])
        #expect(scoped.hiddenCount == 1)
        #expect(scoped.otherCount == 0)
    }

    @Test func undatedIssueIsHidden() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .status(todo), issues: [issue(1, repo: "o/a", at: nil), issue(2, repo: "o/a", at: recent)], counted: true)
        ])
        let scoped = ListFocus(repo: nil, time: time).scope(contents)
        #expect(scoped.contents.groups.first?.issues.map(\.key.number) == [2])
        #expect(scoped.hiddenCount == 1)
    }

    @Test func emptyLanesFoldAway() {
        let contents = IssueTabContents(groups: [
            IssueGroup(kind: .status(todo), issues: [issue(1, repo: "o/a", at: old)], counted: true),
            IssueGroup(kind: .done, issues: [issue(2, repo: "o/a", at: recent)], counted: false),
        ])
        let scoped = ListFocus(repo: nil, time: time).scope(contents)
        #expect(scoped.contents.groups.map(\.kind) == [.done])
    }

    @Test func repoOnlyMatchesRepoFocus() {
        let rows = TabContents(rows: [
            row(1, repo: "o/a", at: old), row(2, repo: "o/b", at: recent),
            row(3, repo: "o/a", at: recent, dimmed: true, counted: false),
        ])
        let issues = IssueTabContents(groups: [
            IssueGroup(kind: .repo("o/b"), issues: [issue(2, repo: "o/b", at: recent)], counted: true),
            IssueGroup(kind: .repo("o/a"), issues: [issue(1, repo: "o/a", at: old)], counted: true),
            IssueGroup(kind: .done, issues: [issue(3, repo: "o/b", at: nil)], counted: false),
        ])
        let closed = [pr(1, repo: "o/a", updatedAt: old), pr(2, repo: "o/b", updatedAt: old)]
        let combined = ListFocus(repo: repoFocus, time: nil)
        let tab = combined.scope(rows)
        let expectedTab = repoFocus.scope(rows)
        #expect(tab.contents.rows.map(\.id) == expectedTab.contents.rows.map(\.id))
        #expect(tab.otherCount == expectedTab.otherCount)
        #expect(tab.hiddenCount == expectedTab.hiddenCount)
        #expect(combined.scope(issues) == repoFocus.scope(issues))
        #expect(combined.scope(closed).map(\.key) == repoFocus.scope(closed).map(\.key))
    }

    @Test func emptyTitle() {
        #expect(ListFocus(repo: repoFocus, time: nil).emptyTitle(repoName: "widgets", tabTitle: "Review") == "Nothing in widgets on Review")
        #expect(ListFocus(repo: nil, time: time).emptyTitle(repoName: nil, tabTitle: "Review") == "Nothing updated today on Review")
        #expect(ListFocus(repo: repoFocus, time: time).emptyTitle(repoName: "widgets", tabTitle: "Review") == "Nothing in widgets updated today on Review")
    }

    @Test func hiddenText() {
        #expect(ListFocus(repo: repoFocus, time: nil).hiddenText(3) == "3 in other repos")
        #expect(ListFocus(repo: nil, time: time).hiddenText(3) == "3 hidden")
        #expect(ListFocus(repo: repoFocus, time: time).hiddenText(3) == "3 hidden")
    }
}
