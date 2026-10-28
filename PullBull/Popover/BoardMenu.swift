import AppKit
import Observation
import PullBullKit

/// The Board tab's board menu: the owner's boards with the chosen one checked, or one line while they
/// load, when there are none, or when they couldn't load. Type-select works on the names. Opening it
/// loads the list if needed, and the open menu is rebuilt in place when the list lands.
@MainActor
final class BoardMenu {
    /// The menu on screen keeps its items' target alive; menu items hold their target weakly.
    private static var active: BoardMenu?

    private let model: AppModel
    private let menu = NSMenu()
    private var target = MenuActionTarget()
    private var isOpen = true

    private init(model: AppModel) {
        self.model = model
        menu.autoenablesItems = false
    }

    /// Pops the menu up in `view` at `point`, with the chosen board positioned there; with none (or
    /// while loading), the menu's top left is at `point`.
    static func show(model: AppModel, in view: NSView, at point: NSPoint) {
        let presenter = BoardMenu(model: model)
        model.loadBoardListIfNeeded()
        presenter.rebuild()
        presenter.followList()
        active = presenter
        let positioned = presenter.menu.items.first { $0.state == .on }
        presenter.menu.popUp(positioning: positioned, at: point, in: view)
        presenter.isOpen = false
        // An item's action may be delivered after tracking ends; the target outlives it by a turn.
        DispatchQueue.main.async { if active === presenter { active = nil } }
    }

    private func rebuild() {
        target = MenuActionTarget()
        menu.removeAllItems()
        for entry in model.boardMenuItems {
            switch entry {
            case .board(let board, let label, let isCurrent):
                let item = target.item(title: label) { [model] in model.chooseBoard(board) }
                item.state = isCurrent ? .on : .off
                menu.addItem(item)
            case .loading, .empty:
                menu.addItem(disabled(entry.title))
            case .failed(let message):
                let item = disabled(entry.title)
                item.toolTip = message
                menu.addItem(item)
            }
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Rebuilds the items each time the list changes while the menu is open.
    private func followList() {
        withObservationTracking {
            _ = model.boardMenuItems
        } onChange: { [weak self] in
            // Called before the change lands; the rebuild reads it on the next turn.
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                self.rebuild()
                self.followList()
            }
        }
    }
}
