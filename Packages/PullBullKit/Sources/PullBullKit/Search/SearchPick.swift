import Foundation

/// The highlighted search result, which Return opens. Return after typing is taken as "search", so a
/// result is highlighted only once it is picked (↑/↓, a click, a detail opened from it), or when the query
/// names one item (`#123`, `owner/repo#123`, a link) and exactly one result is shown.
public struct SearchPick: Equatable, Sendable {
    public var key: PRKey?
    /// Highlighted because the query names it, not picked: it goes when a second match arrives.
    public var implied: Bool

    public init(key: PRKey?, implied: Bool) {
        self.key = key
        self.implied = implied
    }

    public static let none = SearchPick(key: nil, implied: false)

    public static func picked(_ key: PRKey?) -> SearchPick { SearchPick(key: key, implied: false) }

    /// After results arrive, `keys` in display order: `kept` (highlighted when Back searched again) when
    /// shown, then the pick while it is shown, then the only result of a number or link query.
    public func updated(kept: PRKey?, query: SearchQuery, keys: [PRKey]) -> SearchPick {
        if let kept, keys.contains(kept) { return .picked(kept) }
        if !implied, let key, keys.contains(key) { return self }
        return Self.onlyMatch(of: query, in: keys)
    }

    private static func onlyMatch(of query: SearchQuery, in keys: [PRKey]) -> SearchPick {
        switch query {
        case .number, .item:
            guard keys.count == 1, let only = keys.first else { return .none }
            return SearchPick(key: only, implied: true)
        case .text, .filtered, .empty:
            return .none
        }
    }
}
