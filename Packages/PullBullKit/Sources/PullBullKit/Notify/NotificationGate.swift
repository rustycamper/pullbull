import Foundation

/// What one live fetch changed, per kind of item.
public struct NotificationChanges: Equatable, Sendable {
    public var prs: [PREvent]
    public var issues: [IssueEvent]

    public init(prs: [PREvent] = [], issues: [IssueEvent] = []) {
        self.prs = prs
        self.issues = issues
    }

    public var isEmpty: Bool { prs.isEmpty && issues.isEmpty }
}

/// Decides which coordinator updates are diffed by `ChangeDetector`.
///
/// Only live fetches count: an update is the result of a fetch when it follows a refresh marker
/// (`isRefreshing`), has no error, carries a snapshot fetched after launch, and that snapshot is new
/// and belongs to the same account and org as the marker's. Cached snapshots never count. The first
/// live fetch after launch, and the first after an account or org switch, is the baseline and posts
/// nothing; later live fetches for the same account and org are diffed against the previous one.
/// A fast CI follow (`isCIFollow`) counts as a live fetch merged into the baseline: it is diffed
/// against the baseline when it carries the baseline's `fetchedAt`, and then becomes the baseline,
/// so the next full refresh never posts its changes again.
/// A review request the viewer made themselves (`ownReviewRequest`) posts nothing: its pull request's
/// "review requested" is held back on every live fetch up to and including the first whose Review list
/// asks the viewer, and for at most `selfRequestWindow`.
public struct NotificationGate: Sendable {
    /// The override's five minutes and a poll's slack.
    public static let selfRequestWindow: TimeInterval = 360

    private let launchedAt: Date
    private var baseline: Snapshot?
    /// Set by a refresh marker: the snapshot held when the attempt started (`.some(nil)` when none).
    private var marker: Snapshot??
    /// Pull requests the viewer asked themselves (or one of their teams) to review, until when.
    private var ownRequests: [PRKey: Date] = [:]

    public init(launchedAt: Date) {
        self.launchedAt = launchedAt
    }

    /// Forgets the baseline and any pending refresh marker (account or org changed).
    public mutating func reset() {
        self = NotificationGate(launchedAt: launchedAt)
    }

    /// The viewer asked themselves, or one of their teams, to review `key` at `date`.
    public mutating func ownReviewRequest(on key: PRKey, at date: Date) {
        ownRequests[key] = date.addingTimeInterval(Self.selfRequestWindow)
    }

    /// The PR events of `changes(...)`, with nothing merged here. For tests: the app calls `changes`.
    mutating func events(
        snapshot: Snapshot?, status: RefreshStatus, toggles: NotificationToggles,
        filters: ReviewFilters = .none, now: Date = Date()
    ) -> [PREvent] {
        changes(snapshot: snapshot, status: status, toggles: toggles, filters: filters, mergedHere: [], readiedHere: [], now: now).prs
    }

    /// `mergedHere`: the pull requests merged from PullBull this session, which `ChangeDetector` keeps silent.
    /// `readiedHere`: those marked ready from PullBull, whose review request for the viewer is silent too.
    public mutating func changes(
        snapshot: Snapshot?, status: RefreshStatus, toggles: NotificationToggles,
        filters: ReviewFilters = .none, mergedHere: Set<PRKey>, readiedHere: Set<PRKey> = [],
        now: Date = Date()
    ) -> NotificationChanges {
        if status.isRefreshing {
            marker = .some(snapshot)
            return NotificationChanges()
        }
        if status.isCIFollow {
            guard status.error == nil, let fresh = snapshot, let old = baseline, Self.sameContext(old, fresh),
                  fresh.fetchedAt == old.fetchedAt
            else { return NotificationChanges() }
            baseline = fresh
            return settle(diff(old, fresh, toggles: toggles, filters: filters, mergedHere: mergedHere, readiedHere: readiedHere, now: now), fresh, now: now)
        }
        guard let started = marker else { return NotificationChanges() }
        marker = nil
        guard status.error == nil, let fresh = snapshot, fresh.fetchedAt >= launchedAt else {
            return NotificationChanges()
        }
        if let started {
            guard Self.sameContext(started, fresh), fresh.fetchedAt != started.fetchedAt else {
                return NotificationChanges()
            }
        }

        defer { baseline = fresh }
        guard let old = baseline, Self.sameContext(old, fresh), fresh.fetchedAt > old.fetchedAt else {
            return settle(NotificationChanges(), fresh, now: now)
        }
        return settle(diff(old, fresh, toggles: toggles, filters: filters, mergedHere: mergedHere, readiedHere: readiedHere, now: now), fresh, now: now)
    }

    /// Holds back the viewer's own review requests in `changes` from the live fetch `fresh`, and ends
    /// the hold for each pull request `fresh` lists on Review as asking the viewer.
    private mutating func settle(_ changes: NotificationChanges, _ fresh: Snapshot, now: Date) -> NotificationChanges {
        ownRequests = ownRequests.filter { $0.value > now }
        guard !ownRequests.isEmpty else { return changes }
        var changes = changes
        changes.prs.removeAll { $0.kind == .reviewRequested && ownRequests[$0.pr.key] != nil }
        for pr in fresh.reviewCandidates where ownRequests[pr.key] != nil
            && ReviewRules.status(of: pr, me: fresh.org.viewer, myTeams: fresh.org.myTeams).reviewReason != nil {
            ownRequests[pr.key] = nil
        }
        return changes
    }

    private func diff(
        _ old: Snapshot, _ fresh: Snapshot, toggles: NotificationToggles, filters: ReviewFilters,
        mergedHere: Set<PRKey>, readiedHere: Set<PRKey>, now: Date
    ) -> NotificationChanges {
        NotificationChanges(
            prs: ChangeDetector.events(
                old: old, new: fresh, me: fresh.org.viewer, myTeams: fresh.org.myTeams, toggles: toggles,
                filters: filters, mergedHere: mergedHere, readiedHere: readiedHere, now: now),
            issues: ChangeDetector.issueEvents(old: old, new: fresh, me: fresh.org.viewer, toggles: toggles))
    }

    private static func sameContext(_ a: Snapshot, _ b: Snapshot) -> Bool {
        a.org.isPersonal == b.org.isPersonal
            && a.org.org.caseInsensitiveCompare(b.org.org) == .orderedSame
            && a.org.viewer.caseInsensitiveCompare(b.org.viewer) == .orderedSame
    }
}
