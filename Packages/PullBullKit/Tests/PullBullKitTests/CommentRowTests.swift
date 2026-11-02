import Testing
@testable import PullBullKit

@Suite struct CommentRowTests {
    @Test func unfocusedShowsTheSecondaryButtonAndNoCommentButton() {
        let row = CommentRow(focused: false, sending: false)
        #expect(!row.showsCommentButton)
        #expect(row.showsSecondaryButton)
    }

    @Test func focusedTheCommentButtonTakesTheSecondaryButtonsPlace() {
        let row = CommentRow(focused: true, sending: false)
        #expect(row.showsCommentButton)
        #expect(!row.showsSecondaryButton)
        #expect(CommentRow(focused: true, sending: true) == row)
    }

    @Test func sendingUnfocusedKeepsBothInView() {
        let row = CommentRow(focused: false, sending: true)
        #expect(row.showsCommentButton)
        #expect(row.showsSecondaryButton)
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
