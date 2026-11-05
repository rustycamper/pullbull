import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

private func pr(
    _ n: Int, author: String = "alice", draft: Bool = false, created: Double = 5, updated: Double = 1,
    closed: Double? = nil, reviews: [Review] = [], requests: [Reviewer] = [.user("me")], state: PRState = .open,
    waits: [Double?] = [], ready: Double? = nil
) -> PullRequest {
    // `waits[i]`: days since `requests[i]` was made; nil or missing is an unknown time.
    var times: [String: Date] = [:]
    for (reviewer, days) in zip(requests, waits) { times[reviewer.key] = days.map(ago) }
    return PullRequest(
        key: PRKey(repo: "r", number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: draft,
        createdAt: ago(created), updatedAt: ago(updated), closedAt: closed.map(ago),
        headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: reviews, reviewRequests: requests,
        reviewRequestTimes: times, readyForReviewAt: ready.map(ago))
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

    @Test func oldestFirstOnEveryPRTab() {
        var s = AppSettings()
        for tab in PRTab.allCases { s.setSort(.oldestFirst, for: tab) }
        let prs = [
            pr(1, created: 2, updated: 1), pr(2, created: 9, updated: 5), pr(3, created: 9, updated: 3),
            pr(4, created: 4, updated: 2),
        ]
        let built = TabBuilder.build(snap(review: prs, mine: prs.map { pr($0.key.number, author: "me", created: Double($0.key.number)) }, team: prs), settings: s, now: now)
        #expect(built.review.rows.map(\.id.number) == [2, 3, 4, 1])
        #expect(built.mine.rows.map(\.id.number) == [4, 3, 2, 1])
        #expect(built.team.rows.map(\.id.number) == [2, 3, 4, 1])
    }

    @Test func waitingLongestOrdersByWaitStart() {
        var s = AppSettings()
        s.setSort(.waitingLongest, for: PRTab.team)
        let dana = Reviewer.user("dana")
        let team = [
            pr(1, updated: 2, requests: [dana], waits: [1]), pr(2, updated: 9, requests: [dana], waits: [6]),
            pr(3, updated: 3, requests: [dana], waits: [3]), pr(4, draft: true, updated: 0.1, requests: [dana], waits: [8]),
        ]
        let built = TabBuilder.build(snap(team: team), settings: s, now: now)
        #expect(built.team.rows.map(\.id.number) == [2, 3, 1, 4])
    }

    /// A wait whose start isn't known for every reviewer shows no age, so it never sorts ahead of a known one.
    @Test func waitingLongestPutsUnknownStartLast() {
        var s = AppSettings()
        s.setSort(.waitingLongest, for: PRTab.team)
        let dana = Reviewer.user("dana"), lee = Reviewer.user("lee")
        let team = [
            pr(1, updated: 1.0 / 24, requests: [dana, lee], waits: [10, nil]),
            pr(2, updated: 9, requests: [dana], waits: [2]),
            pr(3, updated: 5, reviews: [Review(author: "bob", state: .approved, submittedAt: ago(6))], requests: []),
        ]
        let built = TabBuilder.build(snap(team: team), settings: s, now: now)
        #expect(built.team.rows.map(\.id.number) == [2, 1, 3])
    }

    /// On Review the short form (my own request) orders a row waiting on me; a dimmed row uses the full form.
    @Test func waitingLongestUsesTheFormTheRowShows() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        s.setSort(.waitingLongest, for: PRTab.review)
        let lee = Reviewer.user("lee"), dana = Reviewer.user("dana")
        let review = [
            pr(1, updated: 1.0 / 24, requests: [.user("me"), lee], waits: [1, 9]),
            pr(2, updated: 8, reviews: [Review(author: "me", state: .approved, submittedAt: ago(5))],
               requests: [dana], waits: [4]),
        ]
        let built = TabBuilder.build(snap(review: review), settings: s, now: now)
        #expect(built.review.rows.map(\.id.number) == [2, 1])
    }

    /// Waits that started at the same moment break the tie by repo and number, as every sort does.
    @Test func equalWaitsBreakTiesByNumber() {
        var s = AppSettings()
        s.setSort(.waitingLongest, for: PRTab.team)
        let dana = Reviewer.user("dana")
        let team = [
            pr(2, updated: 0.5, requests: [dana], waits: [3]), pr(1, updated: 2, requests: [dana], waits: [3]),
        ]
        let built = TabBuilder.build(snap(team: team), settings: s, now: now)
        #expect(built.team.rows.map(\.id.number) == [1, 2])
    }

    @Test func recentlyClosedIgnoresTheSort() {
        var s = AppSettings()
        s.setSort(.oldestFirst, for: PRTab.mine)
        let closed = [
            pr(5, author: "me", created: 9, closed: 3, state: .merged),
            pr(6, author: "me", created: 1, closed: 1, state: .merged),
        ]
        let built = TabBuilder.build(snap(closed: closed), settings: s, now: now)
        #expect(built.recentlyClosed.map(\.key.number) == [6, 5])
    }

    @Test func reviewKeepsRecentActivityFirstByDefault() {
        let prs = [pr(1, created: 2, updated: 1), pr(2, created: 9, updated: 5)]
        let built = TabBuilder.build(snap(review: prs), settings: AppSettings(), now: now)
        #expect(built.review.rows.map(\.id.number) == [1, 2])
    }
}

/// A direct merge on its way: the overlay marks the PR merged before GitHub answers, and the row must not
/// leave at the send.
@Suite struct MergingRowTests {
    private let key = PRKey(repo: "r", number: 1)

    private func merging(_ snapshot: Snapshot) -> (shown: Snapshot, overrides: EditOverrides, id: UUID) {
        var overrides = EditOverrides()
        let id = overrides.record(.merged(viewer: "me"), on: key, at: now)
        return (overrides.apply(to: snapshot), overrides, id)
    }

    private func build(_ shown: Snapshot, _ overrides: EditOverrides, settings: AppSettings = AppSettings()) -> BuiltTabs {
        TabBuilder.build(shown, settings: settings, now: now, merging: overrides.directMerges)
    }

    @Test func staysInMineDimmed() {
        let (shown, overrides, _) = merging(snap(mine: [pr(1, author: "me"), pr(2, author: "me")]))
        let rows = build(shown, overrides).mine.rows
        #expect(rows.map(\.id.number) == [1, 2])
        #expect(rows.map(\.dimmed) == [true, false])
    }

    @Test func staysInTeamDimmed() {
        let (shown, overrides, _) = merging(snap(team: [pr(1), pr(2)]))
        let rows = build(shown, overrides).team.rows
        #expect(rows.map(\.id.number) == [1, 2])
        #expect(rows.map(\.dimmed) == [true, false])
    }

    @Test func isNoLongerCounted() {
        let (shown, overrides, _) = merging(snap(mine: [pr(1, author: "me"), pr(2, author: "me")], team: [pr(1), pr(2)]))
        let built = build(shown, overrides)
        #expect(built.mine.count == 1)
        #expect(built.team.count == 1)
    }

    @Test func staysInItsSection() {
        // Ready to merge puts it in Your PRs, and a PR reading merged isn't ready.
        let ready = pr(1, author: "me", reviews: [Review(author: "bob", state: .approved, submittedAt: ago(1))])
        let (shown, overrides, _) = merging(snap(mine: [ready]))
        let built = build(shown, overrides)
        #expect(built.yourPRs.rows.map(\.id.number) == [1])
        #expect(built.waitingOnOthers.rows.isEmpty)
    }

    @Test func keepsItsPlaceInAWaitSort() {
        var settings = AppSettings()
        settings.setSort(.waitingLongest, for: PRTab.team)
        let (shown, overrides, _) = merging(snap(team: [pr(1, waits: [9]), pr(2, waits: [3])]))
        #expect(build(shown, overrides, settings: settings).team.rows.map(\.id.number) == [1, 2])
    }

    @Test func teamFiltersStillApply() {
        var settings = AppSettings()
        settings.hideOlderThanTwoMonths = true
        let (shown, overrides, _) = merging(snap(team: [pr(1, updated: 90)]))
        #expect(build(shown, overrides, settings: settings).team.rows.isEmpty)
    }

    @Test func aRefusalPutsItBackUndimmed() {
        var (_, overrides, id) = merging(snap())
        overrides.drop(id)
        let fetched = snap(mine: [pr(1, author: "me")], team: [pr(1)])
        let built = build(overrides.apply(to: fetched), overrides)
        #expect(built.mine.rows.map(\.dimmed) == [false])
        #expect(built.mine.count == 1)
        #expect(built.team.rows.map(\.dimmed) == [false])
        #expect(built.team.count == 1)
    }

    @Test func movesOnceTheOverlaySettles() {
        var (_, overrides, _) = merging(snap())
        let fetched = snap(
            mine: [pr(1, author: "me", state: .merged)], team: [pr(1, state: .merged)],
            closed: [pr(1, author: "me", closed: 0, state: .merged)])
        overrides.reconcile(with: fetched, now: now.addingTimeInterval(30))
        let built = build(overrides.apply(to: fetched), overrides)
        #expect(built.mine.rows.isEmpty)
        #expect(built.team.rows.isEmpty)
        #expect(built.recentlyClosed.map(\.key.number) == [1])
    }

    @Test func staysWhileTheDetailHoldsTheOverlay() {
        var (_, overrides, _) = merging(snap())
        let fetched = snap(mine: [pr(1, author: "me", state: .merged)])
        overrides.reconcile(with: fetched, now: now.addingTimeInterval(30), holdingMerges: [key])
        #expect(build(overrides.apply(to: fetched), overrides).mine.rows.map(\.dimmed) == [true])
    }

    @Test func aMergeGitHubReportsWithNoOverlayLeavesAsBefore() {
        let fetched = snap(mine: [pr(1, author: "me", state: .merged)], team: [pr(1, state: .merged)])
        let built = TabBuilder.build(fetched, settings: AppSettings(), now: now)
        #expect(built.mine.rows.isEmpty)
        #expect(built.team.rows.isEmpty)
    }

    @Test func staysInReviewDimmedAndUncounted() {
        let (shown, overrides, _) = merging(snap(review: [pr(1), pr(2)]))
        let built = build(shown, overrides)
        #expect(built.review.rows.map(\.id.number) == [1, 2])
        #expect(built.review.rows.map(\.dimmed) == [true, false])
        #expect(built.review.count == 1)
        #expect(built.review.rows.first?.pr.state == .open)
        #expect(built.review.rows.first?.reviewReason == .requested)
    }

    @Test func isNotListedInTeamToo() {
        let (shown, overrides, _) = merging(snap(review: [pr(1)], team: [pr(1), pr(2)]))
        #expect(build(shown, overrides).teamSection.rows.map(\.id.number) == [2])
    }

    @Test func keepsItsPlaceInReviewsWaitSort() {
        // With its reason #1 shows the viewer's own 1d wait; without one it would show the oldest request's 9d.
        var settings = AppSettings()
        settings.setSort(.waitingLongest, for: PRTab.review)
        let requests: [Reviewer] = [.user("zed"), .user("me")]
        let prs = [pr(1, requests: requests, waits: [9, 1]), pr(2, waits: [3])]
        let (shown, overrides, _) = merging(snap(review: prs))
        #expect(build(shown, overrides, settings: settings).review.rows.map(\.id.number) == [2, 1])
    }

    @Test func aHiddenApprovedRowStaysHidden() {
        var settings = AppSettings()
        settings.hideApprovedByMe = true
        let (shown, overrides, _) = merging(snap(review: [approvedByMe(1)]))
        let built = build(shown, overrides, settings: settings)
        #expect(built.review.rows.isEmpty)
        #expect(built.hiddenApprovedCount == 1)
    }

    @Test func isNotListedInRecentlyClosedToo() {
        // Search lags: Mine still returns the PR while Recently closed already has it.
        let closed = pr(1, author: "me", closed: 0, state: .merged)
        let (shown, overrides, _) = merging(snap(mine: [pr(1, author: "me")], closed: [closed]))
        let built = build(shown, overrides)
        #expect(built.mine.rows.map(\.id.number) == [1])
        #expect(built.recentlyClosed.isEmpty)
    }

    @Test func staysInRecentlyClosedOnceNoOtherListHasIt() {
        // The lists caught up while the detail still holds the overlay: this is the only place it's listed.
        let closed = pr(1, author: "me", closed: 0, state: .merged)
        let (shown, overrides, _) = merging(snap(closed: [closed]))
        #expect(build(shown, overrides).recentlyClosed.map(\.key.number) == [1])
    }

    @Test func anAutoMergeKeepsTheRowUndimmed() {
        var overrides = EditOverrides()
        overrides.record(.autoMerge(enabled: true, viewer: "me"), on: key, at: now)
        let built = build(overrides.apply(to: snap(mine: [pr(1, author: "me")])), overrides)
        #expect(built.mine.rows.map(\.dimmed) == [false])
        #expect(built.mine.count == 1)
    }
}
