import Testing
@testable import PullBullKit

@Suite struct EmptyListFrameTests {
    @Test func withoutASectionTheGlyphStaysWhereEveryTabDrawsIt() {
        #expect(EmptyListFrame.height(below: .nothing, viewport: 470) == 400)
        #expect(EmptyListFrame.height(below: .nothing, viewport: 900) == 400)
    }

    @Test func aFoldedSectionSitsAtTheBottomOfTheViewport() {
        // Recently closed: 6pt gap, hairline, 28pt header, the list's 6pt bottom padding.
        #expect(EmptyListFrame.height(below: .folded(height: 41), viewport: 470) == 429)
        // Done: header and padding only.
        #expect(EmptyListFrame.height(below: .folded(height: 34), viewport: 470) == 436)
    }

    @Test func aFoldedSectionNeverSqueezesTheEmptyStateBelowItsFloor() {
        #expect(EmptyListFrame.height(below: .folded(height: 41), viewport: 200) == 260)
        #expect(EmptyListFrame.height(below: .folded(height: 41), viewport: 0) == 260)
    }

    @Test func anOpenSectionLeavesTheEmptyStateItsOwnHeight() {
        #expect(EmptyListFrame.height(below: .open, viewport: 470) == nil)
    }
}
