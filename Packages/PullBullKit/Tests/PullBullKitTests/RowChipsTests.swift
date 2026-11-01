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
        reviews: [(String, ReviewState)] = [("x", .commented)],
        requests: [(Reviewer, Date?)] = [],
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
            reviewRequests: requests.map(\.0), mergeable: mergeable,
            reviewRequestTimes: Dictionary(uniqueKeysWithValues: requests.compactMap { r in r.1.map { (r.0.key, $0) } }))
        return Row(pr: pr, dimmed: dimmed, counted: !dimmed, reviewReason: reason)
    }

    static let now = t0 + 5 * 86_400

    static func chips(_ row: Row, _ tab: PRTab) -> RowChips {
        RowChips(row: row, tab: tab, me: "me", myTeams: [], now: now)
    }

    static func wait(_ row: Row, _ tab: PRTab) -> RowChips.Info {
        .reviewWait(ReviewWait.make(for: row.pr, me: "me", myTeams: [], reviewLayout: tab == .review, now: now)!)
    }

    // MARK: Mine

    @Test func mineWithNoReviewsIsInfoOnly() {
        let row = Self.row(reviews: [])
        #expect(Self.chips(row, .mine) == RowChips(action: nil, info: [Self.wait(row, .mine)]))
        #expect(Self.chips(row, .mine).info.first?.text == "No reviewer 5d")
    }

    @Test func mineDraftShowsNoWait() {
        #expect(Self.chips(Self.row(isDraft: true, reviews: []), .mine) == RowChips(action: nil, info: []))
    }

    @Test func mineReadyToMergeIsACapsuleAndKeepsTheApprovalCount() {
        let chips = Self.chips(Self.row(reviews: [("a", .approved), ("b", .approved)]), .mine)
        #expect(chips == RowChips(action: .readyToMerge, info: [.approvals(2)]))
    }

    @Test func mineApprovedButFailingIsInfoOnly() {
        let chips = Self.chips(Self.row(ci: .failure, reviews: [("a", .approved)]), .mine)
        #expect(chips == RowChips(action: nil, info: [.approvals(1)]))
    }

    @Test func mineChangesRequestedIsACapsule() {
        let chips = Self.chips(
            Self.row(reviews: [("alice", .changesRequested), ("bob", .approved), ("carol", .changesRequested)]),
            .mine)
        #expect(chips == RowChips(action: .changesRequested(by: ["alice", "carol"]), info: [.approvals(1)]))
    }

    @Test func mineCommentsOnlyShowNoWait() {
        #expect(Self.chips(Self.row(reviews: [("a", .commented)]), .mine) == RowChips(action: nil, info: []))
    }

    @Test func mineConflictingLosesReadyToMergeAndSaysConflicts() {
        let chips = Self.chips(Self.row(reviews: [("a", .approved)], mergeable: .conflicting), .mine)
        #expect(chips == RowChips(action: nil, info: [.approvals(1), .conflicts]))
    }

    @Test func mineConflictsFollowNoReviewsAndKeepChangesRequested() {
        let unreviewed = Self.row(reviews: [], mergeable: .conflicting)
        #expect(Self.chips(unreviewed, .mine).info == [Self.wait(unreviewed, .mine), .conflicts])
        let chips = Self.chips(Self.row(reviews: [("a", .changesRequested)], mergeable: .conflicting), .mine)
        #expect(chips == RowChips(action: .changesRequested(by: ["a"]), info: [.conflicts]))
    }

    @Test func mineUnknownOrMergeableShowsNoConflicts() {
        for state: Mergeable? in [.unknown, .mergeable, nil] {
            let chips = Self.chips(Self.row(reviews: [("a", .approved)], mergeable: state), .mine)
            #expect(chips == RowChips(action: .readyToMerge, info: [.approvals(1)]))
        }
    }

    @Test func conflictsShowOnEveryTab() {
        #expect(Self.chips(Self.row(mergeable: .conflicting), .team).info == [.conflicts])
        let withApproval = Self.chips(Self.row(reviews: [("a", .approved)], mergeable: .conflicting), .team)
        #expect(withApproval.info == [.approvals(1), .conflicts])
        let review = Self.chips(Self.row(reason: .reRequested, mergeable: .conflicting), .review)
        #expect(review.info == [.reRequested, .conflicts])
        let viaTeam = Self.chips(Self.row(reason: .teamRequested("core"), mergeable: .conflicting), .review)
        #expect(viaTeam.info == [.viaTeam("org/core"), .conflicts])
        #expect(Self.chips(Self.row(reason: .requested, mergeable: .conflicting), .review).info == [.conflicts])
        let dimmed = Self.chips(Self.row(reviews: [("me", .approved)], dimmed: true, mergeable: .conflicting), .review)
        #expect(dimmed == RowChips(action: nil, info: [.youApprovedNotCounted, .conflicts]))
    }

    @Test func reviewUnknownOrMergeableShowsNoConflicts() {
        for state: Mergeable? in [.unknown, .mergeable, nil] {
            #expect(Self.chips(Self.row(reason: .reRequested, mergeable: state), .review).info == [.reRequested])
            #expect(Self.chips(Self.row(mergeable: state), .team).info == [])
        }
    }

    // MARK: Team

    @Test func teamShowsOnlyApprovals() {
        #expect(Self.chips(Self.row(), .team) == RowChips(action: nil, info: []))
        let chips = Self.chips(Self.row(reviews: [("a", .approved), ("b", .changesRequested)]), .team)
        #expect(chips == RowChips(action: nil, info: [.approvals(1)]))
    }

    @Test func teamShowsTheWait() {
        let row = Self.row(reviews: [("a", .approved)], requests: [(.user("dana"), Self.t0)])
        #expect(Self.chips(row, .team).info == [.approvals(1), Self.wait(row, .team)])
        #expect(Self.chips(row, .team).info[1].text == "@dana 5d")
    }

    @Test func waitSitsBeforeConflicts() {
        let row = Self.row(reviews: [], mergeable: .conflicting)
        #expect(Self.chips(row, .team).info == [Self.wait(row, .team), .conflicts])
    }

    @Test func teamNeverGetsACapsule() {
        #expect(Self.chips(Self.row(reviews: [("a", .approved)]), .team).action == nil)
    }

    // MARK: Review

    @Test func reviewFirstRequestShowsNothing() {
        #expect(Self.chips(Self.row(reason: .requested), .review) == RowChips(action: nil, info: []))
        #expect(Self.chips(Self.row(), .review) == RowChips(action: nil, info: []))
    }

    @Test func reviewReasonsAreInfo() {
        #expect(Self.chips(Self.row(reason: .reRequested), .review).info == [.reRequested])
        #expect(Self.chips(Self.row(reason: .newCommitsSinceReview), .review).info == [.newCommits])
        #expect(Self.chips(Self.row(reason: .teamRequested("web")), .review).info == [.viaTeam("org/web")])
    }

    @Test func reviewReasonComesBeforeTheWait() {
        let row = Self.row(requests: [(.user("me"), Self.t0 + 3 * 86_400)], reason: .reRequested, mergeable: .conflicting)
        #expect(Self.chips(row, .review).info == [.reRequested, Self.wait(row, .review), .conflicts])
        #expect(Self.chips(row, .review).info[1].text == "2d")
    }

    @Test func reviewRowWithoutAReasonGetsTheFullForm() {
        // A dimmed or uncounted Review row isn't waiting on the viewer, so a bare age would mislead.
        let row = Self.row(requests: [(.user("me"), Self.t0 + 3 * 86_400)])
        #expect(Self.chips(row, .review).info.first?.text == "You 2d")
    }

    @Test func reviewTeamWithoutOwnerUsesTheBareSlug() {
        #expect(Self.chips(Self.row(repo: "", reason: .teamRequested("web")), .review).info == [.viaTeam("web")])
    }

    @Test func reviewDimmedIsYouApproved() {
        let chips = Self.chips(Self.row(reviews: [("me", .approved)], dimmed: true), .review)
        #expect(chips == RowChips(action: nil, info: [.youApprovedNotCounted]))
    }

    @Test func reviewNeverGetsACapsule() {
        let chips = Self.chips(Self.row(reviews: [("a", .changesRequested)], reason: .reRequested), .review)
        #expect(chips.action == nil)
    }

    // MARK: Wording

    @Test func infoWording() {
        #expect(RowChips.Info.approvals(1).text == "1")
        #expect(RowChips.Info.approvals(1).label == "1 approval")
        #expect(RowChips.Info.approvals(3).label == "3 approvals")
        let wait = ReviewWait(who: "@dana", age: "3d", label: "Waiting on review: @dana 3 days")
        #expect(RowChips.Info.reviewWait(wait).text == "@dana 3d")
        #expect(RowChips.Info.reviewWait(wait).label == "Waiting on review: @dana 3 days")
        #expect(RowChips.Info.reviewWait(wait).symbol == "clock")
        #expect(RowChips.Info.reviewWait(wait).isReviewWait)
        #expect(!RowChips.Info.conflicts.isReviewWait)
        #expect(RowChips.Info.newCommits.label == "New commits since your review")
        #expect(RowChips.Info.viaTeam("org/web").text == "via @org/web")
        #expect(RowChips.Info.reRequested.label == "Re-requested")
        #expect(RowChips.Info.approvals(2).isCount)
        #expect(!RowChips.Info.reviewWait(wait).isCount)
        #expect(RowChips.Info.conflicts.text == "Conflicts")
        #expect(RowChips.Info.conflicts.label == "Merge conflicts")
        #expect(RowChips.Info.conflicts.symbol == "exclamationmark.triangle")
        #expect(RowChips.Info.conflicts.isWarning)
        #expect(!RowChips.Info.conflicts.isCount)
        #expect(!RowChips.Info.reviewWait(wait).isWarning)
    }
}
