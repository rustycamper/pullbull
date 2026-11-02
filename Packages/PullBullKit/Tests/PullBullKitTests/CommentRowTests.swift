import Testing
@testable import PullBullKit

@Suite struct CommentRowTests {
    @Test func emptyAndUnfocusedTheHintIsTheFocusShortcut() {
        #expect(CommentRow.hint(focused: false, sending: false, hasDraft: false) == "⌥⌘M")
    }

    @Test func aWaitingDraftHasNoHintUnfocused() {
        #expect(CommentRow.hint(focused: false, sending: false, hasDraft: true) == nil)
    }

    @Test func focusedTheHintIsTheSendShortcut() {
        #expect(CommentRow.hint(focused: true, sending: false, hasDraft: false) == "⌘↩")
        #expect(CommentRow.hint(focused: true, sending: false, hasDraft: true) == "⌘↩")
    }

    @Test func sendingShowsInTheHintFocusedOrNot() {
        #expect(CommentRow.hint(focused: true, sending: true, hasDraft: true) == "Sending…")
        #expect(CommentRow.hint(focused: false, sending: true, hasDraft: true) == "Sending…")
    }

    @Test func previewIsTheFirstLineWithText() {
        #expect(CommentRow.preview(of: "") == nil)
        #expect(CommentRow.preview(of: " \n\t\n") == nil)
        #expect(CommentRow.preview(of: "LGTM") == "LGTM")
        #expect(CommentRow.preview(of: "\n  \nFirst line\nsecond") == "First line")
        #expect(CommentRow.preview(of: "  indented\r\nnext") == "  indented")
    }

    @Test func unfocusedValueNamesTheDraft() {
        #expect(CommentRow.unfocusedValue(of: "") == nil)
        #expect(CommentRow.unfocusedValue(of: "\n \n") == nil)
        #expect(CommentRow.unfocusedValue(of: "\n  Looks good\nThanks") == "Draft: Looks good")
    }
}
