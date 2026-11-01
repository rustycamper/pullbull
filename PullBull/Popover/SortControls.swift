import AppKit
import SwiftUI
import PullBullKit

/// The filter bar's sort control, on its right end: ⇅ alone while the tab is on its default (Recently
/// updated), ⇅ and the choice's name in the accent colour otherwise, so a changed order is never hidden.
/// It opens `SortMenu` for the tab the list or results are laid out for (`AppModel.sortTab`).
struct SortButton: View {
    let model: AppModel
    @State private var anchor = MenuAnchor()

    var body: some View {
        let sort = model.sort
        let changed = sort != .recentlyUpdated
        Button { show() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .medium))
                if changed {
                    Text(sort.title)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(changed ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .background(MenuAnchorView(anchor: anchor))
        .help("Sort: \(sort.title)")
        .accessibilityLabel("Sort: \(sort.title)")
    }

    private func show() {
        guard let view = anchor.view else { return }
        SortMenu.show(model: model, in: view)
    }
}

/// The sort button's menu: the tab's choices, the current one checked and positioned over the button.
@MainActor
enum SortMenu {
    /// The menu on screen keeps its item target alive; menu items hold their target weakly.
    private static var activeTarget: MenuActionTarget?

    static func show(model: AppModel, in view: NSView) {
        let target = MenuActionTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        var positioned: NSMenuItem?
        for choice in model.sortChoices {
            let item = target.item(title: choice.title) { model.setSort(choice) }
            item.state = choice == model.sort ? .on : .off
            if choice == model.sort { positioned = item }
            menu.addItem(item)
        }
        activeTarget = target
        menu.popUp(positioning: positioned, at: .zero, in: view)
        // An item's action may be delivered after tracking ends; the target outlives it by a turn.
        DispatchQueue.main.async { if activeTarget === target { activeTarget = nil } }
    }
}

/// "Sort By" on a list's context menus, after Show Only Updated: the tab's choices with a checkmark on
/// the current one.
struct SortByMenu: View {
    let model: AppModel

    var body: some View {
        Menu("Sort By", systemImage: "arrow.up.arrow.down") {
            ForEach(model.sortChoices, id: \.self) { choice in
                Toggle(choice.title, isOn: Binding(
                    get: { model.sort == choice },
                    set: { _ in model.setSort(choice) }))
            }
        }
    }
}
