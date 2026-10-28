import Foundation
import Testing
@testable import PullBullKit

@Suite struct ReadyToMergeTests {
    static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    static func pr(
        state: PRState = .open,
        isDraft: Bool = false,
        ci: CIState = .success,
        reviews: [ReviewState] = [.approved],
        mergeable: Mergeable? = nil
    ) -> PullRequest {
        PullRequest(
            key: PRKey(repo: "org/repo", number: 1), title: "t",
            url: URL(string: "https://github.com/org/repo/pull/1")!,
            author: "me", authorAvatarURL: nil, state: state, isDraft: isDraft,
            createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main",
            ci: ci, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: reviews.enumerated().map {
                Review(author: "r\($0.offset)", state: $0.element, submittedAt: t0)
            },
            reviewRequests: [], mergeable: mergeable)
    }

    @Test func approvedAndGreenIsReady() {
        #expect(ReviewRules.isReadyToMerge(Self.pr()))
    }

    @Test func approvedWithNoChecksIsReady() {
        #expect(ReviewRules.isReadyToMerge(Self.pr(ci: .none)))
    }

    @Test func approvalAlongsideCommentsIsReady() {
        #expect(ReviewRules.isReadyToMerge(Self.pr(reviews: [.commented, .approved, .dismissed])))
    }

    @Test func conflictingIsNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(mergeable: .conflicting)))
        #expect(!ReviewRules.isReadyToMerge(Self.pr(ci: .none, mergeable: .conflicting)))
    }

    @Test func mergeableOrUnknownIsReady() {
        #expect(ReviewRules.isReadyToMerge(Self.pr(mergeable: .mergeable)))
        // UNKNOWN is GitHub still computing after a push; it doesn't withhold the pill.
        #expect(ReviewRules.isReadyToMerge(Self.pr(mergeable: .unknown)))
    }

    @Test func approvedWithOnlySkippedChecksIsReady() {
        #expect(ReviewRules.isReadyToMerge(Self.pr(ci: .skipped)))
    }

    @Test func draftIsNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(isDraft: true)))
    }

    @Test func changesRequestedIsNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(reviews: [.approved, .changesRequested])))
    }

    @Test func pendingChecksAreNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(ci: .pending)))
    }

    @Test func failingChecksAreNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(ci: .failure)))
    }

    @Test func noApprovalIsNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(reviews: [])))
        #expect(!ReviewRules.isReadyToMerge(Self.pr(reviews: [.commented])))
        #expect(!ReviewRules.isReadyToMerge(Self.pr(reviews: [.dismissed])))
    }

    @Test func mergedOrClosedIsNotReady() {
        #expect(!ReviewRules.isReadyToMerge(Self.pr(state: .merged)))
        #expect(!ReviewRules.isReadyToMerge(Self.pr(state: .closed)))
    }
}
