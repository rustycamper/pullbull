import AppKit
import SwiftUI

/// The footer's gear: opens the Settings window and brings it to the front
/// (an accessory app is not activated by `SettingsLink` alone).
struct SettingsGearButton: View {
    @State private var hovering = false

    var body: some View {
        SettingsLink {
            FooterGlyph(systemName: "gearshape")
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
        .onHover { hovering = $0 }
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
    }
}
