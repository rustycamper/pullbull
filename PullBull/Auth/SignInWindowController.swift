import AppKit
import PullBullKit
import SwiftUI

@MainActor
final class SignInWindowController: NSObject, NSWindowDelegate {
    static let shared = SignInWindowController()

    private static let autoCloseDelay = Duration.milliseconds(1500)

    private var window: NSWindow?
    private var model: SignInModel?
    private var autoClose: Task<Void, Never>?

    /// `checkApproval` re-reads the org's installations from the needs-approval state; true closes the
    /// window as a ready sign-in does. `app` drives the personal install step.
    func show(
        app: AppModel,
        complete: @escaping @MainActor (TokenGrant) async -> SignInOutcome,
        checkApproval: @escaping @MainActor () async -> Bool
    ) {
        model?.cancel()
        autoClose?.cancel()

        let model = SignInModel(
            config: GitHubAppConfig.current,
            complete: { [weak self] grant in
                let outcome = await complete(grant)
                if case .ready = outcome, !Task.isCancelled { self?.scheduleClose() }
                return outcome
            },
            checkApproval: { [weak self] in
                let approved = await checkApproval()
                if approved { self?.scheduleClose() }
                return approved
            })
        self.model = model
        let view = SignInView(
            model: model, app: app, onClose: { [weak self] in self?.close() },
            onInstalled: { [weak self] in self?.scheduleClose() })

        let window = self.window ?? makeWindow()
        let hosting = NSHostingController(rootView: view)
        // The personal install step is taller than the sign-in states; the window follows its content.
        hosting.sizingOptions = .preferredContentSize
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 360, height: 300))
        if !window.isVisible { window.center() }
        self.window = window

        model.start()
        bringToFront(window)
    }

    /// PullBull is an accessory app, usually inactive when this opens, and since macOS 14 a plain
    /// `NSApp.activate()` is refused while another app is in front, which left the window behind it.
    /// `orderFrontRegardless` puts it above the other app's windows even if activation is refused, and
    /// the forced activation (the same one Settings uses) gives it keyboard focus.
    private func bringToFront(_ window: NSWindow) {
        SettingsOpener.forceActivate()
        window.orderFrontRegardless()
        window.makeKey()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model?.cancel()
        autoClose?.cancel()
        autoClose = nil
    }

    private func scheduleClose() {
        autoClose?.cancel()
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: Self.autoCloseDelay)
            if Task.isCancelled { return }
            self?.close()
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Sign in to GitHub"
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
