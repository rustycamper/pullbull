import AppKit
import SwiftUI

/// The footer's gear: opens the app menu (`AppMenu`) above it, with Settings and Keyboard Shortcuts first.
struct AppMenuButton: View {
    let model: AppModel
    @State private var hovering = false
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            AppMenu.show(model: model, above: view)
        } label: {
            FooterGlyph(systemName: "gearshape")
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchorView(anchor: anchor))
        .onHover { hovering = $0 }
        .help("Settings (⌘,), Keyboard Shortcuts (⌘/) and more")
        .accessibilityLabel("PullBull menu")
        .accessibilityHint("Settings, Keyboard Shortcuts, Stats, About, Check for Updates and Quit")
    }
}
