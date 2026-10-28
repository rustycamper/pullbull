import Testing
@testable import PullBullKit

@Suite struct PendingCaretTests {
    private let completed = "@alice foo"
    private let old = "@a foo"

    private var fresh: PendingCaret { PendingCaret(text: "@alice foo", caret: 7) }

    @Test func appliesAtTheHopWhenTheEditorCaughtUp() {
        var pending = fresh
        #expect(pending.afterHop(editorText: completed, searchText: completed) == .apply(7))
    }

    @Test func dropsAtTheHopWithoutAFieldEditor() {
        var pending = fresh
        #expect(pending.afterHop(editorText: nil, searchText: completed) == .drop)
    }

    @Test func dropsWhenTheSearchTextMovesOn() {
        var pending = fresh
        #expect(pending.selectionChanged(editorText: completed, searchText: "@alice fooz") == .drop)
        #expect(pending.afterHop(editorText: completed, searchText: "") == .drop)
    }

    @Test func editorLagsTheHopThenCatchesUp() {
        var pending = fresh
        // The field's own selection change on the old text, before the hop: waited out.
        #expect(pending.selectionChanged(editorText: old, searchText: completed) == .wait)
        #expect(pending.afterHop(editorText: old, searchText: completed) == .wait)
        #expect(pending.hopped)
        // The field takes the new text: the next selection change applies.
        #expect(pending.selectionChanged(editorText: completed, searchText: completed) == .apply(7))
    }

    @Test func afterTheHopTheFirstOtherChangeDrops() {
        var pending = fresh
        #expect(pending.afterHop(editorText: old, searchText: completed) == .wait)
        #expect(pending.selectionChanged(editorText: old, searchText: completed) == .drop)
    }

    @Test func aSecondHopNeverWaits() {
        var pending = fresh
        #expect(pending.afterHop(editorText: old, searchText: completed) == .wait)
        #expect(pending.afterHop(editorText: old, searchText: completed) == .drop)
    }
}
