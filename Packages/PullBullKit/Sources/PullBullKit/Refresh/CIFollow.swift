import Foundation

/// Which of my pull requests with pending CI the coordinator looks at again between full refreshes,
/// so CI failed and Ready to merge arrive sooner. A head is followed for `maxPending` from when the app
/// first saw it pending; a new push (another head) starts its clock again.
public struct CIFollow: Equatable, Sendable {
    public static let interval: Duration = .seconds(30)
    /// The most pull requests one follow looks up.
    public static let cap = 5
    public static let maxPending: TimeInterval = 1200

    private struct Entry: Equatable, Sendable {
        let head: String
        let since: Date
    }

    private var pending: [PRKey: Entry] = [:]

    public init() {}

    /// Records when each of Mine's open pull requests was first seen pending on its current head, and
    /// forgets the ones no longer pending.
    public mutating func observe(_ snap: Snapshot, now: Date) {
        var kept: [PRKey: Entry] = [:]
        for pr in snap.mine where Self.isFollowable(pr) {
            let head = Self.head(of: pr)
            if let entry = pending[pr.key], entry.head == head {
                kept[pr.key] = entry
            } else {
                kept[pr.key] = Entry(head: head, since: now)
            }
        }
        pending = kept
    }

    /// Mine's open pull requests with pending CI (drafts too: their checks still run), pending for less
    /// than `maxPending` on their current head; the newest head commits first, then those without a
    /// date, at most `cap`. One not yet observed counts as seen pending now.
    public func selection(in snap: Snapshot, now: Date) -> [PRKey] {
        let due = snap.mine.filter { pr in
            guard Self.isFollowable(pr) else { return false }
            guard let entry = pending[pr.key], entry.head == Self.head(of: pr) else { return true }
            return now.timeIntervalSince(entry.since) < Self.maxPending
        }
        var seen = Set<PRKey>()
        let sorted = due.enumerated().sorted { a, b in
            switch (a.element.headCommitDate, b.element.headCommitDate) {
            case let (x?, y?) where x != y: x > y
            case (.some, nil): true
            case (nil, .some): false
            default: a.offset < b.offset
            }
        }
        return Array(sorted.map(\.element.key).filter { seen.insert($0).inserted }.prefix(Self.cap))
    }

    /// No follow while a full refresh runs or is due within `interval`, nor while offline or
    /// rate limited.
    public static func shouldRun(now: Date, nextFullAt: Date?, fullInFlight: Bool, error: RefreshError?) -> Bool {
        guard !fullInFlight else { return false }
        switch error {
        case .offline, .rateLimited: return false
        default: break
        }
        guard let nextFullAt else { return true }
        return nextFullAt > now.addingTimeInterval(TimeInterval(interval.components.seconds))
    }

    private static func isFollowable(_ pr: PullRequest) -> Bool {
        pr.state == .open && pr.ci == .pending
    }

    /// The head commit: its oid, or its date when the oid wasn't fetched.
    private static func head(of pr: PullRequest) -> String {
        if let oid = pr.headCommitOid { return oid }
        return pr.headCommitDate.map { "date:\($0.timeIntervalSince1970)" } ?? ""
    }
}
