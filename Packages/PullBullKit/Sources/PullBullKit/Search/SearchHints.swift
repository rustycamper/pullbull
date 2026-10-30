import Foundation

/// A clickable hint under the empty search field: it types its sigil into the field.
public enum SearchHint: Equatable, Sendable {
    case number, person, label, state, status, updated

    public var sigil: String {
        switch self {
        case .number: "#"
        case .person: "@"
        case .label: "~"
        case .state: "is:"
        case .status: "status:"
        case .updated: "updated:"
        }
    }

    /// The word after the sigil on its token.
    public var word: String {
        switch self {
        case .number: "number"
        case .person: "person"
        case .label: "label"
        case .state: "state"
        case .status: "column"
        case .updated: "time"
        }
    }

    /// Whether the token line draws `word` after the sigil. `status:` and `updated:` name themselves, and six
    /// tokens with words don't fit the line; VoiceOver still reads the word.
    public var showsWord: Bool { self != .status && self != .updated }

    /// Typing the sigil opens a completion list.
    public var opensList: Bool { self != .number }

    /// The token line, in order.
    public static let all: [SearchHint] = [.number, .person, .label, .state, .status, .updated]

    public var accessibilityLabel: String { "\(sigil) \(word)" }
    public var accessibilityHint: String { "Types \(sigil) in the search field" }

    /// The caption line's sentence while the token is selected; the number's names where it looks.
    public func caption(scope: FetchScope?) -> String {
        switch self {
        case .number:
            switch scope {
            case .org(let org): "A number finds it in every \(org) repo"
            case .personal: "A number finds it in your repos"
            case nil: "A number finds it in every repo"
            }
        case .person: "@name filters by author, assignee or reviewer"
        case .label: "~label filters by label"
        case .state: "is:open, closed, merged or draft filters by state"
        case .status: "status:name filters issues by board Status"
        case .updated: "updated:today, 3d, 1w or 1m filters by last activity"
        }
    }
}

/// An item the cursor reaches under the empty search field: a saved chip, "+N" (or "Show less"), or a
/// syntax token. One cursor spans them in reading order, the saved chips first.
public enum HintPanelItem: Hashable, Sendable {
    case saved(UUID)
    case more
    case hint(SearchHint)

    /// The cloud's chips, then the token line.
    public static func items(cloud: SavedChipCloud) -> [HintPanelItem] {
        cloud.chips.map(\.item) + SearchHint.all.map(HintPanelItem.hint)
    }

    /// Where `key` takes the cursor from `current` (nil: the caret is in the field, or the item is no
    /// longer in `items`). ↓ and ↑ walk the items and stop at the last; ↑ from the first returns to
    /// the field. ← and → walk them too, stopping at both ends, but only once the cursor is in the
    /// panel: without one they stay the field's.
    public static func move(_ current: HintPanelItem?, _ key: HintPanelKey, in items: [HintPanelItem]) -> HintPanelMove {
        let index = current.flatMap { items.firstIndex(of: $0) }
        switch (key, index) {
        case (.down, nil):
            return items.first.map(HintPanelMove.select) ?? .pass
        case (.up, nil), (.up, 0):
            return .field
        case (.left, nil), (.right, nil):
            return .pass
        case (.down, let index?), (.right, let index?):
            return .select(items[min(index + 1, items.count - 1)])
        case (.up, let index?), (.left, let index?):
            return .select(items[max(index - 1, 0)])
        }
    }
}

/// An arrow key under the empty search field.
public enum HintPanelKey: Sendable {
    case up, down, left, right
}

/// What an arrow does to the hint panel's cursor.
public enum HintPanelMove: Equatable, Sendable {
    case select(HintPanelItem)
    /// No item selected: the caret is the field's again.
    case field
    /// Not the panel's key: it goes on to the field.
    case pass
}

/// The fixed line under the token line: what the selected item does, or a default.
public struct HintCaption: Hashable, Sendable {
    public let text: String
    /// A saved search's query, drawn as code.
    public let isQuery: Bool
    /// An item is selected: the ↩ keycap shows.
    public let showsReturn: Bool

    public init(text: String, isQuery: Bool, showsReturn: Bool) {
        self.text = text
        self.isQuery = isQuery
        self.showsReturn = showsReturn
    }

    /// `expanded` is the cloud's state, for what the "+N" / "Show less" chip says.
    public init(for item: HintPanelItem?, saved: SavedSearches, scope: FetchScope?, expanded: Bool = false) {
        switch item {
        case .saved(let id):
            if let search = saved.items.first(where: { $0.id == id }) {
                self.init(text: search.query, isQuery: true, showsReturn: true)
                return
            }
        case .more:
            let more: SavedChipCloud.More = expanded ? .showLess : .hidden(0)
            self.init(text: more.accessibilityLabel(total: saved.items.count), isQuery: false, showsReturn: true)
            return
        case .hint(let hint):
            self.init(text: hint.caption(scope: scope), isQuery: false, showsReturn: true)
            return
        case nil:
            break
        }
        let idle = saved.isEmpty ? "Words match titles · bookmark a search to keep it here" : "Words match titles · ↓ to choose"
        self.init(text: idle, isQuery: false, showsReturn: false)
    }
}
