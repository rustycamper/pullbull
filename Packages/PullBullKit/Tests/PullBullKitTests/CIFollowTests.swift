import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func pr(
    _ n: Int, ci: CIState = .pending, state: PRState = .open, isDraft: Bool = false, author: String = "me",
    oid: String? = "a", pushed: Date? = t0, title: String = "t"
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "o/r", number: n), title: title, url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: isDraft,
        createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main", ci: ci,
        headCommitDate: pushed, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [],
        headCommitOid: oid)
}

private func snap(
    mine: [PullRequest], review: [PullRequest] = [], team: [PullRequest] = [], closed: [PullRequest] = []
) -> Snapshot {
    Snapshot(
        fetchedAt: t0, org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: review, mine: mine, team: team, recentlyClosed: closed, boardIssues: [])
}

private func key(_ n: Int) -> PRKey { PRKey(repo: "o/r", number: n) }

@Suite struct CIFollowTests {
    @Test func selectsPendingMine() {
        let s = snap(mine: [
            pr(1), pr(2, ci: .success), pr(3, ci: .failure), pr(4, isDraft: true),
            pr(5, state: .closed), pr(6, state: .merged), pr(7, ci: .none),
        ])
        var follow = CIFollow()
        follow.observe(s, now: t0)
        #expect(Set(follow.selection(in: s, now: t0)) == [key(1), key(4)])
        // Pending PRs outside Mine are not followed.
        let others = snap(mine: [], review: [pr(8, author: "bob")], team: [pr(9, author: "bob")])
        follow.observe(others, now: t0)
        #expect(follow.selection(in: others, now: t0).isEmpty)
    }

    @Test func capsAtFiveNewestFirst() {
        let prs = [
            pr(1, pushed: t0.addingTimeInterval(10)), pr(2, pushed: nil), pr(3, pushed: t0.addingTimeInterval(30)),
            pr(4, pushed: t0.addingTimeInterval(20)), pr(5, pushed: t0.addingTimeInterval(50)),
            pr(6, pushed: t0.addingTimeInterval(40)), pr(7, pushed: t0),
        ]
        var follow = CIFollow()
        let s = snap(mine: prs)
        follow.observe(s, now: t0)
        #expect(CIFollow.cap == 5)
        #expect(follow.selection(in: s, now: t0) == [key(5), key(6), key(3), key(4), key(1)])
        // Nil dates come last.
        let few = snap(mine: [pr(2, pushed: nil), pr(7, pushed: t0)])
        follow.observe(few, now: t0)
        #expect(follow.selection(in: few, now: t0) == [key(7), key(2)])
    }

    @Test func twentyMinuteCutoff() {
        var follow = CIFollow()
        let first = snap(mine: [pr(1, oid: "a")])
        follow.observe(first, now: t0)
        // Seen again later: the clock keeps the first time.
        follow.observe(first, now: t0.addingTimeInterval(600))
        #expect(follow.selection(in: first, now: t0.addingTimeInterval(1199)) == [key(1)])
        #expect(follow.selection(in: first, now: t0.addingTimeInterval(1200)).isEmpty)
        let pushed = snap(mine: [pr(1, oid: "b")])
        follow.observe(pushed, now: t0.addingTimeInterval(1300))
        #expect(follow.selection(in: pushed, now: t0.addingTimeInterval(1300)) == [key(1)])
        #expect(follow.selection(in: pushed, now: t0.addingTimeInterval(2499)) == [key(1)])
        #expect(follow.selection(in: pushed, now: t0.addingTimeInterval(2500)).isEmpty)
    }

    @Test func headCommitDateStandsInForAMissingOid() {
        var follow = CIFollow()
        follow.observe(snap(mine: [pr(1, oid: nil, pushed: t0)]), now: t0)
        let pushed = snap(mine: [pr(1, oid: nil, pushed: t0.addingTimeInterval(60))])
        follow.observe(pushed, now: t0.addingTimeInterval(1300))
        #expect(follow.selection(in: pushed, now: t0.addingTimeInterval(1300)) == [key(1)])
    }

    @Test func noLongerPendingRestartsTheClock() {
        var follow = CIFollow()
        let pending = snap(mine: [pr(1)])
        follow.observe(pending, now: t0)
        follow.observe(snap(mine: [pr(1, ci: .failure)]), now: t0.addingTimeInterval(60))
        // A re-run of the same head is pending again: its 20 minutes start over.
        follow.observe(pending, now: t0.addingTimeInterval(1300))
        #expect(follow.selection(in: pending, now: t0.addingTimeInterval(1300)) == [key(1)])
    }

    @Test func shouldRun() {
        let later = t0.addingTimeInterval(120)
        #expect(CIFollow.interval == .seconds(30))
        #expect(CIFollow.maxPending == 1200)
        #expect(!CIFollow.shouldRun(now: t0, nextFullAt: later, fullInFlight: true, error: nil))
        #expect(!CIFollow.shouldRun(now: t0, nextFullAt: t0.addingTimeInterval(30), fullInFlight: false, error: nil))
        #expect(!CIFollow.shouldRun(now: t0, nextFullAt: t0.addingTimeInterval(10), fullInFlight: false, error: nil))
        #expect(!CIFollow.shouldRun(now: t0, nextFullAt: later, fullInFlight: false, error: .offline))
        #expect(!CIFollow.shouldRun(now: t0, nextFullAt: later, fullInFlight: false, error: .rateLimited(nil)))
        #expect(!CIFollow.shouldRun(now: t0, nextFullAt: later, fullInFlight: false, error: .rateLimited(later)))
        #expect(CIFollow.shouldRun(now: t0, nextFullAt: t0.addingTimeInterval(31), fullInFlight: false, error: nil))
        #expect(CIFollow.shouldRun(now: t0, nextFullAt: later, fullInFlight: false, error: nil))
        #expect(CIFollow.shouldRun(now: t0, nextFullAt: nil, fullInFlight: false, error: nil))
    }

    @Test func mergingReplacesEverywhere() {
        let s = snap(
            mine: [pr(1), pr(2)], review: [pr(1), pr(3, author: "bob")], team: [pr(1), pr(4, author: "bob")],
            closed: [pr(1, state: .merged)])
        let followed = pr(1, ci: .failure, title: "new")
        let merged = s.merging(followed: [followed, pr(99, ci: .success)])
        #expect(merged.mine == [followed, pr(2)])
        #expect(merged.reviewCandidates == [followed, pr(3, author: "bob")])
        #expect(merged.team == [followed, pr(4, author: "bob")])
        #expect(merged.recentlyClosed == s.recentlyClosed)
        #expect(merged.fetchedAt == s.fetchedAt)
        #expect(s.merging(followed: []) == s)
    }

    @Test func mergingKeepsTheOldRowOfAClosedPR() {
        let s = snap(mine: [pr(1), pr(2)], review: [pr(2, author: "bob")])
        let merged = s.merging(followed: [pr(1, ci: .success, state: .merged), pr(2, ci: .success, state: .closed)])
        #expect(merged == s)
        let mixed = s.merging(followed: [pr(1, ci: .success, state: .merged), pr(2, ci: .failure)])
        #expect(mixed.mine == [pr(1), pr(2, ci: .failure)])
    }
}
