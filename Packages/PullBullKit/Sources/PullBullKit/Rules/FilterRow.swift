import Foundation

/// The row at the top of every list: "▦ Roadmap ▾ · ▤ All repos ▾" on the Board tab, "▤ All repos ▾"
/// elsewhere, "▤ widgets ▾ ✕" with a repo focus. Each part opens its menu; a time focus adds a plain label
/// ("◷ Last 3 days") after the repo part.
public struct FilterRow: Equatable, Sendable {
    /// The repo part's label: "All repos", or the focused repository's display name.
    public let repoTitle: String
    /// A repo or time focus is active: ✕ clears both.
    public let isFocused: Bool
    /// A repo focus is active: the repo label is tinted.
    public let isRepoFocused: Bool
    /// The time focus's full line ("Updated today"), for the tooltip and VoiceOver; nil without one and in
    /// search.
    public let timeTitle: String?
    /// The board part's name, only on the Board tab while it offers the board menu, and never in search.
    public let boardTitle: String?

    public init(repoTitle: String, isFocused: Bool, isRepoFocused: Bool, timeTitle: String? = nil, boardTitle: String?) {
        self.repoTitle = repoTitle
        self.isFocused = isFocused
        self.isRepoFocused = isRepoFocused
        self.timeTitle = timeTitle
        self.boardTitle = boardTitle
    }

    public static let allRepos = "All repos"

    /// The row for the list or search results on screen; nil while there is nothing to filter yet (the
    /// loading or error state fills the popover) unless a focus is active, so ✕ stays in reach. Search
    /// shows the repo part only, as it isn't board-scoped and ignores the tab's time focus. `focusName` is
    /// the focused repository's display name; `timeTitle` the time focus's full line; `boardTitle` is given
    /// only on the Board tab while it offers the board menu.
    public static func make(
        searching: Bool, listsBuilt: Bool, focusName: String?, timeTitle: String?, boardTitle: String?
    ) -> FilterRow? {
        let time = searching ? nil : timeTitle
        guard listsBuilt || focusName != nil || time != nil else { return nil }
        return FilterRow(
            repoTitle: focusName ?? allRepos, isFocused: focusName != nil || time != nil, isRepoFocused: focusName != nil, timeTitle: time,
            boardTitle: listsBuilt && !searching ? boardTitle : nil)
    }

    /// VoiceOver's label for the repo and time parts: "Showing only widgets, updated today. 2 of 4 in
    /// Review." with both (the tally only when the tab has one), "Showing all repositories, updated today."
    /// with a time focus alone, "Showing all repositories" without.
    public func spokenLabel(tally: String?) -> String {
        guard isFocused else { return "Showing all repositories" }
        let repo = isRepoFocused ? "Showing only \(repoTitle)" : "Showing all repositories"
        let time = timeTitle.map {
            ", " + ($0.prefix(1).lowercased() + $0.dropFirst()).replacingOccurrences(of: " · ", with: ", ")
        } ?? ""
        return repo + time + "." + (tally.map { " \($0)." } ?? "")
    }

    /// VoiceOver's label for the board part: "Board, Roadmap".
    public var boardSpokenLabel: String? { boardTitle.map { "Board, \($0)" } }

    /// "2 of 4 in Review": the focused and all counted items of the tab on screen.
    public static func tally(_ shown: Int, of total: Int, in tab: String) -> String {
        "\(shown) of \(total) in \(tab)"
    }
}
