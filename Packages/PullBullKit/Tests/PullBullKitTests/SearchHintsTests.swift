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
        #expect(SearchHint.all == [.number, .person, .label, .state, .status, .updated, .review, .repo, .size, .negate])
        #expect(SearchHint.all.map(\.word)
            == ["number", "person", "label", "state", "column", "time", "review", "repo", "size", "not"])
    }

    /// Two fixed lines of five that read as `all`, each narrow enough that no token is cut off.
    @Test func twoLines() {
        #expect(SearchHint.lines == [
            [.number, .person, .label, .state, .status],
            [.updated, .review, .repo, .size, .negate],
        ])
        #expect(SearchHint.lines.flatMap { $0 } == SearchHint.all)
    }

    @Test func sigils() {
        #expect(SearchHint.number.sigil == "#")
        #expect(SearchHint.person.sigil == "@")
        #expect(SearchHint.label.sigil == "~")
        #expect(SearchHint.state.sigil == "is:")
        #expect(SearchHint.updated.sigil == "updated:")
        #expect(SearchHint.updated.opensList)
        #expect(!SearchHint.updated.showsWord)
        #expect(SearchHint.person.opensList)
        #expect(SearchHint.state.opensList)
        #expect(!SearchHint.number.opensList)
        #expect(SearchHint.all.map(\.sigil).suffix(4) == ["review:", "repo:", "size:", "-"])
        #expect(SearchHint.review.opensList && SearchHint.repo.opensList && SearchHint.size.opensList)
        #expect(!SearchHint.negate.opensList)
        #expect(!SearchHint.review.showsWord && !SearchHint.repo.showsWord && !SearchHint.size.showsWord)
        #expect(SearchHint.negate.showsWord)
    }

    @Test func voiceOver() {
        #expect(SearchHint.person.accessibilityLabel == "@ person")
        #expect(SearchHint.state.accessibilityLabel == "is: state")
        #expect(SearchHint.person.accessibilityHint == "Types @ in the search field")
        #expect(SearchHint.number.accessibilityHint == "Types # in the search field")
        #expect(SearchHint.negate.accessibilityLabel == "- not")
        #expect(SearchHint.size.accessibilityLabel == "size: size")
    }

    /// The caption's sentence for each token; the number's names the scope it searches.
    @Test func captions() {
        #expect(SearchHint.person.caption(scope: nil) == "@name filters by author, assignee or reviewer")
        #expect(SearchHint.label.caption(scope: nil) == "~label filters by label")
        #expect(SearchHint.state.caption(scope: nil) == "is:open, closed, merged or draft filters by state")
        #expect(SearchHint.updated.caption(scope: nil) == "updated:today, 3d, 1w or 1m filters by last activity")
        #expect(SearchHint.review.caption(scope: nil) == "review:changes or none filters by review")
        #expect(SearchHint.repo.caption(scope: nil) == "repo:name filters by repository")
        #expect(SearchHint.size.caption(scope: nil) == "size:s, m or l filters pull requests by lines changed")
        #expect(SearchHint.negate.caption(scope: nil)
            == "- before @, ~, is:, status:, updated:, review:, repo: or size: excludes it")
        #expect(SearchHint.number.caption(scope: .org("initech")) == "A number finds it in every initech repo")
        #expect(SearchHint.number.caption(scope: .personal(login: "me")) == "A number finds it in your repos")
        #expect(SearchHint.number.caption(scope: nil) == "A number finds it in every repo")
    }

    /// Picking the `is:` hint leaves `is:` in the field with its four states listed.
    @Test func stateHintOpensTheStateList() {
        var field = SearchFieldState()
        let sigil = SearchHint.state.sigil
        field.edit(sigil, caret: sigil.utf16.count, people: .empty)
        #expect(field.stateCompletion?.candidates.map(\.value) == IsValue.all)
    }

    /// Picking the `size:` hint lists the three sizes.
    @Test func sizeHintOpensTheSizeList() {
        var field = SearchFieldState()
        let sigil = SearchHint.size.sigil
        field.edit(sigil, caret: sigil.utf16.count, people: .empty)
        #expect(field.sizeCompletion?.candidates.map(\.size) == [.s, .m, .l])
    }

    /// Picking the `-` hint leaves `-` in the field: no list, no ghost, nothing searched.
    @Test func negateHintOpensNothing() {
        var field = SearchFieldState()
        let sigil = SearchHint.negate.sigil
        #expect(field.edit(sigil, caret: sigil.utf16.count, people: .empty) == nil)
        #expect(field.text == "-")
        #expect(field.searchCompletion == nil)
        #expect(field.ghost(statuses: .empty) == nil)
        #expect(SearchQuery.parse(sigil) == .empty)
    }

    /// After the `-` token, one it negates joins it; `#` and `-` start over, as every token does after other text.
    @Test func tokenAfterNegate() {
        #expect(SearchHint.person.text(after: "-") == "-@")
        #expect(SearchHint.size.text(after: "-") == "-size:")
        #expect(SearchHint.number.text(after: "-") == "#")
        #expect(SearchHint.negate.text(after: "-") == "-")
        #expect(SearchHint.person.text(after: "") == "@")
        #expect(SearchHint.person.text(after: "fix") == "@")
    }
}

@Suite struct HintPanelItemTests {
    private static let tokens: [HintPanelItem] = SearchHint.all.map(HintPanelItem.hint)

    @Test func chipsComeBeforeTheTokens() {
        let saved = savedSearches(2)
        let ids = saved.items.map(\.id)
        #expect(HintPanelItem.items(cloud: cloud(saved)) == [.saved(ids[0]), .saved(ids[1])] + Self.tokens)
        #expect(HintPanelItem.items(cloud: cloud(SavedSearches())) == Self.tokens)
    }

    @Test func plusNAndShowLessAreOneItem() {
        let saved = savedSearches(8)
        let folded = HintPanelItem.items(cloud: cloud(saved))
        #expect(folded.count == 5 + 1 + 10)
        #expect(folded[5] == .more)
        #expect(folded[6] == .hint(.number))
        let expanded = HintPanelItem.items(cloud: cloud(saved, expanded: true))
        #expect(expanded.count == 8 + 1 + 10)
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
        #expect(HintPanelItem.move(.hint(.updated), .down, in: items) == .select(.hint(.review)))
        #expect(HintPanelItem.move(.hint(.negate), .down, in: items) == .select(.hint(.negate)))
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
        #expect(HintPanelItem.move(.hint(.updated), .right, in: items) == .select(.hint(.review)))
        #expect(HintPanelItem.move(.hint(.review), .left, in: items) == .select(.hint(.updated)))
        #expect(HintPanelItem.move(.hint(.negate), .right, in: items) == .select(.hint(.negate)))
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
