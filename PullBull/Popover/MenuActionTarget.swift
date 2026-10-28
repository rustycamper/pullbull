import AppKit

/// The target of a popover menu's items: each item's tag indexes the closure it runs.
@MainActor
final class MenuActionTarget: NSObject {
    private var actions: [@MainActor () -> Void] = []

    func item(title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
        item.target = self
        item.tag = actions.count
        actions.append(action)
        return item
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}
