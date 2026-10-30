import Foundation
import Testing
@testable import PullBullKit

private func searches(_ count: Int) -> SavedSearches {
    var saved = SavedSearches()
    for n in 1...count { saved.add(name: "s\(n)", query: "q\(n)") }
    return saved
}

/// Every chip `width` wide, whatever it says.
private func cloud(_ saved: SavedSearches, expanded: Bool = false, chip width: CGFloat = 100,
                   line: CGFloat = 344) -> SavedChipCloud {
    SavedChipCloud(saved: saved, expanded: expanded, width: line) { _ in width }
}

@Suite struct SavedChipCloudTests {
    @Test func linesBreakGreedilyWithTheGap() {
        // 100 + 6 + 100 + 6 + 100 = 312 fits 344; a fourth doesn't.
        #expect(SavedChipCloud.lines([100, 100, 100, 100, 100], in: 344) == [[0, 1, 2], [3, 4]])
        #expect(SavedChipCloud.lines([170, 168], in: 344) == [[0, 1]])
        #expect(SavedChipCloud.lines([170, 169], in: 344) == [[0], [1]])
        #expect(SavedChipCloud.lines([], in: 344) == [])
    }

    /// A chip wider than the line takes a line of its own rather than an empty one before it.
    @Test func anOverwideChipGetsItsOwnLine() {
        #expect(SavedChipCloud.lines([400, 100], in: 344) == [[0], [1]])
        #expect(SavedChipCloud.lines([100, 400], in: 344) == [[0], [1]])
    }

    @Test func chipWidthPadsAndCaps() {
        #expect(SavedChipCloud.chipWidth(textWidth: 40) == 59)
        #expect(SavedChipCloud.chipWidth(textWidth: 40.2) == 60)
        #expect(SavedChipCloud.chipWidth(textWidth: 500) == SavedChipCloud.maxChipWidth)
        #expect(SavedChipCloud.maxChipWidth == 168)
    }

    @Test func nothingSavedIsAnEmptyCloud() {
        let empty = cloud(SavedSearches())
        #expect(empty.chips.isEmpty)
        #expect(empty.lines.isEmpty)
        #expect(!empty.scrolls)
    }

    /// Six 100pt chips fill two lines exactly: no "+N".
    @Test func everythingShowsWhenItFitsTwoLines() {
        let saved = searches(6)
        let c = cloud(saved)
        #expect(c.chips == saved.items.map(SavedChipCloud.Chip.saved))
        #expect(c.lines.count == 2)
        #expect(c.firstHidden == nil)
    }

    /// The last slot of the second line becomes "+N" when the rest don't fit.
    @Test func overflowEndsTheSecondLineWithPlusN() {
        let saved = searches(8)
        let c = cloud(saved)
        #expect(c.chips == saved.items.prefix(5).map(SavedChipCloud.Chip.saved) + [.more(.hidden(3))])
        #expect(c.lines.count == 2)
        #expect(c.lines.last?.last == .more(.hidden(3)))
        #expect(c.firstHidden == saved.items[5])
        #expect(c.chips.map(\.item).last == .more)
        #expect(c.chips.first?.item == .saved(saved.items[0].id))
    }

    /// "+N" is narrower than a chip, so it can fit where the next chip doesn't, and its width counts.
    @Test func plusNUsesItsOwnWidth() {
        let saved = searches(8)
        let c = SavedChipCloud(saved: saved, expanded: false, width: 344) { chip in
            if case .more = chip { 30 } else { 100 }
        }
        // Line 2: three chips (312) + 6 + 30 = 348 doesn't fit; two chips and +N do.
        #expect(c.chips.last == .more(.hidden(3)))
        #expect(c.chips.count == 6)
        let narrow = SavedChipCloud(saved: saved, expanded: false, width: 350) { chip in
            if case .more = chip { 30 } else { 100 }
        }
        #expect(narrow.chips == saved.items.prefix(6).map(SavedChipCloud.Chip.saved) + [.more(.hidden(2))])
    }

    @Test func expandedShowsEverySearchThenShowLess() {
        let saved = searches(8)
        let c = cloud(saved, expanded: true)
        #expect(c.chips == saved.items.map(SavedChipCloud.Chip.saved) + [.more(.showLess)])
        #expect(c.lines.count == 3)
        #expect(c.firstHidden == nil)
        #expect(!c.scrolls)
    }

    /// Expanded with nothing hidden (a search was deleted) is just the cloud, no "Show less".
    @Test func expandedWithNothingHiddenHasNoShowLess() {
        let saved = searches(4)
        #expect(cloud(saved, expanded: true) == cloud(saved, expanded: false))
    }

    @Test func expandedScrollsPastFiveLines() {
        let c = cloud(searches(20), expanded: true)
        #expect(c.lines.count == 7)
        #expect(c.scrolls)
        #expect(SavedChipCloud.expandedHeight == 144)
        #expect(!cloud(searches(14), expanded: true).scrolls)
    }

    /// Chips wider than a line still collapse to two lines: one chip each, then +N on a line's end
    /// where it fits.
    @Test func overwideChipsCollapseToTwoLines() {
        let saved = searches(5)
        let c = SavedChipCloud(saved: saved, expanded: false, width: 344) { chip in
            if case .more = chip { 30 } else { 300 }
        }
        #expect(c.lines.count == 2)
        #expect(c.chips == saved.items.prefix(2).map(SavedChipCloud.Chip.saved) + [.more(.hidden(3))])
    }

    @Test func plusNNeverStandsAlone() {
        // One overwide chip per line and no room for +N beside any: the first line keeps a chip.
        let saved = searches(3)
        let c = SavedChipCloud(saved: saved, expanded: false, width: 344) { _ in 344 }
        #expect(c.lines.count == 2)
        #expect(c.chips == [.saved(saved.items[0]), .more(.hidden(2))])
    }

    /// The ⌃N key is measured into the chip, so a keyed chip is wider and the cloud wraps by it.
    @Test func measureIncludesKey() {
        let keyed = SavedChipCloud.chipWidth(textWidth: 40, keyWidth: 14)
        #expect(keyed > SavedChipCloud.chipWidth(textWidth: 40))
        #expect(keyed == 59 + SavedChipCloud.keyGap + 14)
        #expect(SavedChipCloud.chipWidth(textWidth: 500, keyWidth: 14) == SavedChipCloud.maxChipWidth)
        // Three 100pt chips fit a 312pt line; with a 14pt key each, only two do.
        let saved = searches(3)
        let plain = SavedChipCloud(saved: saved, expanded: false, width: 312) { _ in
            SavedChipCloud.chipWidth(textWidth: 100 - 19)
        }
        let withKeys = SavedChipCloud(saved: saved, expanded: false, width: 312) { _ in
            SavedChipCloud.chipWidth(textWidth: 100 - 19, keyWidth: 14)
        }
        #expect(plain.lines.map(\.count) == [3])
        #expect(withKeys.lines.map(\.count) == [2, 1])
    }
}
