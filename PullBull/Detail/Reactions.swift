import PullBullKit
import SwiftUI

// A detail's reactions: the chips under a description, comment or review, the ☺︎ that shows on hover, and
// the picker it opens.

/// What a detail row may do with one subject's reactions. The detail views build it from the model, so the
/// shared components don't take the model.
struct ReactionHandle {
    let key: PRKey
    let canReact: Bool
    /// The running account's login, which a chip's tooltip reads as "You".
    let viewer: String?
    let toggle: (ReactionContent) -> Void
    let isPickerOpen: Bool
    let setPickerOpen: (Bool) -> Void
}

/// One subject's reactions as a detail row shows them (the clicks GitHub's reads don't show yet laid over
/// them), and its handle. Both nil for a subject without reactions, such as one read from an old cache.
struct ShownReactions {
    let reactions: Reactions?
    let react: ReactionHandle?

    static var none: ShownReactions { ShownReactions(reactions: nil, react: nil) }

    init(reactions: Reactions?, react: ReactionHandle?) {
        self.reactions = reactions
        self.react = react
    }

    /// From `stored`, the subject's reactions as the detail holds them. The handle toggles on `stored`,
    /// since `toggleReaction` lays the overlay over it itself.
    @MainActor init(_ stored: Reactions?, model: AppModel, key: PRKey, isPullRequest: Bool, now: Date) {
        guard let stored else {
            self = .none
            return
        }
        let subject = ReactionPickerSubject(key: key, subjectId: stored.subjectId)
        reactions = model.shownReactions(stored, on: key, now: now)
        react = ReactionHandle(
            key: key, canReact: model.canReact(stored, on: key, isPullRequest: isPullRequest),
            viewer: model.runningAccount?.login,
            toggle: { model.toggleReaction($0, on: stored, key: key, isPullRequest: isPullRequest) },
            isPickerOpen: model.reactionPicker == subject,
            setPickerOpen: { open in
                if open {
                    model.openReactionPicker(subject)
                } else if model.reactionPicker == subject {
                    model.openReactionPicker(nil)
                }
            })
    }
}

/// A subject's reactions as chips in GitHub's order, wrapping onto more lines. Only for `reactions.shown`
/// that isn't empty; clickable where the viewer can react.
struct ReactionChips: View {
    let reactions: Reactions
    let react: ReactionHandle?

    var body: some View {
        let clickable = react?.canReact == true
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(reactions.shown, id: \.content) { group in
                ReactionChip(
                    group: group, viewer: react?.viewer,
                    toggle: clickable ? { react?.toggle(group.content) } : nil)
            }
        }
    }
}

/// "👍 3": yours on the accent, others' on the quiet fill. The tooltip names who reacted.
private struct ReactionChip: View {
    let group: ReactionGroup
    let viewer: String?
    /// Nil where the viewer can't react: the chip shows, but isn't a button.
    let toggle: (() -> Void)?

    var body: some View {
        if let toggle {
            Button(action: toggle) { label }
                .buttonStyle(PressableStyle())
                .focusable(false)
                .help(group.tooltip(viewer: viewer))
                .accessibilityLabel(group.accessibilityLabel)
                .accessibilityAction(named: group.viewerHasReacted ? "Remove reaction" : "Add reaction", toggle)
        } else {
            label
                .help(group.tooltip(viewer: viewer))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(group.accessibilityLabel)
        }
    }

    private var label: some View {
        let mine = group.viewerHasReacted
        return HStack(spacing: 3) {
            Text(verbatim: group.content.emoji)
            Text(verbatim: String(group.count))
                .foregroundStyle(mine ? AnyShapeStyle(Palette.accentTextOnSelection) : AnyShapeStyle(.secondary))
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(mine ? .clear : Palette.fill))
        .selectionFill(mine, in: Capsule())
        .overlay(Capsule().strokeBorder(mine ? Color.accentColor : Palette.separator, lineWidth: 0.5))
        .contentShape(Capsule())
    }
}

/// The ☺︎ at a row's top right, which opens the reaction picker under it. Laid over the row by the caller,
/// so it reserves no width; the caller shows it only on hover or while its picker is open.
struct ReactButton: View {
    let react: ReactionHandle
    /// The subject's reactions as shown, which the picker tints.
    let reactions: Reactions
    @State private var hovering = false

    var body: some View {
        Button { react.setPickerOpen(true) } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 16)
                .background(RoundedRectangle(cornerRadius: 4).fill(hovering || react.isPickerOpen ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("React")
        .accessibilityLabel("React…")
        .anchorPreference(key: ReactionPickerAnchorKey.self, value: .bounds) { bounds in
            react.isPickerOpen ? ReactionPickerAnchor(bounds: bounds, reactions: reactions, toggle: react.toggle) : nil
        }
    }
}

/// Where the open reaction picker opens: the ☺︎ that opened it, and what the picker shows and sends.
struct ReactionPickerAnchor {
    let bounds: Anchor<CGRect>
    let reactions: Reactions
    let toggle: (ReactionContent) -> Void
}

struct ReactionPickerAnchorKey: PreferenceKey {
    static var defaultValue: ReactionPickerAnchor? { nil }

    /// Only one picker is open at a time, so at most one ☺︎ sets it.
    static func reduce(value: inout ReactionPickerAnchor?, nextValue: () -> ReactionPickerAnchor?) {
        value = value ?? nextValue()
    }
}

/// The detail's layer while its reaction picker is open: a catcher over the whole detail that closes the
/// picker on a click outside, and the picker on top, under its ☺︎ (above it when there's no room below).
struct ReactionPickerLayer: View {
    let anchor: ReactionPickerAnchor?
    let close: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                if let anchor {
                    let origin = Self.origin(for: proxy[anchor.bounds], in: proxy.size)
                    ReactionPicker(reactions: anchor.reactions, toggle: anchor.toggle)
                        .offset(x: origin.x, y: origin.y)
                }
            }
        }
    }

    /// Right-aligned with the ☺︎ and kept 8 pt inside the detail.
    private static func origin(for button: CGRect, in container: CGSize) -> CGPoint {
        let size = ReactionPicker.size
        let margin: CGFloat = 8
        let x = min(max(button.maxX - size.width, margin), container.width - size.width - margin)
        let below = button.maxY + 4
        let y = below + size.height <= container.height - margin ? below : button.minY - size.height - 4
        return CGPoint(x: x, y: max(y, margin))
    }
}

/// GitHub's eight reactions in a row; the ones you've given tinted as your chips are. A click toggles one,
/// which also closes the picker.
struct ReactionPicker: View {
    let reactions: Reactions
    let toggle: (ReactionContent) -> Void

    private static let button: CGFloat = 24
    private static let spacing: CGFloat = 2
    private static let padding: CGFloat = 4
    static let size = CGSize(
        width: CGFloat(ReactionContent.allCases.count) * button
            + CGFloat(ReactionContent.allCases.count - 1) * spacing + 2 * padding,
        height: button + 2 * padding)

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(ReactionContent.allCases, id: \.self) { content in
                ReactionPickerButton(content: content, given: reactions.viewerHasReacted(content)) {
                    toggle(content)
                }
            }
        }
        .padding(Self.padding)
        .raisedSurface(radius: 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reactions")
    }
}

private struct ReactionPickerButton: View {
    let content: ReactionContent
    /// The viewer gave this reaction: tinted, and a click takes it back.
    let given: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: content.emoji)
                .font(.system(size: 14))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(!given && hovering ? Palette.fill : .clear))
                .selectionFill(given, radius: 5)
                .overlay {
                    if given { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 0.5) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(content.name)
        .accessibilityLabel(content.name)
        .accessibilityAddTraits(given ? .isSelected : [])
    }
}

extension View {
    /// The VoiceOver action "React…" on a description, comment or review the viewer can react to.
    @ViewBuilder func reactAction(_ react: ReactionHandle?) -> some View {
        if let react, react.canReact {
            accessibilityElement(children: .contain)
                .accessibilityAction(named: "React…") { react.setPickerOpen(true) }
        } else {
            self
        }
    }
}
