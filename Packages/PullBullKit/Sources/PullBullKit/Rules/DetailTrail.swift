/// The details opened one from another through a relationship, starting at the one opened from a list.
/// Back steps to the one before. Following an item already on the trail goes back to it, so the trail
/// never holds an item twice.
public struct DetailTrail: Equatable, Sendable {
    /// One detail on the trail. The same number as an issue and as a PR are different entries.
    public struct Entry: Equatable, Hashable, Sendable {
        public let kind: DetailWalk.Kind
        public let key: PRKey

        /// An entry for the `kind` detail of `key`.
        public init(kind: DetailWalk.Kind, key: PRKey) {
            self.kind = kind
            self.key = key
        }
    }

    /// Base first, current last. Never empty, and no entry twice.
    public private(set) var entries: [Entry]

    /// A trail that has only `base`, the detail opened from a list.
    public init(base: Entry) {
        entries = [base]
    }

    /// The detail the trail started from.
    public var base: Entry { entries[0] }

    /// The detail being shown.
    public var current: Entry { entries[entries.count - 1] }

    /// The detail Back goes to; nil on the base.
    public var previous: Entry? { entries.count > 1 ? entries[entries.count - 2] : nil }

    /// Whether the trail is back at where it started.
    public var isOnBase: Bool { entries.count == 1 }

    /// Opens `entry` from the current detail. One already on the trail (the base included) cuts the
    /// trail back to it; the current entry is therefore a no-op.
    public mutating func follow(_ entry: Entry) {
        if let index = entries.firstIndex(of: entry) {
            entries.removeSubrange((index + 1)...)
        } else {
            entries.append(entry)
        }
    }

    /// Drops the current entry and returns the one now current; nil, with the trail unchanged, on the base.
    public mutating func back() -> Entry? {
        guard entries.count > 1 else { return nil }
        entries.removeLast()
        return current
    }
}
