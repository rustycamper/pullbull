import AppKit

/// A key-down monitor for the popover window, installed while the popover is visible. `handler` returns
/// true to consume the event; events for other windows always pass through.
@MainActor
final class SearchKeyMonitor {
    private var monitor: Any?
    private(set) weak var window: NSWindow?

    func install(on window: NSWindow, handler: @escaping @MainActor (NSEvent, NSWindow) -> Bool) {
        remove()
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread; the event never leaves it.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated {
                guard let window = self?.window, event.window === window else { return false }
                return handler(event, window)
            }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window = nil
    }

    /// The typed text when the event is a printable character without ⌘ or ⌃, else nil.
    static func printableText(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .control, .function]),
              let text = event.characters, !text.isEmpty else { return nil }
        let printable = text.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !(0xF700...0xF8FF).contains(scalar.value)  // arrows, function keys
        }
        return printable ? text : nil
    }

    static let escape: UInt16 = 53
    static let `return`: UInt16 = 36
    static let enter: UInt16 = 76
    static let tab: UInt16 = 48
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    /// kVK_ANSI_1 and kVK_ANSI_2: the keys in the 1 and 2 position, whatever they type.
    static let digit1: UInt16 = 18
    static let digit2: UInt16 = 19
    /// kVK_ANSI_F, kVK_ANSI_R, kVK_ANSI_C and kVK_ANSI_LeftBracket: used for ⌘F, ⌘R, ⌘C and ⌘[ only when
    /// the layout types no Latin character there (e.g. Russian).
    static let letterF: UInt16 = 3
    static let letterR: UInt16 = 15
    static let letterC: UInt16 = 8
    static let leftBracket: UInt16 = 33
    /// kVK_ANSI_W: used for ⌘W only when the layout types no Latin character there.
    static let letterW: UInt16 = 13
    /// kVK_ANSI_B: used for ⌘⇧B only when the layout types no Latin character there.
    static let letterB: UInt16 = 11
}
