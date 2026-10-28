import AppKit
import SwiftUI
import PullBullKit

@main
struct PullBullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { NotificationService.shared.install() }

    var body: some Scene {
        Settings {
            SettingsView(model: delegate.model)
        }
    }
}

/// Owns the model, so polling and the badge run from launch rather than from the first popover open,
/// and the status item with its popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var popover: PopoverController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let popover = PopoverController(model: model)
        self.popover = popover
        MenuBarPopover.install(popover)
        // A notification click that launched the app is waiting for the model.
        NotificationService.shared.attach(model)
        GlobalHotkey.shared.onPress = { MenuBarPopover.toggle() }
        GlobalHotkey.shared.apply(model.settings.toggleHotkey)
        Updater.shared.start()
        LaunchAtLogin.followInstalledCopy()
    }
}
