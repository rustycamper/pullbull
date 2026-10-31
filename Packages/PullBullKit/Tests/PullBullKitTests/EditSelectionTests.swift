import Testing
@testable import PullBullKit

private let k1 = editKey(1)
private let k2 = editKey(2)
private let k3 = editKey(3)

@Suite struct EditSelectionTests {
    @Test func aSelectedRowThatStaysIsScrolledTo() {
        var s = EditSelection()
        #expect(s.follow(k2, selection: k2, from: [k1, k2, k3], to: [k1, k3, k2]) == .scroll)
    }

    @Test func aSelectedRowThatLeavesSelectsTheNext() {
        var s = EditSelection()
        #expect(s.follow(k2, selection: k2, from: [k1, k2, k3], to: [k1, k3]) == .select(k3))
    }

    /// The edit moved the row into a folded lane; its undo (or failure) brings it back, and the
    /// selection with it.
    @Test func theRowComingBackIsSelectedAgain() {
        var s = EditSelection()
        _ = s.follow(k2, selection: k2, from: [k1, k2, k3], to: [k1, k3])
        #expect(s.follow(k2, selection: k3, from: [k1, k3], to: [k1, k2, k3]) == .select(k2))
    }

    @Test func notAfterTheSelectionMoved() {
        var s = EditSelection()
        _ = s.follow(k2, selection: k2, from: [k1, k2, k3], to: [k1, k3])
        #expect(s.follow(k2, selection: k1, from: [k1, k3], to: [k1, k2, k3]) == .none)
    }

    @Test func anotherRowsEditLeavesTheSelection() {
        var s = EditSelection()
        #expect(s.follow(k2, selection: k1, from: [k1, k2, k3], to: [k1, k3]) == .none)
    }

    @Test func onlyOnce() {
        var s = EditSelection()
        _ = s.follow(k2, selection: k2, from: [k1, k2, k3], to: [k1, k3])
        _ = s.follow(k2, selection: k3, from: [k1, k3], to: [k1, k2, k3])
        #expect(s.follow(k2, selection: k3, from: [k1, k3], to: [k1, k2, k3]) == .none)
    }
}
