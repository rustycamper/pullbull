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
public struct NotificationGate: Sendable {
    private let launchedAt: Date
    private var baseline: Snapshot?
    /// Set by a refresh marker: the snapshot held when the attempt started (`.some(nil)` when none).
    private var marker: Snapshot??

    public init(launchedAt: Date) {
        self.launchedAt = launchedAt
    }

    /// Forgets the baseline and any pending refresh marker (account or org changed).
    public mutating func reset() {
        self = NotificationGate(launchedAt: launchedAt)
    }

    /// The PR events of `changes(...)`.
    public mutating func events(
        snapshot: Snapshot?, status: RefreshStatus, toggles: NotificationToggles,
        filters: ReviewFilters = .none, now: Date = Date()
    ) -> [PREvent] {
        changes(snapshot: snapshot, status: status, toggles: toggles, filters: filters, now: now).prs
    }

    public mutating func changes(
        snapshot: Snapshot?, status: RefreshStatus, toggles: NotificationToggles,
        filters: ReviewFilters = .none, now: Date = Date()
    ) -> NotificationChanges {
        if status.isRefreshing {
            marker = .some(snapshot)
            return NotificationChanges()
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
            return NotificationChanges()
        }
        return NotificationChanges(
            prs: ChangeDetector.events(
                old: old, new: fresh, me: fresh.org.viewer, myTeams: fresh.org.myTeams, toggles: toggles,
                filters: filters, now: now),
            issues: ChangeDetector.issueEvents(old: old, new: fresh, me: fresh.org.viewer, toggles: toggles))
    }

    private static func sameContext(_ a: Snapshot, _ b: Snapshot) -> Bool {
        a.org.isPersonal == b.org.isPersonal
            && a.org.org.caseInsensitiveCompare(b.org.org) == .orderedSame
            && a.org.viewer.caseInsensitiveCompare(b.org.viewer) == .orderedSame
    }
}
