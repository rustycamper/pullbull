import AppKit
import SwiftUI
import PullBullKit

/// The panel under the empty search field, drawn over the top of the current list: the saved searches as a cloud of
/// chips (`SavedChipCloud`), one line of syntax tokens, and a caption explaining the selected item. A
/// saved chip applies its search, "+N" expands the cloud and "Show less" folds it, and a token types its
/// sigil into the field. Its height changes only when searches are saved or deleted or the cloud expands.
struct SearchHints: View {
    let model: AppModel
    /// Built by `cloud(saved:expanded:)`, which the popover's keys use too.
    let cloud: SavedChipCloud
    /// "+N" expanded the cloud.
    let expanded: Bool
    /// Highlighted with the arrows; Return picks it.
    let selection: HintPanelItem?
    let pick: (HintPanelItem) -> Void

    /// The panel's side inset, which lines the chips up with the search field's edge.
    private static let inset: CGFloat = 8

    /// The cloud at the popover's width, chips measured in the fonts they are drawn in. A cloud that
    /// scrolls is laid out again beside the scroller when scroll bars always show.
    static func cloud(saved: SavedSearches, expanded: Bool) -> SavedChipCloud {
        let width = PopoverView.size.width - 2 * inset
        let cloud = SavedChipCloud(saved: saved, expanded: expanded, width: width, measure: chipWidth)
        guard cloud.scrolls, NSScroller.preferredScrollerStyle == .legacy else { return cloud }
        let scroller = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        return SavedChipCloud(saved: saved, expanded: expanded, width: width - scroller, measure: chipWidth)
    }

    private static func chipWidth(_ chip: SavedChipCloud.Chip) -> CGFloat {
        let text: String
        let font: NSFont
        switch chip {
        case .saved(let search):
            text = search.name
            font = search.nameIsQuery ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        case .more(let more):
            text = more.title
            font = .systemFont(ofSize: 12)
        }
        return SavedChipCloud.chipWidth(textWidth: (text as NSString).size(withAttributes: [.font: font]).width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !cloud.chips.isEmpty {
                savedCloud
                    .padding(.bottom, 10)
            }
            tokens
            caption
                .padding(.top, 6)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Past five lines (expanded), the cloud scrolls and follows the cursor.
    private var savedCloud: some View {
        Group {
            if cloud.scrolls {
                ScrollViewReader { proxy in
                    ScrollView { lines }
                        .frame(height: SavedChipCloud.expandedHeight)
                        .onChange(of: selection) { _, item in
                            if let item { proxy.scrollTo(item) }
                        }
                }
            } else {
                lines
            }
        }
        // The grouping the "Saved" header used to give.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saved searches")
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: SavedChipCloud.spacing) {
            ForEach(Array(cloud.lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: SavedChipCloud.spacing) {
                    ForEach(line, id: \.item) { chip($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func chip(_ chip: SavedChipCloud.Chip) -> some View {
        let width = Self.chipWidth(chip)
        switch chip {
        case .saved(let search):
            PanelButton(look: .filled, radius: 6, selected: selection == chip.item, action: { pick(chip.item) }) {
                Text(search.name)
                    .font(search.nameIsQuery ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, SavedChipCloud.chipPadding)
                    .frame(width: width, height: SavedChipCloud.chipHeight)
            }
            .id(chip.item)
            .help(search.name)
            .accessibilityLabel(search.accessibilityLabel)
            .accessibilityHint("Searches for it")
        case .more(let more):
            PanelButton(look: .outlined, radius: 6, selected: selection == chip.item, action: { pick(chip.item) }) {
                Text(more.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, SavedChipCloud.chipPadding)
                    .frame(width: width, height: SavedChipCloud.chipHeight)
            }
            .id(chip.item)
            .accessibilityLabel(more.accessibilityLabel(total: model.settings.savedSearches.items.count))
        }
    }

    private var tokens: some View {
        HStack(spacing: 4) {
            ForEach(SearchHint.all, id: \.self) { hint in
                PanelButton(look: .outlined, radius: 5, selected: selection == .hint(hint), action: {
                    pick(.hint(hint))
                }) {
                    HStack(spacing: 5) {
                        Text(hint.sigil)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                        if hint.showsWord {
                            Text(hint.word)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 5)
                    .frame(height: 22)
                }
                .accessibilityLabel(hint.accessibilityLabel)
                .accessibilityHint(hint.accessibilityHint)
            }
        }
    }

    /// One fixed line: the selected chip's query, the token's sentence, or a default. VoiceOver reads
    /// the selected item itself, so the caption is hidden from it.
    private var caption: some View {
        let caption = HintCaption(
            for: selection, saved: model.settings.savedSearches, scope: model.snapshot?.scope ?? model.settings.scope,
            expanded: expanded)
        return HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Text(caption.text)
                    .font(caption.isQuery ? .system(size: 11, design: .monospaced) : .system(size: 11))
                    .foregroundStyle(caption.isQuery ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(caption)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if caption.showsReturn { Keycap { Text("↩") } }
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.12), value: caption)
        .accessibilityHidden(true)
    }
}

extension SearchHints {
    /// Drawn over the top of the list, which doesn't move: the popover's own material and a 1pt rule, with
    /// a soft shadow below unless a completion list covers the panel (only the top layer casts one).
    func overList(solid: Bool, shadow: Bool) -> some View {
        VStack(spacing: 0) {
            self
            Hairline()
        }
        .background { PopoverMaterial(solid: solid) }
        .contentShape(Rectangle())
        .background(alignment: .bottom) {
            if shadow { HintPanelShadow() }
        }
    }
}

/// The popover's background, so the panel reads as part of it: the material behind the window, or with
/// a solid background the same opaque fill under the window-background material.
private struct PopoverMaterial: View {
    let solid: Bool

    var body: some View {
        ZStack {
            if solid { Color(nsColor: .windowBackgroundColor) }
            EffectView(solid: solid)
        }
        .accessibilityHidden(true)
    }

    private struct EffectView: NSViewRepresentable {
        let solid: Bool

        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.state = .active
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {
            view.material = solid ? .windowBackground : .popover
            view.blendingMode = solid ? .withinWindow : .behindWindow
        }
    }
}

/// A soft shadow just below the panel's rule, deeper in dark mode so the edge stays clear on dark rows.
private struct HintPanelShadow: View {
    @Environment(\.colorScheme) private var colorScheme
    private static let depth: CGFloat = 8

    var body: some View {
        LinearGradient(
            colors: [.black.opacity(colorScheme == .dark ? 0.35 : 0.1), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: Self.depth)
            .offset(y: Self.depth)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A chip or token: filled (a saved search) or outlined ("+N", the tokens), its fill following hover,
/// press and the keyboard cursor, which also draws an accent edge so a selected chip stands out in the cloud.
private struct PanelButton<Label: View>: View {
    let look: PanelLook
    let radius: CGFloat
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(PanelButtonStyle(look: look, radius: radius, selected: selected, hovering: hovering))
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private enum PanelLook { case filled, outlined }

private struct PanelButtonStyle: ButtonStyle {
    let look: PanelLook
    let radius: CGFloat
    let selected: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        return configuration.label
            .contentShape(shape)
            .background(shape.fill(fill(pressed: configuration.isPressed)))
            .overlay {
                if selected {
                    shape.strokeBorder(Color.accentColor, lineWidth: 1)
                } else if look == .outlined {
                    shape.strokeBorder(Palette.separator, lineWidth: 0.5)
                }
            }
    }

    private func fill(pressed: Bool) -> Color {
        if selected { return Palette.selection }
        if pressed { return Palette.strongFill }
        switch look {
        case .filled: return hovering ? Palette.strongFill : Palette.fill
        case .outlined: return hovering ? Palette.rowHover : .clear
        }
    }
}
