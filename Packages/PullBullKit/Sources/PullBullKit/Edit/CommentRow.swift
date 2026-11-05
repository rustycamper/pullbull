import Foundation

/// How a detail's comment field reads at its trailing end, and how the unfocused field reads a draft.
/// There is no Comment button: typing needs the keyboard, so ⌘↩ is always to hand, and the hint says so.
public enum CommentRow {
    /// The hint at the field's trailing end: "Checking…" while a review's head is read, then "Sending…"
    /// while a post is in flight, focused or not; focused, the shortcut that posts; unfocused and empty,
    /// the one that focuses. A waiting draft's preview takes the whole field unfocused, so it has none.
    public static func hint(focused: Bool, sending: Bool, hasDraft: Bool, checking: Bool = false) -> String? {
        if checking { return "Checking…" }
        if sending { return "Sending…" }
        if focused { return "⌘↩" }
        return hasDraft ? nil : "⌥⌘M"
    }

    /// The review field's placeholder; Request changes needs text, so it says what.
    public static func reviewPlaceholder(_ verdict: ReviewVerdict) -> String {
        switch verdict {
        case .approve: "Add a note (optional)…"
        case .requestChanges: "Say what needs changing…"
        }
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
