import SwiftUI
import PullBullKit

/// The Pull Requests / Issues switch at the start of the search row: two icon segments on one track, as
/// tall as the field beside it, the active one in the accent colour on a tinted chip, so it reads without
/// hue too (a Graphite accent, Differentiate Without Colour). The track groups the two icons and sets them
/// apart from the field. The other mode's glyph carries a dot while it has something new for me
/// (`ModeNews`).
struct ModeToggle: View {
    @Bindable var model: AppModel
    /// Switches to the mode, as ⌘1 / ⌘2 do: a query in the field stays, an empty open field closes.
    let select: (PopoverMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopoverMode.allCases, id: \.self) { mode in
                ModeButton(
                    mode: mode, selected: model.mode == mode,
                    news: model.mode == mode ? nil : model.modeNews.note(mode)
                ) { select(mode) }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode")
    }
}

private struct ModeButton: View {
    let mode: PopoverMode
    let selected: Bool
    /// "1 newly assigned": what's new in this mode while another is on screen; nil with nothing new.
    let news: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var contrast

    /// 20pt tall inside the 24pt track; its radius nests inside the track's 6.
    private static let chip = RoundedRectangle(cornerRadius: 5)

    var body: some View {
        Button(action: action) {
            Image(symbol: mode.symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 20)
                .background(Self.chip.fill(fill))
                .overlay {
                    // Increase Contrast edges the chosen chip too.
                    if selected, contrast == .increased { Self.chip.strokeBorder(Color.accentColor, lineWidth: 1) }
                }
                .overlay(alignment: .topTrailing) {
                    if news != nil {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .offset(x: -3, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(news.map { "\(mode.help) · \($0)" } ?? mode.help)
        .accessibilityLabel(mode.title)
        .accessibilityValue(news ?? "")
        .accessibilityHint(mode.shortcut)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var fill: Color {
        if selected { return Palette.selection }
        // The track is `Palette.fill`, so a hover takes the stronger fill to show on it.
        return hovering ? Palette.strongFill : .clear
    }
}

extension PopoverMode {
    var title: String {
        switch self {
        case .pullRequests: "Pull Requests"
        case .issues: "Issues"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests: "pullbull.pullrequest"
        case .issues: "pullbull.issue"
        }
    }

    var shortcut: String {
        switch self {
        case .pullRequests: "⌘1"
        case .issues: "⌘2"
        }
    }

    var help: String { "\(title) (\(shortcut))" }
}
