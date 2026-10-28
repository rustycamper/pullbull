import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

private func pr(
    _ n: Int, author: String = "alice", draft: Bool = false, created: Double = 5, updated: Double = 1,
    closed: Double? = nil, reviews: [Review] = [], requests: [Reviewer] = [.user("me")], state: PRState = .open
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "r", number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: draft,
        createdAt: ago(created), updatedAt: ago(updated), closedAt: closed.map(ago),
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests)
}

private func approvedByMe(_ n: Int) -> PullRequest {
    pr(n, reviews: [Review(author: "me", state: .approved, submittedAt: ago(2))], requests: [])
}

private func snap(
    review: [PullRequest] = [], mine: [PullRequest] = [], team: [PullRequest] = [],
    closed: [PullRequest] = []
) -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: review, mine: mine, team: team, recentlyClosed: closed, boardIssues: [])
}

@Suite struct TabBuilderTests {
    @Test func countEqualsCountedRows() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        let built = TabBuilder.build(
            snap(review: [pr(1), approvedByMe(2), pr(1)], mine: [pr(3, author: "me")], team: [pr(4), pr(1)]),
            settings: s, now: now)
        for tab in [built.review, built.mine, built.team] {
            #expect(tab.count == tab.rows.filter(\.counted).count)
        }
        #expect(built.review.rows.count == 2)
        #expect(built.review.count == 1)
    }

    @Test func reviewRowsCarryTheReason() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        let again = pr(3, reviews: [Review(author: "me", state: .commented, submittedAt: ago(2))])
        let built = TabBuilder.build(snap(review: [pr(1), approvedByMe(2), again], team: [pr(1)]), settings: s, now: now)
        let reasons = Dictionary(uniqueKeysWithValues: built.review.rows.map { ($0.id.number, $0.reviewReason) })
        #expect(reasons[1] == .some(.requested))
        #expect(reasons[2] == .some(nil))
        #expect(reasons[3] == .some(.reRequested))
        #expect(built.team.rows.allSatisfy { $0.reviewReason == nil })
    }

    @Test func approvedHiddenByDefault() {
        let built = TabBuilder.build(snap(review: [approvedByMe(1)]), settings: AppSettings(), now: now)
        #expect(built.review.rows.isEmpty)
    }

    @Test func approvedDimmedWhenSettingOff() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        let built = TabBuilder.build(snap(review: [pr(1), approvedByMe(2)]), settings: s, now: now)
        let row = built.review.rows.first { $0.id.number == 2 }
        #expect(row?.dimmed == true)
        #expect(row?.counted == false)
        #expect(built.review.count == 1)
        #expect(built.badgeCount(.review) == built.review.count)
    }

    @Test func dimmedInReviewCountedInTeamBadgeOnce() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        let built = TabBuilder.build(snap(review: [approvedByMe(1)], team: [approvedByMe(1)]), settings: s, now: now)
        #expect(built.review.rows.first?.dimmed == true)
        #expect(built.review.count == 0)
        #expect(built.team.count == 1)
        #expect(built.badgeCount(.all) == 1)
        #expect(built.badgeCount(.review) == 0)
    }

    @Test func singleSourceBadgeEqualsTabCount() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        let built = TabBuilder.build(
            snap(review: [pr(1), approvedByMe(2)], mine: [pr(3, author: "me")], team: [pr(4)]), settings: s, now: now)
        #expect(built.badgeCount(.review) == built.review.count)
        #expect(built.badgeCount(.mine) == built.mine.count)
    }

    @Test func dedupeKeepsNewest() {
        let built = TabBuilder.build(
            snap(team: [pr(1, updated: 5), pr(1, updated: 2)]), settings: AppSettings(), now: now)
        #expect(built.team.rows.count == 1)
        #expect(built.team.rows[0].pr.updatedAt == ago(2))
    }

    @Test func mineIgnoresFilters() {
        var s = AppSettings()
        s.hideDrafts = true
        let built = TabBuilder.build(
            snap(mine: [pr(1, author: "me", draft: true, created: 100, updated: 90)]), settings: s, now: now)
        #expect(built.mine.count == 1)
    }

    @Test func ageUsesUpdatedAt() {
        let built = TabBuilder.build(
            snap(team: [pr(1, created: 100, updated: 1), pr(2, created: 100, updated: 61)]),
            settings: AppSettings(), now: now)
        #expect(built.team.rows.map(\.id.number) == [1])
    }

    @Test func draftsFilteredOnReviewAndTeam() {
        var s = AppSettings()
        s.hideDrafts = true
        let built = TabBuilder.build(
            snap(review: [pr(1, draft: true)], team: [pr(2, draft: true), pr(3)]), settings: s, now: now)
        #expect(built.review.rows.isEmpty)
        #expect(built.team.rows.map(\.id.number) == [3])
    }

    @Test func teamExcludesMyOwnCaseInsensitive() {
        let built = TabBuilder.build(snap(team: [pr(1, author: "ME"), pr(2)]), settings: AppSettings(), now: now)
        #expect(built.team.rows.map(\.id.number) == [2])
    }

    @Test func sortedByUpdatedDescending() {
        let built = TabBuilder.build(
            snap(team: [pr(1, updated: 5), pr(2, updated: 1), pr(3, updated: 3)]), settings: AppSettings(), now: now)
        #expect(built.team.rows.map(\.id.number) == [2, 3, 1])
    }

    @Test func badgeDistinct() {
        let built = TabBuilder.build(
            snap(review: [pr(1)], mine: [pr(2, author: "me")], team: [pr(1), pr(3)]),
            settings: AppSettings(), now: now)
        #expect(built.badgeCount(.all) == 3)
        #expect(built.badgeCount(.review) == 1)
        #expect(built.badgeCount(.mine) == 1)
        #expect(built.badgeCount(.reviewAndMine) == 2)
    }

    @Test func recentlyClosedWindow() {
        let built = TabBuilder.build(
            snap(mine: [pr(3, author: "me")], closed: [pr(1, closed: 8), pr(2, closed: 6), pr(3, closed: 1)]),
            settings: AppSettings(), now: now)
        #expect(built.recentlyClosed.map(\.key.number) == [3, 2])
        #expect(built.mine.count == 1)
        #expect(built.badgeCount(.all) == 1)
        #expect(built.review.count == 0)
        #expect(built.team.count == 0)
    }

    @Test func mergedNodeFromOpenSearchIsDropped() {
        // The is:open search index can lag a merge; the node's own state is live.
        let built = TabBuilder.build(
            snap(
                review: [pr(1, state: .merged), pr(2)],
                mine: [pr(3, author: "me", state: .closed), pr(4, author: "me")],
                team: [pr(5, state: .merged), pr(6)]),
            settings: AppSettings(), now: now)
        #expect(built.review.rows.map(\.id.number) == [2])
        #expect(built.mine.rows.map(\.id.number) == [4])
        #expect(built.team.rows.map(\.id.number) == [6])
        #expect(built.badgeCount(.all) == 3)
    }

    @Test func hiddenApprovalsCountedInSamePass() {
        let snapshot = snap(review: [pr(1), approvedByMe(2), approvedByMe(3)])
        #expect(TabBuilder.build(snapshot, settings: AppSettings(), now: now).hiddenApprovedCount == 2)
        var shown = AppSettings()
        shown.hideApprovedByMe = false
        #expect(TabBuilder.build(snapshot, settings: shown, now: now).hiddenApprovedCount == 0)
        var noDrafts = AppSettings()
        noDrafts.hideDrafts = true
        let draftApproved = pr(4, draft: true, reviews: [Review(author: "me", state: .approved, submittedAt: ago(2))],
                               requests: [])
        #expect(TabBuilder.build(snap(review: [draftApproved]), settings: noDrafts, now: now).hiddenApprovedCount == 0)
    }
}
