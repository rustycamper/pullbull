import Foundation
import Testing
@testable import PullBullKit

@Suite struct RowChipsTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func row(
        repo: String = "org/repo",
        author: String = "me",
        state: PRState = .open,
        isDraft: Bool = false,
        ci: CIState = .success,
        reviews: [(String, ReviewState)] = [],
        dimmed: Bool = false,
        reason: ReviewReason? = nil,
        mergeable: Mergeable? = nil
    ) -> Row {
        let pr = PullRequest(
            key: PRKey(repo: repo, number: 1), title: "t",
            url: URL(string: "https://github.com/org/repo/pull/1")!,
            author: author, authorAvatarURL: nil, state: state, isDraft: isDraft,
            createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main",
            ci: ci, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: reviews.map { Review(author: $0.0, state: $0.1, submittedAt: t0) },
            reviewRequests: [], mergeable: mergeable)
        return Row(pr: pr, dimmed: dimmed, counted: !dimmed, reviewReason: reason)
    }

    // MARK: Mine

    @Test func mineWithNoReviewsIsInfoOnly() {
        #expect(RowChips(row: Self.row(), tab: .mine) == RowChips(action: nil, info: [.noReviews]))
    }

    @Test func mineDraftWithNoReviewsIsInfoOnly() {
        #expect(RowChips(row: Self.row(isDraft: true), tab: .mine) == RowChips(action: nil, info: [.noReviews]))
    }

    @Test func mineReadyToMergeIsACapsuleAndKeepsTheApprovalCount() {
        let chips = RowChips(row: Self.row(reviews: [("a", .approved), ("b", .approved)]), tab: .mine)
        #expect(chips == RowChips(action: .readyToMerge, info: [.approvals(2)]))
    }

    @Test func mineApprovedButFailingIsInfoOnly() {
        let chips = RowChips(row: Self.row(ci: .failure, reviews: [("a", .approved)]), tab: .mine)
        #expect(chips == RowChips(action: nil, info: [.approvals(1)]))
    }

    @Test func mineChangesRequestedIsACapsule() {
        let chips = RowChips(
            row: Self.row(reviews: [("alice", .changesRequested), ("bob", .approved), ("carol", .changesRequested)]),
            tab: .mine)
        #expect(chips == RowChips(action: .changesRequested(by: ["alice", "carol"]), info: [.approvals(1)]))
    }

    @Test func mineCommentsOnlyCountAsNoReviews() {
        #expect(RowChips(row: Self.row(reviews: [("a", .commented)]), tab: .mine) == RowChips(action: nil, info: [.noReviews]))
    }

    @Test func mineConflictingLosesReadyToMergeAndSaysConflicts() {
        let chips = RowChips(row: Self.row(reviews: [("a", .approved)], mergeable: .conflicting), tab: .mine)
        #expect(chips == RowChips(action: nil, info: [.approvals(1), .conflicts]))
    }

    @Test func mineConflictsFollowNoReviewsAndKeepChangesRequested() {
        #expect(RowChips(row: Self.row(mergeable: .conflicting), tab: .mine).info == [.noReviews, .conflicts])
        let chips = RowChips(row: Self.row(reviews: [("a", .changesRequested)], mergeable: .conflicting), tab: .mine)
        #expect(chips == RowChips(action: .changesRequested(by: ["a"]), info: [.conflicts]))
    }

    @Test func mineUnknownOrMergeableShowsNoConflicts() {
        for state: Mergeable? in [.unknown, .mergeable, nil] {
            let chips = RowChips(row: Self.row(reviews: [("a", .approved)], mergeable: state), tab: .mine)
            #expect(chips == RowChips(action: .readyToMerge, info: [.approvals(1)]))
        }
    }

    @Test func conflictsShowOnlyOnMine() {
        #expect(!RowChips(row: Self.row(mergeable: .conflicting), tab: .team).info.contains(.conflicts))
        let review = RowChips(row: Self.row(reason: .reRequested, mergeable: .conflicting), tab: .review)
        #expect(review.info == [.reRequested])
    }

    // MARK: Team

    @Test func teamShowsOnlyApprovals() {
        #expect(RowChips(row: Self.row(), tab: .team) == RowChips(action: nil, info: []))
        let chips = RowChips(row: Self.row(reviews: [("a", .approved), ("b", .changesRequested)]), tab: .team)
        #expect(chips == RowChips(action: nil, info: [.approvals(1)]))
    }

    @Test func teamNeverGetsACapsule() {
        #expect(RowChips(row: Self.row(reviews: [("a", .approved)]), tab: .team).action == nil)
    }

    // MARK: Review

    @Test func reviewFirstRequestShowsNothing() {
        #expect(RowChips(row: Self.row(reason: .requested), tab: .review) == RowChips(action: nil, info: []))
        #expect(RowChips(row: Self.row(), tab: .review) == RowChips(action: nil, info: []))
    }

    @Test func reviewReasonsAreInfo() {
        #expect(RowChips(row: Self.row(reason: .reRequested), tab: .review).info == [.reRequested])
        #expect(RowChips(row: Self.row(reason: .newCommitsSinceReview), tab: .review).info == [.newCommits])
        #expect(RowChips(row: Self.row(reason: .teamRequested("web")), tab: .review).info == [.viaTeam("org/web")])
    }

    @Test func reviewTeamWithoutOwnerUsesTheBareSlug() {
        #expect(RowChips(row: Self.row(repo: "", reason: .teamRequested("web")), tab: .review).info == [.viaTeam("web")])
    }

    @Test func reviewDimmedIsYouApproved() {
        let chips = RowChips(row: Self.row(reviews: [("me", .approved)], dimmed: true), tab: .review)
        #expect(chips == RowChips(action: nil, info: [.youApprovedNotCounted]))
    }

    @Test func reviewNeverGetsACapsule() {
        let chips = RowChips(row: Self.row(reviews: [("a", .changesRequested)], reason: .reRequested), tab: .review)
        #expect(chips.action == nil)
    }

    // MARK: Search

    static func search(
        author: String = "me", state: PRState = .open, reviews: [(String, ReviewState)] = [],
        mergeable: Mergeable? = nil, viewer: String = "me"
    ) -> RowChips {
        RowChips(
            searchResult: row(author: author, state: state, reviews: reviews, mergeable: mergeable).pr, viewer: viewer)
    }

    @Test func searchShowsNoCountsOrNoReviews() {
        #expect(Self.search() == RowChips(action: nil, info: []))
        #expect(Self.search(reviews: [("a", .approved)], viewer: "other") == RowChips(action: nil, info: []))
    }

    @Test func searchReadyToMergeOnlyOnTheViewersOwn() {
        #expect(Self.search(reviews: [("a", .approved)]) == RowChips(action: .readyToMerge, info: []))
        #expect(Self.search(reviews: [("a", .approved)], viewer: "ME").action == .readyToMerge)
        #expect(Self.search(author: "alice", reviews: [("a", .approved)]).action == nil)
    }

    @Test func searchChangesRequestedOnAnyOpenPR() {
        let chips = Self.search(author: "alice", reviews: [("bob", .changesRequested), ("carol", .approved)])
        #expect(chips == RowChips(action: .changesRequested(by: ["bob"]), info: []))
    }

    @Test func searchConflictsOnAnyOpenPR() {
        #expect(Self.search(author: "alice", mergeable: .conflicting) == RowChips(action: nil, info: [.conflicts]))
        let own = Self.search(reviews: [("a", .approved)], mergeable: .conflicting)
        #expect(own == RowChips(action: nil, info: [.conflicts]))
    }

    @Test func searchEndedPRShowsNothing() {
        for state: PRState in [.merged, .closed] {
            let chips = Self.search(state: state, reviews: [("a", .changesRequested)], mergeable: .conflicting)
            #expect(chips == RowChips(action: nil, info: []))
        }
    }

    // MARK: Wording

    @Test func infoWording() {
        #expect(RowChips.Info.approvals(1).text == "1")
        #expect(RowChips.Info.approvals(1).label == "1 approval")
        #expect(RowChips.Info.approvals(3).label == "3 approvals")
        #expect(RowChips.Info.noReviews.text == "No reviews")
        #expect(RowChips.Info.noReviews.label == "No reviews yet")
        #expect(RowChips.Info.newCommits.label == "New commits since your review")
        #expect(RowChips.Info.viaTeam("org/web").text == "via @org/web")
        #expect(RowChips.Info.reRequested.label == "Re-requested")
        #expect(RowChips.Info.approvals(2).isCount)
        #expect(!RowChips.Info.noReviews.isCount)
        #expect(RowChips.Info.conflicts.text == "Conflicts")
        #expect(RowChips.Info.conflicts.label == "Merge conflicts")
        #expect(RowChips.Info.conflicts.symbol == "exclamationmark.triangle")
        #expect(RowChips.Info.conflicts.isWarning)
        #expect(!RowChips.Info.conflicts.isCount)
        #expect(!RowChips.Info.noReviews.isWarning)
    }
}
