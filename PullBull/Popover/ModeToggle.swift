import SwiftUI
import PullBullKit

/// The Pull Requests / Issues switch at the start of the header: two free-standing icon buttons, the
/// active one in the accent colour. It has no track or thumb, so it doesn't read as part of the tab bar;
/// a hairline divider closes it off.
struct ModeToggle: View {
    @Bindable var model: AppModel
    /// Switches to the mode, as ⌘1 / ⌘2 do: a query in the field stays, an empty open field closes.
    let select: (PopoverMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PopoverMode.allCases, id: \.self) { mode in
                ModeButton(mode: mode, selected: model.mode == mode) { select(mode) }
            }
            Hairline(axis: .vertical)
                .frame(height: 18)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }
}

private struct ModeButton: View {
    let mode: PopoverMode
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(symbol: mode.symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 22, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering && !selected ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(mode.help)
        .accessibilityLabel(mode.title)
        .accessibilityHint(mode.shortcut)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
