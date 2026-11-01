import Foundation
import Testing
@testable import PullBullKit

private let modifierOrder = ["⌃", "⌥", "⇧", "⌘"]

@Suite struct ShortcutCatalogTests {
    @Test func sectionsInOrder() {
        #expect(ShortcutCatalog.sections(toggle: nil).map(\.title)
            == ["PullBull", "Lists", "Copy and open", "Search", "Completion list", "Editing", "Detail",
                "Ask AI answers"])
    }

    @Test func editingShortcuts() throws {
        let editing = try #require(ShortcutCatalog.sections(toggle: nil).first { $0.title == "Editing" })
        #expect(editing.note == "Issue rows, search results and the issue detail")
        #expect(editing.shortcuts == [
            Shortcut("Set Status", [["⌥", "⌘", "S"]], note: "When a board is shown"),
            Shortcut("Assignees", [["⌥", "⌘", "A"]]),
            Shortcut("Labels", [["⌥", "⌘", "L"]]),
            Shortcut("Undo the last edit", [["⌘", "Z"]], note: "For 10 seconds after it"),
            Shortcut("Choose", [["↑"], ["↓"]], note: "In a picker; type to filter"),
            Shortcut("Apply", [["↩"]], note: "Status picker"),
            Shortcut("Tick or untick", [["↩"]], note: "Assignees and labels"),
            Shortcut("Apply and close", [["⌘", "↩"]]),
            Shortcut("Close", [["Esc"]], note: "Status: without change. Assignees and labels: applies"),
        ])
    }

    @Test func everySectionHasShortcutsAndEveryShortcutKeys() {
        for section in ShortcutCatalog.sections(toggle: ["⌃", "⌥", "P"]) {
            #expect(!section.shortcuts.isEmpty, "\(section.title)")
            for shortcut in section.shortcuts {
                #expect(!shortcut.keys.isEmpty, "\(shortcut.action)")
                #expect(shortcut.keys.allSatisfy { !$0.isEmpty }, "\(shortcut.action)")
            }
        }
    }

    /// Modifiers lead each combo in the menu order ⌃⌥⇧⌘, as macOS menus show them.
    @Test func modifiersInMenuOrder() {
        for section in ShortcutCatalog.sections(toggle: nil) {
            for combo in section.shortcuts.flatMap(\.keys) {
                let modifiers = combo.prefix { modifierOrder.contains($0) }
                let positions = modifiers.compactMap { modifierOrder.firstIndex(of: $0) }
                #expect(positions == positions.sorted(), "\(combo)")
                #expect(!combo.dropFirst(modifiers.count).contains { modifierOrder.contains($0) }, "\(combo)")
            }
        }
    }

    /// Within a section a combo does one thing, or one thing per context its note names (↩ in each picker).
    @Test func noComboTwiceInASection() {
        for section in ShortcutCatalog.sections(toggle: nil) {
            let combos = section.shortcuts.flatMap { shortcut in shortcut.keys.map { [$0, [shortcut.note ?? ""]] } }
            #expect(Set(combos).count == combos.count, "\(section.title)")
        }
    }

    @Test func theRecordedToggleShortcut() {
        let toggle = ShortcutCatalog.sections(toggle: ["⌃", "⌥", "P"])[0].shortcuts[0]
        #expect(toggle.action == "Show or hide PullBull")
        #expect(toggle.keys == [["⌃", "⌥", "P"]])
        #expect(toggle.note == "From any app")
    }

    @Test func noToggleShortcutSaysWhereToSetOne() {
        let toggle = ShortcutCatalog.sections(toggle: nil)[0].shortcuts[0]
        #expect(toggle.action == "Show or hide PullBull")
        #expect(toggle.keys.isEmpty)
        #expect(toggle.note == "Not set: Settings → General")
    }

    @Test func thisWindowsOwnShortcut() {
        let app = ShortcutCatalog.sections(toggle: nil)[0]
        #expect(app.shortcuts.contains { $0.action == "Keyboard shortcuts" && $0.keys == [["⌘", "/"]] })
    }

    // MARK: Filter

    private let all = ShortcutCatalog.sections(toggle: ["⌃", "⌥", "P"])

    @Test func emptyOrBlankQueryKeepsEverything() {
        #expect(ShortcutCatalog.filter(all, query: "") == all)
        #expect(ShortcutCatalog.filter(all, query: "   ") == all)
    }

    @Test func matchesActionWordsCaseInsensitively() {
        let found = ShortcutCatalog.filter(all, query: "MARKDOWN")
        #expect(found.map(\.title) == ["Copy and open"])
        #expect(found[0].shortcuts.map(\.action) == ["Copy Markdown link"])
    }

    @Test func matchesNotes() {
        let found = ShortcutCatalog.filter(all, query: "board tab")
        #expect(found.flatMap(\.shortcuts).map(\.action) == ["Board menu"])
    }

    @Test func everyWordMustMatch() {
        #expect(ShortcutCatalog.filter(all, query: "copy checkout").flatMap(\.shortcuts).map(\.action)
            == ["Copy checkout command"])
        #expect(ShortcutCatalog.filter(all, query: "copy zebra").isEmpty)
    }

    /// Words match at the start of a word, so "tab" doesn't find "table" or every "Status".
    @Test func matchesWordStartsOnly() {
        #expect(ShortcutCatalog.filter(all, query: "opy").isEmpty)
    }

    @Test func aSectionTitleKeepsTheWholeSection() {
        let found = ShortcutCatalog.filter(all, query: "detail")
        let detail = all.first { $0.title == "Detail" }!
        #expect(found.contains(detail))
    }

    @Test func sectionsWithoutMatchesDrop() {
        let found = ShortcutCatalog.filter(all, query: "saved")
        #expect(found.map(\.title) == ["Search"])
    }
}
