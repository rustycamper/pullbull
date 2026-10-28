import AppKit
import PullBullKit
import SwiftUI

/// The "Set Up GitHub CLI" window. A window rather than the popover, which closes when Terminal takes
/// focus.
@MainActor
final class GhSetupWindowController: NSObject, NSWindowDelegate {
    static let shared = GhSetupWindowController()

    private var window: NSWindow?
    private var model: GhSetupModel?

    func show(app: AppModel, purpose: GhSetupChecklist.Purpose) {
        if let window, window.isVisible, model?.purpose == purpose {
            bringToFront(window)
            model?.checkNow()
            return
        }
        model?.stop()
        let model = GhSetupModel(app: app, purpose: purpose)
        self.model = model
        let view = GhSetupView(model: model, app: app) { [weak self] in self?.close() }

        let window = self.window ?? makeWindow()
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = .preferredContentSize
        window.contentViewController = hosting
        if !window.isVisible { window.center() }
        self.window = window

        model.start()
        bringToFront(window)
    }

    /// As the sign-in window: in front of the app that is, with keyboard focus.
    private func bringToFront(_ window: NSWindow) {
        SettingsOpener.forceActivate()
        window.orderFrontRegardless()
        window.makeKey()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.stop()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Set Up GitHub CLI"
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
