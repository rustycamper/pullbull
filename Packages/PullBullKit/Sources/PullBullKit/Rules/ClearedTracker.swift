import Foundation

/// When a list (Review, Assigned) went from some items to none between two fetches seen this session,
/// so its empty state can say so. Only a newer fetch can clear it: a rebuild of the same fetch (a
/// setting changed) or a failed poll (the last good list again) just moves the baseline, and a fetch
/// from before `since` (the cache shown at launch) is a baseline that never counts. Kept in memory only.
public struct ClearedTracker: Equatable, Sendable {
    private struct Seen: Equatable, Sendable {
        let count: Int
        let fetchedAt: Date
    }

    /// When this app session started; fetches older than this are another session's.
    public let since: Date
    /// The fetch that found the list empty after it had items; nil once it has items again.
    public private(set) var clearedAt: Date?
    private var last: Seen?

    public init(since: Date) { self.since = since }

    /// The list as built from the fetch made at `fetchedAt`.
    public mutating func observe(count: Int, fetchedAt: Date) {
        defer { last = Seen(count: count, fetchedAt: fetchedAt) }
        if count > 0 {
            clearedAt = nil
            return
        }
        guard let last, last.count > 0, last.fetchedAt >= since, fetchedAt > last.fetchedAt else { return }
        clearedAt = fetchedAt
    }

    /// The account or org changed, or the list went away: what was seen no longer applies.
    public mutating func reset() {
        clearedAt = nil
        last = nil
    }

    /// The empty state's subtitle once cleared: "You cleared the last one 12 min ago."
    public static func subtitle(clearedAt: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(clearedAt)) / 60)
        let ago: String
        switch minutes {
        case ..<1: ago = "just now"
        case ..<60: ago = "\(minutes) min ago"
        case ..<1440: ago = "\(minutes / 60) hr ago"
        default: ago = minutes / 1440 == 1 ? "1 day ago" : "\(minutes / 1440) days ago"
        }
        return "You cleared the last one \(ago)."
    }
}
