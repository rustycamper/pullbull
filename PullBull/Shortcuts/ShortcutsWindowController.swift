import AppKit
import PullBullKit
import SwiftUI

/// The Keyboard Shortcuts window: ⌘/ in the popover, or Settings → General. A window rather than
/// the popover, so it stays up beside it.
@MainActor
final class ShortcutsWindowController: NSObject, NSWindowDelegate {
    static let shared = ShortcutsWindowController()

    private var window: NSWindow?

    /// Opens the window, or brings it to the front with the toggle shortcut as it is now.
    func show(app: AppModel) {
        let sections = ShortcutCatalog.sections(toggle: app.settings.toggleHotkey?.localizedKeycaps)
        let window = self.window ?? makeWindow()
        if !window.isVisible {
            let hosting = NSHostingController(rootView: ShortcutsView(sections: sections) { [weak self] in
                self?.close()
            })
            hosting.sizingOptions = .preferredContentSize
            window.contentViewController = hosting
            window.center()
        }
        self.window = window
        SettingsOpener.forceActivate()
        window.orderFrontRegardless()
        window.makeKey()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = ShortcutsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}

/// ⌘W and ⌘/ (or ⌘?, the same key shifted) close it. PullBull has no menu bar while only this window
/// is open, so no Close item answers ⌘W.
private final class ShortcutsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if (flags == .command && key == "w") || ShortcutsWindowController.isOpenKey(event) {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension ShortcutsWindowController {
    /// ⌘/, or ⌘? where "/" is a shifted key or the user holds ⇧: by character, so it follows the layout.
    static func isOpenKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function, .shift])
        let key = event.charactersIgnoringModifiers
        return flags == .command && (key == "/" || key == "?")
    }
}
