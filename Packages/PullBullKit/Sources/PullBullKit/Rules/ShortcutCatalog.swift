import Foundation

/// One shortcut in the Keyboard Shortcuts window.
public struct Shortcut: Hashable, Sendable {
    /// Each way to press it, as keycaps in order: `[["⌘", "↩"]]`. Empty for a shortcut not set.
    public let keys: [[String]]
    public let action: String
    /// Where it works, or what it does beyond the action; nil when the action says it all.
    public let note: String?

    public init(_ action: String, _ keys: [[String]], note: String? = nil) {
        self.action = action
        self.keys = keys
        self.note = note
    }
}

/// A titled group of shortcuts, as the manual's Keyboard tables group them.
public struct ShortcutSection: Hashable, Sendable, Identifiable {
    public let title: String
    /// Where the whole section applies; nil when the title says it.
    public let note: String?
    public let shortcuts: [Shortcut]

    public var id: String { title }

    public init(_ title: String, note: String? = nil, _ shortcuts: [Shortcut]) {
        self.title = title
        self.note = note
        self.shortcuts = shortcuts
    }
}

/// Every keyboard shortcut PullBull has, for the Keyboard Shortcuts window. Keep it in step with the
/// manual's Keyboard and Search sections. Modifiers come in the menu order ⌃⌥⇧⌘.
public enum ShortcutCatalog {
    /// `toggle` is the recorded show-or-hide shortcut as keycaps, nil when none is set.
    public static func sections(toggle: [String]?) -> [ShortcutSection] {
        [
            ShortcutSection("PullBull", [
                toggle.map { Shortcut("Show or hide PullBull", [$0], note: "From any app") }
                    ?? Shortcut("Show or hide PullBull", [], note: "Not set: Settings → General"),
                Shortcut("Settings", [["⌘", ","]]),
                Shortcut("Keyboard shortcuts", [["⌘", "/"]]),
                Shortcut("Refresh", [["⌘", "R"]]),
                Shortcut("Close", [["⌘", "W"]]),
            ]),
            ShortcutSection("Lists", [
                Shortcut("Select", [["↑"], ["↓"]]),
                Shortcut("Previous / next group", [["⌥", "↑"], ["⌥", "↓"]],
                         note: "Repo, author, lane, Done, Closed. Folded lanes are skipped"),
                Shortcut("First / last row", [["⌘", "↑"], ["⌘", "↓"]]),
                Shortcut("Previous / next tab", [["←"], ["→"]]),
                Shortcut("Pull Requests", [["⌘", "1"]]),
                Shortcut("Issues", [["⌘", "2"]]),
                Shortcut("Open detail", [["↩"]]),
                Shortcut("Open on GitHub", [["⌘", "↩"]]),
                Shortcut("Repo menu", [["⇧", "⌘", "F"]], note: "Show only one repo"),
                Shortcut("Board menu", [["⇧", "⌘", "B"]], note: "On the Board tab"),
                Shortcut("Account menu", [["⇧", "⌘", "A"]]),
                Shortcut("Back out", [["Esc"]], note: "Clear search, then clear the repo, then close"),
            ]),
            ShortcutSection("Copy and open", note: "Lists, search results and the detail", [
                Shortcut("Copy link", [["⌘", "C"]]),
                Shortcut("Copy owner/repo#123", [["⇧", "⌘", "C"]]),
                Shortcut("Copy Markdown link", [["⌥", "⌘", "C"]]),
                Shortcut("Copy checkout command", [["⌃", "⌘", "C"]], note: "Pull requests"),
                Shortcut("Files changed", [["⇧", "⌘", "↩"]],
                         note: "Pull requests. Only the changes since your review when there are new commits"),
            ]),
            ShortcutSection("Search", [
                Shortcut("Search", [["/"], ["⌘", "F"]], note: "Or just start typing"),
                Shortcut("Saved search 1–9", [["⌃", "1…9"]], note: "In Settings order"),
                Shortcut("Narrow to the tab beside", [["←"], ["→"]], note: "At the field's start or end"),
                Shortcut("Ask AI", [["⌥", "⌘", "↩"]], note: "From the field, once Ask AI is on"),
                Shortcut("Take the grey suggestion", [["⇥"]], note: "Writes it and opens its list"),
            ]),
            ShortcutSection("Completion list", note: "After @, ~, is:, status: and the other tokens", [
                Shortcut("Choose", [["↑"], ["↓"]]),
                Shortcut("Complete", [["↩"], ["⇥"]]),
                Shortcut("Close", [["Esc"]]),
            ]),
            ShortcutSection("Detail", [
                Shortcut("Back", [["Esc"], ["←"], ["⌘", "["]]),
                Shortcut("Next / previous item", [["⌥", "↓"], ["⌥", "↑"]],
                         note: "Of the list or search you came from"),
                Shortcut("Open on GitHub", [["⌘", "↩"]]),
            ]),
            ShortcutSection("Ask AI answers", [
                Shortcut("Move the highlight", [["↑"], ["↓"]]),
                Shortcut("Open in PullBull", [["↩"]]),
                Shortcut("Open on GitHub", [["⌘", "↩"]]),
                Shortcut("Back to the question", [["Esc"], ["←"]]),
            ]),
        ]
    }

    /// The shortcuts every word of `query` finds, by the start of a word in the section's title or
    /// note, or the shortcut's action or note; case is ignored. Sections left empty drop out.
    public static func filter(_ sections: [ShortcutSection], query: String) -> [ShortcutSection] {
        let wanted = words(query)
        guard !wanted.isEmpty else { return sections }
        return sections.compactMap { section in
            let sectionWords = words(section.title) + words(section.note ?? "")
            let kept = section.shortcuts.filter { shortcut in
                let have = sectionWords + words(shortcut.action) + words(shortcut.note ?? "")
                return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
            }
            return kept.isEmpty ? nil : ShortcutSection(section.title, note: section.note, kept)
        }
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
