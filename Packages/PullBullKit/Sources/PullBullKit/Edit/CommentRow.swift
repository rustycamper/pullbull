import Foundation

/// What a detail's bottom row shows beside the comment field: the Comment button, the item's own buttons
/// (Copy branch or View on board, and Open on GitHub), and how the unfocused field reads a draft.
public struct CommentRow: Equatable, Sendable {
    /// While the field has focus, and while a post is sending, so "Sending…" stays in view.
    public let showsCommentButton: Bool
    /// Hidden only while the field has focus, never because a draft waits, so Open on GitHub stays a click
    /// away.
    public let showsItemButtons: Bool

    public init(focused: Bool, sending: Bool) {
        showsCommentButton = focused || sending
        showsItemButtons = !focused
    }

    /// The draft's first line with text in it, which the unfocused field shows; nil when there's none.
    public static func preview(of draft: String) -> String? {
        draft.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(String.init)
    }

    /// VoiceOver's value for the unfocused field: "Draft: " and the line it shows; nil with no draft.
    public static func unfocusedValue(of draft: String) -> String? {
        preview(of: draft).map { "Draft: \($0.trimmingCharacters(in: .whitespaces))" }
    }
}
