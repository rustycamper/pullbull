import Foundation
import Testing
@testable import PullBullKit

private func pr(_ n: Int) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "o/a", number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: Date(), updatedAt: Date(), closedAt: nil,
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [.user("me")])
}

private func row(_ n: Int, _ reason: ReviewReason?) -> Row {
    Row(pr: pr(n), dimmed: false, counted: reason != nil, reviewReason: reason)
}

private func issue(_ n: Int) -> BoardIssue {
    BoardIssue(key: PRKey(repo: "o/a", number: n), title: "i\(n)", url: URL(string: "https://x/i\(n)")!, isOpen: true)
}

private func assigned(_ numbers: [Int], done: [Int] = []) -> IssueTabContents {
    IssueTabContents(groups: [
        IssueGroup(kind: .noStatus, issues: numbers.map(issue), counted: true),
        IssueGroup(kind: .done, issues: done.map(issue), counted: false),
    ])
}

@Suite struct ModeNewsTests {
    /// The first look only records what's there: nothing is new at launch or after a switch.
    @Test func firstLookIsABaseline() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2])), shown: false)
        #expect(news.newCount(.issues) == 0)
        #expect(news.note(.issues) == nil)
    }

    @Test func newlyAssignedIssueCountsUntilIssuesIsShown() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1])), shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2, 3])), shown: false)
        #expect(news.newCount(.issues) == 2)
        #expect(news.note(.issues) == "2 newly assigned")
        news.show(.issues)
        #expect(news.newCount(.issues) == 0)
    }

    /// The mode on screen is always seen.
    @Test func shownModeNeverCounts() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested)]), shown: true)
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested), row(2, .requested)]), shown: true)
        #expect(news.newCount(.pullRequests) == 0)
    }

    /// A PR already in Review that comes back for another reason (re-requested, new commits) is new.
    @Test func reRequestAndNewCommitsCount() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested), row(2, .requested)]), shown: false)
        news.observe(.pullRequests, items: ModeNews.items(review: [
            row(1, .reRequested), row(2, .newCommitsSinceReview),
        ]), shown: false)
        #expect(news.newCount(.pullRequests) == 2)
        #expect(news.note(.pullRequests) == "2 new in Review")
    }

    /// Leaving the list (reviewed, unassigned) isn't news, and doesn't hide what is.
    @Test func itemsThatLeaveDontCount() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2])), shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([2, 3])), shown: false)
        #expect(news.newCount(.issues) == 1)
    }

    /// PRs I approved (no reason) and Assigned's Done group never count.
    @Test func approvedAndDoneDontCount() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: []), shown: false)
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, nil)]), shown: false)
        #expect(news.newCount(.pullRequests) == 0)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([])), shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([], done: [5])), shown: false)
        #expect(news.newCount(.issues) == 0)
    }

    @Test func resetStartsOver() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1])), shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2])), shown: false)
        news.reset()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2, 3])), shown: false)
        #expect(news.newCount(.issues) == 0)
    }
}
