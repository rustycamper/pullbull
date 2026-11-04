import AppKit
import PullBullKit

/// The app menu (`AppMenuEntry.entries`), for the footer gear and the menu bar item's right-click. A pick
/// runs on the next turn of the main loop, once the menu has closed, so a window it opens isn't put
/// behind the closing menu or the popover.
@MainActor
final class AppMenu: NSObject {
    /// The menu on screen keeps its item target alive; menu items hold their target weakly, and an item's
    /// action may be delivered after tracking ends.
    private static var active: AppMenu?

    let menu = NSMenu()
    private let model: AppModel
    private var entries: [AppMenuEntry] = []

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.autoenablesItems = false
        let updater = Updater.shared
        for entry in AppMenuEntry.entries(updatesAvailable: updater.isAvailable) {
            guard let title = entry.title else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: entry.keyEquivalent)
            item.target = self
            item.tag = entries.count
            // Disabled while Sparkle is busy; Stats has no window yet.
            item.isEnabled = (entry != .checkForUpdates || updater.canCheckForUpdates) && entry != .stats
            entries.append(entry)
            menu.addItem(item)
        }
    }

    /// Pops the menu up above `view`, right edges aligned: the gear sits at the footer's trailing end.
    static func show(model: AppModel, above view: NSView) {
        let appMenu = AppMenu(model: model)
        let size = appMenu.menu.size
        track(appMenu) {
            appMenu.menu.popUp(
                positioning: nil, at: NSPoint(x: view.bounds.width - size.width, y: -size.height - 4), in: view)
        }
    }

    /// Keeps `appMenu` alive while `present` shows it, and one turn longer for a late action.
    static func track(_ appMenu: AppMenu, while present: () -> Void) {
        active = appMenu
        present()
        DispatchQueue.main.async { if active === appMenu { active = nil } }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard entries.indices.contains(sender.tag) else { return }
        let entry = entries[sender.tag]
        DispatchQueue.main.async { [model] in Self.perform(entry, model: model) }
    }

    private static func perform(_ entry: AppMenuEntry, model: AppModel) {
        switch entry {
        case .settings: SettingsOpener.open()
        case .shortcuts: ShortcutsWindowController.shared.show(app: model)
        case .about:
            // As for Settings: a plain activate() is refused, and the panel would open behind the front app.
            SettingsOpener.forceActivate()
            NSApp.orderFrontStandardAboutPanel(nil)
        case .checkForUpdates: Updater.shared.checkForUpdates()
        case .quit: NSApp.terminate(nil)
        case .stats, .separator: break
        }
    }
}
