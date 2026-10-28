import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReviewRulesTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func pr(
        author: String = "alice",
        headCommitDate: Date? = nil,
        headCommitOid: String? = nil,
        reviews: [Review] = [],
        requests: [Reviewer] = []
    ) -> PullRequest {
        PullRequest(
            key: PRKey(repo: "org/repo", number: 1), title: "t",
            url: URL(string: "https://github.com/org/repo/pull/1")!,
            author: author, authorAvatarURL: nil, state: .open, isDraft: false,
            createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main",
            ci: .none, headCommitDate: headCommitDate, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: reviews, reviewRequests: requests, headCommitOid: headCommitOid)
    }

    static func status(_ pr: PullRequest, me: String = "me", teams: Set<String> = []) -> ReviewStatus {
        ReviewRules.status(of: pr, me: me, myTeams: teams)
    }

    @Test func directRequestNeedsReview() {
        #expect(Self.status(Self.pr(requests: [.user("me")])) == .needsReview(.requested))
    }

    @Test func teamRequestNoReviewNeedsReview() {
        let pr = Self.pr(requests: [.team("core")])
        #expect(Self.status(pr, teams: ["core"]) == .needsReview(.teamRequested("core")))
    }

    @Test func teamRequestAfterMyCommentIsReviewed() {
        let pr = Self.pr(
            headCommitDate: Self.t0,
            reviews: [Review(author: "me", state: .commented, submittedAt: Self.t0.addingTimeInterval(60))],
            requests: [.team("core")])
        #expect(Self.status(pr, teams: ["core"]) == .reviewedByMe)
    }

    @Test func approvedIsApprovedByMe() {
        let pr = Self.pr(
            headCommitDate: Self.t0,
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0.addingTimeInterval(60))])
        #expect(Self.status(pr) == .approvedByMe)
    }

    @Test func newCommitAfterApprovalNeedsReview() {
        let pr = Self.pr(
            headCommitDate: Self.t0.addingTimeInterval(3600),
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0)])
        #expect(Self.status(pr) == .needsReview(.newCommitsSinceReview))
    }

    @Test func reRequestAfterReviewNeedsReview() {
        let pr = Self.pr(
            headCommitDate: Self.t0,
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0.addingTimeInterval(60))],
            requests: [.user("me")])
        #expect(Self.status(pr) == .needsReview(.reRequested))
    }

    @Test func pendingDraftReviewIgnored() {
        let draft = Review(author: "me", state: .pending, submittedAt: nil)
        #expect(Self.status(Self.pr(reviews: [draft])) == .notRequested)
        #expect(Self.status(Self.pr(reviews: [draft], requests: [.team("core")]), teams: ["core"]) == .needsReview(.teamRequested("core")))
    }

    @Test func ownPRNotRequested() {
        let pr = Self.pr(author: "me", requests: [.user("me")])
        #expect(Self.status(pr) == .notRequested)
    }

    @Test func otherTeamNotRequested() {
        let pr = Self.pr(requests: [.team("other")])
        #expect(Self.status(pr, teams: ["core"]) == .notRequested)
    }

    @Test func reviewWithoutSubmittedAtIsIgnored() {
        let r = Review(author: "me", state: .approved, submittedAt: nil)
        #expect(Self.status(Self.pr(reviews: [r])) == .notRequested)
    }

    @Test func missingHeadCommitDateFallsToReviewedState() {
        let approved = Review(author: "me", state: .approved, submittedAt: Self.t0)
        let changes = Review(author: "me", state: .changesRequested, submittedAt: Self.t0)
        #expect(Self.status(Self.pr(headCommitDate: nil, reviews: [approved])) == .approvedByMe)
        #expect(Self.status(Self.pr(headCommitDate: nil, reviews: [changes])) == .reviewedByMe)
    }

    @Test func commitEqualToReviewTimeIsNotNewer() {
        let r = Review(author: "me", state: .approved, submittedAt: Self.t0)
        #expect(Self.status(Self.pr(headCommitDate: Self.t0, reviews: [r])) == .approvedByMe)
    }

    @Test func loginsCompareCaseInsensitively() {
        #expect(Self.status(Self.pr(author: "Me", requests: [.user("me")]), me: "ME") == .notRequested)
        #expect(Self.status(Self.pr(requests: [.user("ME")]), me: "me") == .needsReview(.requested))
        let r = Review(author: "ME", state: .approved, submittedAt: Self.t0)
        #expect(Self.status(Self.pr(headCommitDate: Self.t0, reviews: [r]), me: "me") == .approvedByMe)
        #expect(Self.status(Self.pr(requests: [.team("Core")]), teams: ["core"]) == .needsReview(.teamRequested("Core")))
    }

    @Test func dismissedReviewCountsAsReviewedByMe() {
        let r = Review(author: "me", state: .dismissed, submittedAt: Self.t0)
        #expect(Self.status(Self.pr(headCommitDate: Self.t0, reviews: [r])) == .reviewedByMe)
    }

    // MARK: Commit oids

    @Test func pushedOlderCommitAfterReviewNeedsReview() {
        // The new head was committed before my review but pushed after it: dates miss it, oids don't.
        let pr = Self.pr(
            headCommitDate: Self.t0, headCommitOid: "bbb",
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0.addingTimeInterval(60), commitOid: "aaa")])
        #expect(Self.status(pr) == .needsReview(.newCommitsSinceReview))
    }

    @Test func reviewOfHeadCommitIsCurrentWhateverTheDates() {
        let pr = Self.pr(
            headCommitDate: Self.t0.addingTimeInterval(3600), headCommitOid: "aaa",
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0, commitOid: "aaa")])
        #expect(Self.status(pr) == .approvedByMe)
    }

    @Test func missingOidFallsBackToDates() {
        let later = Self.pr(
            headCommitDate: Self.t0.addingTimeInterval(3600), headCommitOid: "bbb",
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0)])
        #expect(Self.status(later) == .needsReview(.newCommitsSinceReview))
        let earlier = Self.pr(
            headCommitDate: Self.t0, headCommitOid: nil,
            reviews: [Review(author: "me", state: .approved, submittedAt: Self.t0.addingTimeInterval(60), commitOid: "aaa")])
        #expect(Self.status(earlier) == .approvedByMe)
    }

    // MARK: Reasons

    @Test func directRequestAfterMyReviewIsReRequested() {
        let pr = Self.pr(
            headCommitDate: Self.t0.addingTimeInterval(3600),
            reviews: [Review(author: "me", state: .changesRequested, submittedAt: Self.t0)],
            requests: [.user("me")])
        #expect(Self.status(pr) == .needsReview(.reRequested))
    }

    @Test func directRequestWithOnlyADraftIsAFirstRequest() {
        let draft = Review(author: "me", state: .pending, submittedAt: nil)
        #expect(Self.status(Self.pr(reviews: [draft], requests: [.user("me")])) == .needsReview(.requested))
    }

    @Test func directRequestWinsOverTeamRequest() {
        let pr = Self.pr(requests: [.team("core"), .user("me")])
        #expect(Self.status(pr, teams: ["core"]) == .needsReview(.requested))
    }

    @Test func teamReasonNamesMyTeamNotAnother() {
        let pr = Self.pr(requests: [.team("other"), .team("Backend")])
        #expect(Self.status(pr, teams: ["core", "backend"]) == .needsReview(.teamRequested("Backend")))
    }

    @Test func teamRequestWithNewCommitsSinceMyReview() {
        let pr = Self.pr(
            headCommitOid: "bbb",
            reviews: [Review(author: "me", state: .commented, submittedAt: Self.t0, commitOid: "aaa")],
            requests: [.team("core")])
        #expect(Self.status(pr, teams: ["core"]) == .needsReview(.newCommitsSinceReview))
    }

    @Test func reviewReasonIsNilUnlessNeedsReview() {
        #expect(ReviewStatus.needsReview(.reRequested).reviewReason == .reRequested)
        for status in [ReviewStatus.approvedByMe, .reviewedByMe, .notRequested] {
            #expect(status.reviewReason == nil)
        }
    }
}
