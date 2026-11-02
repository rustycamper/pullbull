import Foundation

/// What a detail's bottom row shows beside the comment field: the Comment button, the item's second
/// button (Copy branch or View on board), and how the unfocused field reads a draft. Open on GitHub is
/// always there, last.
public struct CommentRow: Equatable, Sendable {
    /// While the field has focus, and while a post is sending, so "Sending…" stays in view.
    public let showsCommentButton: Bool
    /// Gives way to the Comment button only while the field has focus, never because a draft waits.
    public let showsSecondaryButton: Bool

    public init(focused: Bool, sending: Bool) {
        showsCommentButton = focused || sending
        showsSecondaryButton = !focused
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
