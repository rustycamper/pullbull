import Foundation

/// What each mode has for me that is new since I last looked at it, for the dot on the other mode's
/// glyph: Pull Requests counts PRs newly in Review (a new request, a re-request, new commits since my
/// review), Issues counts issues newly in Assigned. The mode on screen is always seen; the other one
/// compares its items with those it had when it was last on screen. The first look at a mode (launch,
/// another account) only records a baseline. Kept in memory only.
public struct ModeNews: Equatable, Sendable {
    /// One item of a mode's list: a PR and why it is in Review, or an assigned issue (no reason).
    public struct Item: Hashable, Sendable {
        let key: PRKey
        let reason: String?
    }

    private var seen: [PopoverMode: Set<Item>] = [:]
    private var current: [PopoverMode: Set<Item>] = [:]

    public init() {}

    /// `mode`'s items as just built; `shown` when that mode is on screen, which marks them all seen.
    public mutating func observe(_ mode: PopoverMode, items: Set<Item>, shown: Bool) {
        current[mode] = items
        if shown || seen[mode] == nil { seen[mode] = items }
    }

    /// `mode` came on screen: what it lists now is seen.
    public mutating func show(_ mode: PopoverMode) {
        guard let items = current[mode] else { return }
        seen[mode] = items
    }

    /// How many of `mode`'s items are new since it was last on screen.
    public func newCount(_ mode: PopoverMode) -> Int {
        guard let items = current[mode], let seen = seen[mode] else { return 0 }
        return items.subtracting(seen).count
    }

    /// The account or org changed: what was seen no longer applies.
    public mutating func reset() {
        seen = [:]
        current = [:]
    }

    /// Review's rows awaiting my review, each with its reason, so a re-request or new commits on a PR
    /// already listed counts as new. PRs I already approved (no reason) don't count.
    public static func items(review rows: [Row]) -> Set<Item> {
        Set(rows.compactMap { row in
            row.reviewReason.map { Item(key: row.pr.key, reason: String(describing: $0)) }
        })
    }

    /// Assigned's issues, without the folded Done group.
    public static func items(assigned contents: IssueTabContents) -> Set<Item> {
        Set(contents.groups.filter { $0.kind != .done }.flatMap(\.issues).map { Item(key: $0.key, reason: nil) })
    }

    /// The glyph's tooltip addition: "1 newly assigned", "2 new in Review"; nil with nothing new.
    public func note(_ mode: PopoverMode) -> String? {
        let count = newCount(mode)
        guard count > 0 else { return nil }
        switch mode {
        case .pullRequests: return "\(count) new in Review"
        case .issues: return "\(count) newly assigned"
        }
    }
}
