import Foundation

/// ⌥↓ / ⌥↑ in a detail: the list or search results it was opened from, in the order shown at the time,
/// and where in them the detail is. The order is a snapshot, so a refresh mid-walk doesn't reshuffle it.
/// It stops at either end, with no wrap.
public struct DetailWalk: Equatable, Sendable {
    /// Which detail the walk opens: a PR walk never shows in an issue detail, nor the other way round.
    public enum Kind: Sendable { case pullRequest, issue }

    public let keys: [PRKey]
    public let kind: Kind
    public private(set) var index: Int

    /// Nil when `key` isn't one of `keys`: a detail opened some other way has no walk.
    public init?(keys: [PRKey], opening key: PRKey, kind: Kind) {
        guard let index = keys.firstIndex(of: key) else { return nil }
        self.keys = keys
        self.kind = kind
        self.index = index
    }

    /// The item the walk is on.
    public var current: PRKey { keys[index] }

    /// The walk `offset` items on; nil past either end.
    public func stepped(by offset: Int) -> DetailWalk? {
        stepped(by: offset, skipping: { _ in false })
    }

    /// The walk on to the next item `offset`'s way that isn't `skipped` (one that has left the data);
    /// nil when there's none before the end. The skipped items keep their places, so the position still
    /// counts the order as it was shown.
    public func stepped(by offset: Int, skipping skipped: (PRKey) -> Bool) -> DetailWalk? {
        guard offset != 0 else { return self }
        let direction = offset > 0 ? 1 : -1
        var target = index + offset
        while keys.indices.contains(target) {
            if !skipped(keys[target]) {
                var walk = self
                walk.index = target
                return walk
            }
            target += direction
        }
        return nil
    }

    /// "2 of 6" for the back button; nil unless the detail showing `key` is the walk's current item and
    /// of its kind (a linked PR opened from an issue walk shows none).
    public func position(showing key: PRKey, kind: Kind) -> String? {
        guard kind == self.kind, key == current else { return nil }
        return "\(index + 1) of \(keys.count)"
    }
}
