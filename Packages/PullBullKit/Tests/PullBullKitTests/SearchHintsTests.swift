import Foundation
import Testing
@testable import PullBullKit

private func savedSearches(_ count: Int) -> SavedSearches {
    var saved = SavedSearches()
    for n in 1...count { saved.add(name: "s\(n)", query: "q\(n)") }
    return saved
}

/// Every chip 100pt wide on a 344pt line: three to a line.
private func cloud(_ saved: SavedSearches, expanded: Bool = false) -> SavedChipCloud {
    SavedChipCloud(saved: saved, expanded: expanded, width: 344) { _ in 100 }
}

@Suite struct SearchHintTests {
    @Test func theTokenLineInOrder() {
        #expect(SearchHint.all == [.number, .person, .label, .state, .status])
        #expect(SearchHint.all.map(\.word) == ["number", "person", "label", "state", "column"])
    }

    @Test func sigils() {
        #expect(SearchHint.number.sigil == "#")
        #expect(SearchHint.person.sigil == "@")
        #expect(SearchHint.label.sigil == "~")
        #expect(SearchHint.state.sigil == "is:")
        #expect(SearchHint.person.opensList)
        #expect(SearchHint.state.opensList)
        #expect(!SearchHint.number.opensList)
    }

    @Test func voiceOver() {
        #expect(SearchHint.person.accessibilityLabel == "@ person")
        #expect(SearchHint.state.accessibilityLabel == "is: state")
        #expect(SearchHint.person.accessibilityHint == "Types @ in the search field")
        #expect(SearchHint.number.accessibilityHint == "Types # in the search field")
    }

    /// The caption's sentence for each token; the number's names the scope it searches.
    @Test func captions() {
        #expect(SearchHint.person.caption(scope: nil) == "@name filters by author, assignee or reviewer")
        #expect(SearchHint.label.caption(scope: nil) == "~label filters by label")
        #expect(SearchHint.state.caption(scope: nil) == "is:open, closed, merged or draft filters by state")
        #expect(SearchHint.number.caption(scope: .org("initech")) == "A number finds it in every initech repo")
        #expect(SearchHint.number.caption(scope: .personal(login: "me")) == "A number finds it in your repos")
        #expect(SearchHint.number.caption(scope: nil) == "A number finds it in every repo")
    }

    /// Picking the `is:` hint leaves `is:` in the field with its four states listed.
    @Test func stateHintOpensTheStateList() {
        var field = SearchFieldState()
        let sigil = SearchHint.state.sigil
        field.edit(sigil, caret: sigil.utf16.count, people: .empty)
        #expect(field.stateCompletion?.candidates.map(\.state) == [.open, .closed, .merged, .draft])
    }
}

@Suite struct HintPanelItemTests {
    private static let tokens: [HintPanelItem] = [.hint(.number), .hint(.person), .hint(.label), .hint(.state), .hint(.status)]

    @Test func chipsComeBeforeTheTokens() {
        let saved = savedSearches(2)
        let ids = saved.items.map(\.id)
        #expect(HintPanelItem.items(cloud: cloud(saved)) == [.saved(ids[0]), .saved(ids[1])] + Self.tokens)
        #expect(HintPanelItem.items(cloud: cloud(SavedSearches())) == Self.tokens)
    }

    @Test func plusNAndShowLessAreOneItem() {
        let saved = savedSearches(8)
        let folded = HintPanelItem.items(cloud: cloud(saved))
        #expect(folded.count == 5 + 1 + 5)
        #expect(folded[5] == .more)
        #expect(folded[6] == .hint(.number))
        let expanded = HintPanelItem.items(cloud: cloud(saved, expanded: true))
        #expect(expanded.count == 8 + 1 + 5)
        #expect(expanded[8] == .more)
    }

    /// ↓ walks the chips and then the tokens, and stops at the last.
    @Test func downWalksInReadingOrder() {
        let saved = savedSearches(2)
        let ids = saved.items.map(\.id)
        let items = HintPanelItem.items(cloud: cloud(saved))
        #expect(HintPanelItem.move(nil, .down, in: items) == .select(.saved(ids[0])))
        #expect(HintPanelItem.move(.saved(ids[0]), .down, in: items) == .select(.saved(ids[1])))
        #expect(HintPanelItem.move(.saved(ids[1]), .down, in: items) == .select(.hint(.number)))
        #expect(HintPanelItem.move(.hint(.status), .down, in: items) == .select(.hint(.status)))
    }

    /// ↑ goes back, and from the first item returns to the field; in the field it stays there.
    @Test func upFromTheFirstItemReturnsToTheField() {
        let saved = savedSearches(2)
        let ids = saved.items.map(\.id)
        let items = HintPanelItem.items(cloud: cloud(saved))
        #expect(HintPanelItem.move(.hint(.number), .up, in: items) == .select(.saved(ids[1])))
        #expect(HintPanelItem.move(.saved(ids[0]), .up, in: items) == .field)
        #expect(HintPanelItem.move(nil, .up, in: items) == .field)
        #expect(HintPanelItem.move(.hint(.number), .up, in: Self.tokens) == .field)
    }

    /// ← / → move through the same order while the cursor is in the panel, stopping at both ends; with
    /// nothing selected they are not the panel's.
    @Test func leftAndRightMoveOnlyWithACursor() {
        let saved = savedSearches(2)
        let ids = saved.items.map(\.id)
        let items = HintPanelItem.items(cloud: cloud(saved))
        #expect(HintPanelItem.move(.saved(ids[0]), .right, in: items) == .select(.saved(ids[1])))
        #expect(HintPanelItem.move(.saved(ids[1]), .right, in: items) == .select(.hint(.number)))
        #expect(HintPanelItem.move(.hint(.number), .left, in: items) == .select(.saved(ids[1])))
        #expect(HintPanelItem.move(.saved(ids[0]), .left, in: items) == .select(.saved(ids[0])))
        #expect(HintPanelItem.move(.hint(.status), .right, in: items) == .select(.hint(.status)))
        #expect(HintPanelItem.move(nil, .left, in: items) == .pass)
        #expect(HintPanelItem.move(nil, .right, in: items) == .pass)
    }

    /// An item that went away (deleted, or hidden by Show less) counts as no cursor.
    @Test func aVanishedItemCountsAsNone() {
        let saved = savedSearches(2)
        let ids = saved.items.map(\.id)
        let items = HintPanelItem.items(cloud: cloud(saved))
        #expect(HintPanelItem.move(.saved(UUID()), .down, in: items) == .select(.saved(ids[0])))
        #expect(HintPanelItem.move(.saved(UUID()), .up, in: items) == .field)
        #expect(HintPanelItem.move(.more, .right, in: items) == .pass)
    }

    @Test func nothingToMoveTo() {
        #expect(HintPanelItem.move(nil, .down, in: []) == .pass)
        #expect(HintPanelItem.move(nil, .up, in: []) == .field)
    }
}

@Suite struct HintCaptionTests {
    @Test func aSavedChipShowsItsQuery() {
        var saved = SavedSearches()
        let search = saved.add(name: "Bugs", query: "~bug is:open")!
        let caption = HintCaption(for: .saved(search.id), saved: saved, scope: nil)
        #expect(caption == HintCaption(text: "~bug is:open", isQuery: true, showsReturn: true))
    }

    @Test func aTokenShowsItsSentence() {
        let caption = HintCaption(for: .hint(.number), saved: SavedSearches(), scope: .org("initech"))
        #expect(caption == HintCaption(text: "A number finds it in every initech repo", isQuery: false, showsReturn: true))
    }

    @Test func theMoreChipSaysWhatItDoes() {
        let saved = savedSearches(8)
        #expect(HintCaption(for: .more, saved: saved, scope: nil, expanded: false).text == "Show all 8 saved searches")
        #expect(HintCaption(for: .more, saved: saved, scope: nil, expanded: true).text == "Show fewer saved searches")
        #expect(HintCaption(for: .more, saved: saved, scope: nil).showsReturn)
    }

    @Test func nothingSelectedShowsTheDefault() {
        #expect(HintCaption(for: nil, saved: savedSearches(1), scope: nil)
            == HintCaption(text: "Words match titles · ↓ to choose", isQuery: false, showsReturn: false))
        #expect(HintCaption(for: nil, saved: SavedSearches(), scope: nil)
            == HintCaption(text: "Words match titles · bookmark a search to keep it here", isQuery: false,
                           showsReturn: false))
    }

    /// A deleted search's cursor reads as no cursor.
    @Test func aVanishedSearchShowsTheDefault() {
        let caption = HintCaption(for: .saved(UUID()), saved: savedSearches(1), scope: nil)
        #expect(caption.text == "Words match titles · ↓ to choose")
        #expect(!caption.showsReturn)
    }

    @Test func moreChipVoiceOver() {
        #expect(SavedChipCloud.More.hidden(3).accessibilityLabel(total: 8) == "Show all 8 saved searches")
        #expect(SavedChipCloud.More.showLess.accessibilityLabel(total: 8) == "Show fewer saved searches")
        #expect(SavedChipCloud.More.hidden(3).title == "+3")
        #expect(SavedChipCloud.More.showLess.title == "Show less")
    }
}
