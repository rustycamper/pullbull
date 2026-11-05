import Foundation

/// What a key pressed with the merge panel open does.
public enum MergeKeyAction: Equatable, Sendable {
    /// ⌃⌘↩: confirm, which the model refuses while the panel is disarmed.
    case confirm
    /// ⌥← (-1) or ⌥→ (1): the previous or next method.
    case changeMethod(Int)
    /// Esc: close the panel.
    case close
    /// Anything else: taken, and nothing happens.
    case swallow
}

/// Key routing while the merge panel is open. ⌘W, ⌘, and ⌘/ never reach this: PopoverView handles them first.
public enum MergePanelKeys {
    private static let returnKey: UInt16 = 36
    private static let keypadEnter: UInt16 = 76
    private static let escape: UInt16 = 53
    private static let left: UInt16 = 123
    private static let right: UInt16 = 124

    /// With the panel open, every key is taken: ⌘↩ and plain ↩ do nothing, so they can't reach the field or open GitHub.
    /// keyCode is the virtual key; flags exclude caps lock, numeric pad and function. A held key's repeat does nothing.
    public static func route(keyCode: UInt16, flags: KeyCombo.Modifiers, isRepeat: Bool) -> MergeKeyAction {
        guard !isRepeat else { return .swallow }
        switch keyCode {
        case returnKey, keypadEnter: return flags == [.control, .command] ? .confirm : .swallow
        case left: return flags == [.option] ? .changeMethod(-1) : .swallow
        case right: return flags == [.option] ? .changeMethod(1) : .swallow
        case escape: return flags.isEmpty ? .close : .swallow
        default: return .swallow
        }
    }
}
