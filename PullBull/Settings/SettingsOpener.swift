import AppKit
import SwiftUI

/// Opens the Settings scene from code that isn't a SwiftUI view (the status item menu, ⌘, in the
/// popover). SwiftUI hands `openSettings` only to views, so a view in the status item passes it over.
@MainActor
enum SettingsOpener {
    private static var openSettings: OpenSettingsAction?

    static func open() {
        becomeRegularApp()
        if let openSettings {
            openSettings()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    /// From the Settings view's `onAppear`, whichever way it was opened (including `SettingsLink`).
    static func settingsDidAppear() {
        becomeRegularApp()
        // The window is not in `NSApp.windows` until this appearance has finished.
        DispatchQueue.main.async {
            forceActivate()
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// From the Settings view's `onDisappear`: back to a menu bar app, with no Dock icon. Switching while
    /// PullBull is active swaps the whole menu bar at once, so focus goes back to the previous app first
    /// (as closing a menu bar app's last window does) and the switch waits until PullBull is inactive.
    /// While another PullBull window is open (the sign-in window showing a device code), PullBull isn't
    /// hidden: the switch just waits until the user leaves PullBull.
    static func settingsDidDisappear() {
        guard NSApp.isActive else {
            NSApp.setActivationPolicy(.accessory)
            return
        }
        stopWaitingToResign()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                stopWaitingToResign()
                // Settings may have been opened again in the meantime.
                if settingsWindow == nil { NSApp.setActivationPolicy(.accessory) }
            }
        }
        if !otherWindowVisible { NSApp.hide(nil) }
    }

    /// A titled PullBull window other than Settings is on screen, such as the sign-in window. The popover
    /// and the status item's window are untitled.
    private static var otherWindowVisible: Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
                && window.identifier?.rawValue.contains("Settings") != true
        }
    }

    private static var resignObserver: (any NSObjectProtocol)?

    private static func stopWaitingToResign() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// Since macOS 14 the system refuses `NSApp.activate()` unless the user just clicked one of the app's
    /// windows, so ⌘, and the status item menu leave Settings behind the front app. PullBull becomes a
    /// regular app (Dock icon, app menu, ⌘-Tab) while Settings is open and asks to be activated outright.
    private static func becomeRegularApp() {
        stopWaitingToResign()
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        forceActivate()
    }

    /// `activate(ignoringOtherApps: true)`, deprecated since macOS 14 but still the only request the
    /// system honors here. Called through the runtime so the deprecation doesn't warn on every build.
    /// The sign-in window uses it too.
    static func forceActivate() {
        typealias Activate = @convention(c) (NSApplication, Selector, Bool) -> Void
        let selector = NSSelectorFromString("activateIgnoringOtherApps:")
        guard NSApp.responds(to: selector) else {
            NSApp.activate()
            return
        }
        unsafeBitCast(NSApp.method(for: selector), to: Activate.self)(NSApp, selector, true)
    }

    private static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true && $0.isVisible }
    }

    fileprivate static func register(_ action: OpenSettingsAction) { openSettings = action }
}

/// Invisible; place it in a view that exists from launch so `SettingsOpener` has the action.
struct SettingsOpenerAnchor: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { SettingsOpener.register(openSettings) }
    }
}
