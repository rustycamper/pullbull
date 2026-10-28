import Foundation

/// The row at the top of every list: "▦ Roadmap ▾ · ▤ All repos ▾" on the Board tab, "▤ All repos ▾"
/// elsewhere, "▤ widgets ▾ ✕" with a repo focus. Each part opens its menu.
public struct FilterRow: Equatable, Sendable {
    /// The repo part's label: "All repos", or the focused repository's display name.
    public let repoTitle: String
    /// A repo focus is active: the label is tinted and ✕ clears it.
    public let isFocused: Bool
    /// The board part's name, only on the Board tab while it offers the board menu, and never in search.
    public let boardTitle: String?

    public init(repoTitle: String, isFocused: Bool, boardTitle: String?) {
        self.repoTitle = repoTitle
        self.isFocused = isFocused
        self.boardTitle = boardTitle
    }

    public static let allRepos = "All repos"

    /// The row for the list or search results on screen; nil while there is nothing to filter yet (the
    /// loading or error state fills the popover) unless a focus is active, so ✕ stays in reach. Search
    /// shows the repo part only, as it isn't board-scoped. `focusName` is the focused repository's display
    /// name; `boardTitle` is given only on the Board tab while it offers the board menu.
    public static func make(
        searching: Bool, listsBuilt: Bool, focusName: String?, boardTitle: String?
    ) -> FilterRow? {
        guard listsBuilt || focusName != nil else { return nil }
        return FilterRow(
            repoTitle: focusName ?? allRepos, isFocused: focusName != nil,
            boardTitle: listsBuilt && !searching ? boardTitle : nil)
    }

    /// VoiceOver's label for the repo part: "Showing only widgets. 2 of 4 in Review." with a focus
    /// (the tally only when the tab has one), "Showing all repositories" without.
    public func repoSpokenLabel(tally: String?) -> String {
        guard isFocused else { return "Showing all repositories" }
        return "Showing only \(repoTitle)." + (tally.map { " \($0)." } ?? "")
    }

    /// VoiceOver's label for the board part: "Board, Roadmap".
    public var boardSpokenLabel: String? { boardTitle.map { "Board, \($0)" } }

    /// "2 of 4 in Review": the focused and all counted items of the tab on screen.
    public static func tally(_ shown: Int, of total: Int, in tab: String) -> String {
        "\(shown) of \(total) in \(tab)"
    }
}
