import Foundation
import Testing
@testable import PullBullKit

private let launch = Date(timeIntervalSince1970: 1_800_000_000)

private func pr(_ n: Int, comments: Int, author: String) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "initech/api", number: n), title: "Fix the thing", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: launch, updatedAt: launch, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: nil, commentCount: comments, lastCommentAuthor: "bob",
        latestReviews: [], reviewRequests: [])
}

private func snap(_ offset: TimeInterval, comments: Int, viewer: String = "me", org: String = "o") -> Snapshot {
    Snapshot(
        fetchedAt: launch.addingTimeInterval(offset),
        org: OrgContext(org: org, viewer: viewer, members: [], myTeams: [], repos: []),
        reviewCandidates: [], mine: [pr(1, comments: comments, author: viewer)], team: [],
        recentlyClosed: [], boardIssues: [])
}

private let idle = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false)
private let busy = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: true)
private let failed = RefreshStatus(lastSuccess: nil, error: .offline, isRefreshing: false)

/// Feeds the gate the sequence a `RefreshCoordinator` emits and returns the kinds it would post.
private struct Feed {
    var gate = NotificationGate(launchedAt: launch)
    var toggles = NotificationToggles()

    /// The cached snapshot a coordinator emits when its loop starts.
    mutating func cache(_ s: Snapshot?) -> [PREventKind] {
        gate.events(snapshot: s, status: idle, toggles: toggles).map(\.kind)
    }

    /// The refresh marker (carrying the snapshot held before the attempt), then the attempt's result.
    mutating func fetch(from before: Snapshot?, to after: Snapshot?, status: RefreshStatus = idle) -> [PREventKind] {
        let marker = gate.events(snapshot: before, status: busy, toggles: toggles)
        #expect(marker.isEmpty)
        return gate.events(snapshot: after, status: status, toggles: toggles).map(\.kind)
    }
}

@Suite struct NotificationGateTests {
    @Test func cacheThenFirstLiveFetchIsBaseline() {
        var feed = Feed()
        let cached = snap(-3600, comments: 0)
        #expect(feed.cache(cached).isEmpty)
        // A comment arrived while the app was not running: the first live fetch is the baseline.
        let live = snap(10, comments: 1)
        #expect(feed.fetch(from: cached, to: live).isEmpty)
        #expect(feed.fetch(from: live, to: snap(130, comments: 2)) == [.newComment])
    }

    @Test func noCacheFirstFetchIsBaseline() {
        var feed = Feed()
        #expect(feed.cache(nil).isEmpty)
        let live = snap(10, comments: 1)
        #expect(feed.fetch(from: nil, to: live).isEmpty)
        #expect(feed.fetch(from: live, to: snap(130, comments: 2)) == [.newComment])
    }

    @Test func failedAttemptPostsNothingAndKeepsBaseline() {
        var feed = Feed()
        let live = snap(10, comments: 0)
        _ = feed.fetch(from: nil, to: live)
        #expect(feed.fetch(from: live, to: live, status: failed).isEmpty)
        #expect(feed.fetch(from: live, to: snap(250, comments: 1)) == [.newComment])
    }

    @Test func reEmittedSnapshotPostsNothing() {
        var feed = Feed()
        let a = snap(10, comments: 0)
        let b = snap(130, comments: 1)
        _ = feed.fetch(from: nil, to: a)
        #expect(feed.fetch(from: a, to: b) == [.newComment])
        // A coordinator restarted for the same account (e.g. new interval) re-emits its saved snapshot.
        #expect(feed.cache(b).isEmpty)
        #expect(feed.fetch(from: b, to: b).isEmpty)
        #expect(feed.fetch(from: b, to: snap(250, comments: 2)) == [.newComment])
    }

    @Test func accountSwitchPostsNothing() {
        var feed = Feed()
        _ = feed.fetch(from: nil, to: snap(10, comments: 0))
        let otherCache = snap(-100, comments: 0, viewer: "other")
        #expect(feed.cache(otherCache).isEmpty)
        let other = snap(200, comments: 5, viewer: "other")
        #expect(feed.fetch(from: otherCache, to: other).isEmpty)
        #expect(feed.fetch(from: other, to: snap(320, comments: 6, viewer: "other")) == [.newComment])
    }

    @Test func switchingBackDoesNotDiffAgainstEarlierFetch() {
        var feed = Feed()
        let a = snap(10, comments: 0)
        _ = feed.fetch(from: nil, to: a)
        _ = feed.fetch(from: nil, to: snap(200, comments: 0, viewer: "other"))
        // Back to the first account: its cache is from this session; what changed meanwhile is not posted.
        #expect(feed.cache(a).isEmpty)
        #expect(feed.fetch(from: a, to: snap(400, comments: 3)).isEmpty)
    }

    @Test func orgSwitchPostsNothing() {
        var feed = Feed()
        _ = feed.fetch(from: nil, to: snap(10, comments: 0))
        #expect(feed.fetch(from: nil, to: snap(130, comments: 4, org: "p")).isEmpty)
    }

    /// Leaving no-org mode for an org of the login's name (or back) is a scope switch, not new events.
    @Test func personalToOrgSwitchPostsNothing() {
        var feed = Feed()
        var personal = snap(10, comments: 0)
        personal.org = .personal(login: "me", repos: [], reposComplete: true)
        _ = feed.fetch(from: nil, to: personal)
        #expect(feed.fetch(from: nil, to: snap(130, comments: 4, org: "me")).isEmpty)
    }

    @Test func viewerComparedCaseInsensitively() {
        var feed = Feed()
        let a = snap(10, comments: 0, viewer: "Me")
        _ = feed.fetch(from: nil, to: a)
        #expect(feed.fetch(from: a, to: snap(130, comments: 1, viewer: "me")) == [.newComment])
    }

    @Test func leftoverMarkerThenOldCacheIsNotLive() {
        var feed = Feed()
        // The marker of a fetch that was cancelled by a restart, then the restarted loop's cache
        // from a previous launch: neither counts as a live fetch.
        _ = feed.gate.events(snapshot: nil, status: busy, toggles: feed.toggles)
        #expect(feed.cache(snap(-50, comments: 0)).isEmpty)
        let live = snap(10, comments: 2)
        #expect(feed.fetch(from: nil, to: live).isEmpty)
        #expect(feed.fetch(from: live, to: snap(130, comments: 3)) == [.newComment])
    }

    @Test func resetDropsLeftoverNilMarkerAndBaseline() {
        var feed = Feed()
        _ = feed.fetch(from: nil, to: snap(10, comments: 0))
        // Another account's fetch began without a snapshot and was cancelled by switching back.
        _ = feed.gate.events(snapshot: nil, status: busy, toggles: feed.toggles)
        feed.gate.reset()
        // The restarted loop's cache was saved this session: it is neither live nor a diff base.
        let cached = snap(130, comments: 1)
        #expect(feed.cache(cached).isEmpty)
        #expect(feed.fetch(from: cached, to: snap(250, comments: 2)).isEmpty)
        #expect(feed.fetch(from: snap(250, comments: 2), to: snap(370, comments: 3)) == [.newComment])
    }

    @Test func togglesApply() {
        var feed = Feed()
        let a = snap(10, comments: 0)
        _ = feed.fetch(from: nil, to: a)
        feed.toggles.newComment = false
        #expect(feed.fetch(from: a, to: snap(130, comments: 1)).isEmpty)
    }

    @Test func gatePassesReviewFilters() {
        var gate = NotificationGate(launchedAt: launch)
        func review(_ offset: TimeInterval, draft: Bool) -> Snapshot {
            let candidate = PullRequest(
                key: PRKey(repo: "initech/api", number: 7), title: "Draft", url: URL(string: "https://x/7")!,
                author: "alice", authorAvatarURL: nil, state: .open, isDraft: draft,
                createdAt: launch, updatedAt: launch, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
                headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
                latestReviews: [], reviewRequests: [.user("me")])
            return Snapshot(
                fetchedAt: launch.addingTimeInterval(offset),
                org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
                reviewCandidates: draft ? [candidate] : [], mine: [], team: [], recentlyClosed: [], boardIssues: [])
        }
        var settings = AppSettings()
        settings.hideDrafts = true
        let filters = ReviewFilters(settings)
        let base = review(1, draft: false)
        _ = gate.events(snapshot: nil, status: busy, toggles: .init(), filters: filters, now: launch)
        _ = gate.events(snapshot: base, status: idle, toggles: .init(), filters: filters, now: launch)
        _ = gate.events(snapshot: base, status: busy, toggles: .init(), filters: filters, now: launch)
        let posted = gate.events(snapshot: review(2, draft: true), status: idle, toggles: .init(), filters: filters, now: launch)
        #expect(posted.isEmpty)
    }
}

extension NotificationGateTests {
    private func issueSnap(_ offset: TimeInterval, assigned: [BoardIssue]) -> Snapshot {
        Snapshot(
            fetchedAt: launch.addingTimeInterval(offset),
            org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
            assignedIssues: assigned)
    }

    @Test func gateReturnsIssueEventsAfterBaseline() {
        var gate = NotificationGate(launchedAt: launch)
        var toggles = NotificationToggles()
        toggles.issueAssigned = true
        let assigned = BoardIssue(
            key: PRKey(repo: "initech/gadgets", number: 231), title: "Webhook retries",
            url: URL(string: "https://x/231")!, isOpen: true,
            myAssignment: Assignment(actor: "dev-b", at: launch.addingTimeInterval(60)))
        let cached = issueSnap(-3600, assigned: [])
        #expect(gate.changes(snapshot: cached, status: idle, toggles: toggles).isEmpty)
        #expect(gate.changes(snapshot: cached, status: busy, toggles: toggles).isEmpty)
        let a = issueSnap(10, assigned: [])
        #expect(gate.changes(snapshot: a, status: idle, toggles: toggles).isEmpty)
        #expect(gate.changes(snapshot: a, status: busy, toggles: toggles).isEmpty)
        let changes = gate.changes(snapshot: issueSnap(130, assigned: [assigned]), status: idle, toggles: toggles)
        #expect(changes.issues.count == 1)
        #expect(changes.prs.isEmpty)
        #expect(!changes.isEmpty)
    }
}

extension NotificationGateTests {
    private func mergeSnap(_ offset: TimeInterval, mergedAt: TimeInterval?) -> Snapshot {
        let open = pr(9, comments: 0, author: "me")
        let merged = PullRequest(
            key: open.key, title: open.title, url: open.url, author: "me", authorAvatarURL: nil,
            state: .merged, isDraft: false, createdAt: launch, updatedAt: launch,
            closedAt: mergedAt.map { launch.addingTimeInterval($0) }, headRef: "h", baseRef: "main", ci: .none,
            headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil, latestReviews: [], reviewRequests: [],
            mergedBy: "anna")
        return Snapshot(
            fetchedAt: launch.addingTimeInterval(offset),
            org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: mergedAt == nil ? [open] : [], team: [],
            recentlyClosed: mergedAt == nil ? [] : [merged], boardIssues: [])
    }

    @Test func mergeWhileNotRunningIsBaseline() {
        var feed = Feed()
        let cached = mergeSnap(-3600, mergedAt: nil)
        #expect(feed.cache(cached).isEmpty)
        let live = mergeSnap(10, mergedAt: -60)
        #expect(feed.fetch(from: cached, to: live).isEmpty)
        #expect(feed.fetch(from: live, to: mergeSnap(130, mergedAt: -60)).isEmpty)
    }

    @Test func mergeAcrossAFailedPollNotifiesOnceOnTheNextSuccess() {
        var feed = Feed()
        let open = mergeSnap(10, mergedAt: nil)
        _ = feed.fetch(from: nil, to: open)
        #expect(feed.fetch(from: open, to: open, status: failed).isEmpty)
        let merged = mergeSnap(250, mergedAt: 200)
        #expect(feed.fetch(from: open, to: merged) == [.merged])
        #expect(feed.fetch(from: merged, to: mergeSnap(370, mergedAt: 200)).isEmpty)
    }
}

// MARK: - Fast CI follow

private func ciSnap(_ offset: TimeInterval, ci: CIState) -> Snapshot {
    var s = snap(offset, comments: 0)
    let p = s.mine[0]
    s.mine = [PullRequest(
        key: p.key, title: p.title, url: p.url, author: p.author, authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: p.createdAt, updatedAt: p.updatedAt, closedAt: nil, headRef: "h", baseRef: "main", ci: ci,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
        latestReviews: [Review(author: "bob", state: .approved, submittedAt: launch)], reviewRequests: [],
        mergeable: .mergeable)]
    return s
}

private let followed = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false, isCIFollow: true)

extension NotificationGateTests {
    /// A follow merged into the baseline posts its changes, and the next full refresh, which sees the
    /// same state, posts them again never.
    @Test func followPostsOnceAcrossTheNextFullRefresh() {
        var feed = Feed()
        feed.toggles.readyToMerge = true
        let base = ciSnap(10, ci: .pending)
        #expect(feed.fetch(from: nil, to: base).isEmpty)
        let follow = base.merging(followed: ciSnap(10, ci: .failure).mine)
        #expect(feed.gate.events(snapshot: follow, status: followed, toggles: feed.toggles).map(\.kind) == [.ciFailed])
        #expect(feed.fetch(from: follow, to: ciSnap(130, ci: .failure)).isEmpty)
        // Ready to merge the same way.
        let pending = ciSnap(250, ci: .pending)
        #expect(feed.fetch(from: ciSnap(130, ci: .failure), to: pending).isEmpty)
        let green = pending.merging(followed: ciSnap(250, ci: .success).mine)
        #expect(feed.gate.events(snapshot: green, status: followed, toggles: feed.toggles).map(\.kind) == [.readyToMerge])
        #expect(feed.fetch(from: green, to: ciSnap(370, ci: .success)).isEmpty)
    }

    /// A follow update is diffed only on top of the full refresh it was merged into.
    @Test func followNeedsItsBaseline() {
        var feed = Feed()
        // No baseline yet.
        #expect(feed.gate.events(snapshot: ciSnap(10, ci: .failure), status: followed, toggles: feed.toggles).isEmpty)
        #expect(feed.fetch(from: nil, to: ciSnap(20, ci: .pending)).isEmpty)
        // Merged into another snapshot than the baseline: ignored, and the baseline stays.
        #expect(feed.gate.events(snapshot: ciSnap(15, ci: .failure), status: followed, toggles: feed.toggles).isEmpty)
        #expect(feed.fetch(from: ciSnap(20, ci: .pending), to: ciSnap(140, ci: .failure)) == [.ciFailed])
        // A follow that carries an error never counts.
        var failed = followed
        failed.error = .offline
        #expect(feed.gate.events(snapshot: ciSnap(140, ci: .pending), status: failed, toggles: feed.toggles).isEmpty)
    }
}
