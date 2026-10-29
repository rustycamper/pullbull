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
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2])), basis: "b", shown: false)
        #expect(news.newCount(.issues) == 0)
        #expect(news.note(.issues) == nil)
    }

    @Test func newlyAssignedIssueCountsUntilIssuesIsShown() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1])), basis: "b", shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2, 3])), basis: "b", shown: false)
        #expect(news.newCount(.issues) == 2)
        #expect(news.note(.issues) == "2 newly assigned")
        news.show(.issues)
        #expect(news.newCount(.issues) == 0)
    }

    /// The mode on screen is always seen.
    @Test func shownModeNeverCounts() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested)]), basis: "b", shown: true)
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested), row(2, .requested)]), basis: "b", shown: true)
        #expect(news.newCount(.pullRequests) == 0)
    }

    /// A PR already in Review that comes back for another reason (re-requested, new commits) is new.
    @Test func reRequestAndNewCommitsCount() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested), row(2, .requested)]), basis: "b", shown: false)
        news.observe(.pullRequests, items: ModeNews.items(review: [
            row(1, .reRequested), row(2, .newCommitsSinceReview),
        ]), basis: "b", shown: false)
        #expect(news.newCount(.pullRequests) == 2)
        #expect(news.note(.pullRequests) == "2 new in Review")
    }

    /// Leaving the list (reviewed, unassigned) isn't news, and doesn't hide what is.
    @Test func itemsThatLeaveDontCount() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2])), basis: "b", shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([2, 3])), basis: "b", shown: false)
        #expect(news.newCount(.issues) == 1)
    }

    /// PRs I approved (no reason) and Assigned's Done group never count.
    @Test func approvedAndDoneDontCount() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: []), basis: "b", shown: false)
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, nil)]), basis: "b", shown: false)
        #expect(news.newCount(.pullRequests) == 0)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([])), basis: "b", shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([], done: [5])), basis: "b", shown: false)
        #expect(news.newCount(.issues) == 0)
    }

    /// Another basis (a Review filter changed, another board) is a baseline: what it adds isn't news.
    @Test func anotherBasisIsABaseline() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested)]), basis: "drafts hidden", shown: false)
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested), row(2, .requested)]),
                     basis: "drafts shown", shown: false)
        #expect(news.newCount(.pullRequests) == 0)
        // On that basis, a later arrival is news again.
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .requested), row(2, .requested), row(3, .requested)]),
                     basis: "drafts shown", shown: false)
        #expect(news.newCount(.pullRequests) == 1)
    }

    /// A team request is one reason whichever of my teams it names.
    @Test func teamSlugChangeIsNotNews() {
        var news = ModeNews()
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .teamRequested("web"))]), basis: "b", shown: false)
        news.observe(.pullRequests, items: ModeNews.items(review: [row(1, .teamRequested("api"))]), basis: "b", shown: false)
        #expect(news.newCount(.pullRequests) == 0)
    }

    @Test func assignedBasisIsTheBoard() {
        #expect(ModeNews.assignedBasis(.org("acme", 3)) != ModeNews.assignedBasis(.org("acme", 4)))
        #expect(ModeNews.assignedBasis(.org("ACME", 3)) == ModeNews.assignedBasis(.org("acme", 3)))
        #expect(ModeNews.assignedBasis(nil) == "")
    }

    @Test func resetStartsOver() {
        var news = ModeNews()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1])), basis: "b", shown: false)
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2])), basis: "b", shown: false)
        news.reset()
        news.observe(.issues, items: ModeNews.items(assigned: assigned([1, 2, 3])), basis: "b", shown: false)
        #expect(news.newCount(.issues) == 0)
    }
}
