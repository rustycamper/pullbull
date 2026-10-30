import Testing
@testable import PullBullKit

@Suite struct SearchArrowsTests {
    private func moves(
        _ offset: Int, focused: Bool = true, caret: Int? = 5, length: Int = 5, completion: Bool = false,
        isRepeat: Bool = false
    ) -> Bool {
        SearchArrows.movesScope(
            offset: offset, fieldFocused: focused, caret: caret, length: length, completionOpen: completion,
            isRepeat: isRepeat)
    }

    @Test func rightAtEndMoves() {
        #expect(moves(1, caret: 5))
        #expect(!moves(1, caret: 3))
    }

    @Test func leftAtStartMoves() {
        #expect(moves(-1, caret: 0))
        #expect(!moves(-1, caret: 5))
    }

    @Test func arrowsStayInFieldWhileEditing() {
        #expect(!moves(1, caret: nil))
        #expect(!moves(-1, caret: nil))
        #expect(!moves(1, caret: 5, completion: true))
        #expect(!moves(-1, caret: 0, completion: true))
        #expect(!moves(1, caret: 5, isRepeat: true))
        #expect(!moves(-1, caret: 0, isRepeat: true))
    }

    @Test func unfocusedFieldMoves() {
        #expect(moves(1, focused: false, caret: nil))
        #expect(moves(-1, focused: false, caret: 2))
    }
}
