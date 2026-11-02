import Foundation

/// What a key pressed in the focused comment field does.
public enum CommentKeyAction: Equatable, Sendable {
    /// ⌘↩: post the draft.
    case post
    /// Esc with the mention list closed: leave the field, keeping the draft.
    case leaveField
    /// Esc with the mention list open: close it, keeping the typed text.
    case closeMentions
    /// ↑ (-1) or ↓ (1) in the open mention list.
    case moveMention(Int)
    /// Return or Tab in the open mention list: insert the highlighted person or team.
    case acceptMention
    /// The key belongs to the text view: typing, editing, caret moves, or nothing.
    case text
}

/// Key routing while the comment field has focus: the field owns the keyboard, so the detail's own
/// shortcuts (←, ⌥↑ ⌥↓, ⌘Z, ⌘R, ⌘[, ⌘C, ⌥⌘A/L/R/S/M…) act on the text or do nothing.
public enum CommentFieldKeys {
    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let tab: UInt16 = 48
    private static let escape: UInt16 = 53
    private static let down: UInt16 = 125
    private static let up: UInt16 = 126

    /// keyCode is the virtual key; flags exclude caps lock, numeric pad and function.
    /// ⌘W, ⌘, and ⌘/ never reach this: PopoverView handles them before `handleDetailKey`.
    public static func route(keyCode: UInt16, flags: KeyCombo.Modifiers,
                             mentionsOpen: Bool, composing: Bool) -> CommentKeyAction {
        // An input method composing keeps every key, as the search field does.
        guard !composing else { return .text }
        if flags == [.command], keyCode == returnKey || keyCode == keypadEnter { return .post }
        guard flags.isEmpty else { return .text }
        switch keyCode {
        case escape: return mentionsOpen ? .closeMentions : .leaveField
        case up where mentionsOpen: return .moveMention(-1)
        case down where mentionsOpen: return .moveMention(1)
        case returnKey where mentionsOpen, tab where mentionsOpen: return .acceptMention
        default: return .text
        }
    }
}
