import CoreGraphics
import Testing
@testable import PullBullKit

private let popover = CGSize(width: 400, height: 500)

@Suite struct StatusPickerPlacementTests {
    @Test func belowTheRowWhenItFits() {
        let frame = StatusPickerPlacement.frame(anchor: CGRect(x: 0, y: 100, width: 400, height: 20), height: 200, in: popover)
        #expect(frame == CGRect(x: 12, y: 124, width: 300, height: 200))
    }

    @Test func aboveTheRowWhenThereIsNoRoomBelow() {
        let frame = StatusPickerPlacement.frame(anchor: CGRect(x: 0, y: 400, width: 400, height: 20), height: 200, in: popover)
        #expect(frame.minY == 196)
    }

    /// Its measured height, not a guess: a short picker fits below a row a guess would have sent above.
    @Test func aShortPickerStaysBelowALowRow() {
        let frame = StatusPickerPlacement.frame(anchor: CGRect(x: 0, y: 350, width: 400, height: 20), height: 100, in: popover)
        #expect(frame.minY == 374)
    }

    /// Room neither below nor above: kept on screen, at the bottom.
    @Test func keptOnScreenWhenNeitherFits() {
        let frame = StatusPickerPlacement.frame(anchor: CGRect(x: 0, y: 200, width: 400, height: 20), height: 300, in: popover)
        #expect(frame.minY == 196)
        #expect(frame.maxY <= 496)
    }

    /// A row scrolled partly out of view at the top.
    @Test func aRowAboveTheTopKeepsThePickerOnScreen() {
        let frame = StatusPickerPlacement.frame(anchor: CGRect(x: 0, y: -60, width: 400, height: 20), height: 200, in: popover)
        #expect(frame.minY == 4)
    }

    @Test func tallerThanThePopoverIsCapped() {
        let frame = StatusPickerPlacement.frame(anchor: nil, height: 900, in: popover)
        #expect(frame.minY == 4)
        #expect(frame.height == 492)
    }

    @Test func narrowPopover() {
        let frame = StatusPickerPlacement.frame(
            anchor: CGRect(x: 200, y: 100, width: 100, height: 20), height: 200, in: CGSize(width: 250, height: 500))
        #expect(frame.width == 230)
        #expect(frame.minX == 10)
    }
}
