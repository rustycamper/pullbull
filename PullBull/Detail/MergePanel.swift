import AppKit
import PullBullKit
import SwiftUI

/// The merge panel, directly above the bottom row: what's being merged, frozen from the panel's read, and
/// the Merge button with its key. Nothing here takes focus: the keys come through `MergePanelKeys`.
struct MergePanel: View {
    let model: AppModel
    let mode: MergeMode
    /// The bottom row's Cancel, which closes the panel itself.
    let cancelAnchor: MenuAnchor

    @State private var panelAnchor = MenuAnchor()
    @State private var outsideClicks = OutsideClickMonitor()

    private static let mergeWhenReadyNote =
        "Merges by itself, even with PullBull closed. Commits pushed later by people with write access are included."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sentence = mode.sentence {
                Text(sentence)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if mode.methods.count > 1 { methodChoice }
                if let summary = mode.summary {
                    Text(summary)
                        .foregroundStyle(Palette.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                ForEach(mode.warnings, id: \.text) { warning in
                    Text(warning.text).foregroundStyle(Palette.amberGlyph)
                }
                if mode.read?.facts.action == .mergeWhenReady {
                    Text(Self.mergeWhenReadyNote)
                        .foregroundStyle(Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                confirmButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text("Checking…").foregroundStyle(Palette.secondaryText)
            }
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Hairline() }
        .background(MenuAnchorView(anchor: panelAnchor))
        .onAppear {
            outsideClicks.install(inside: [panelAnchor, cancelAnchor]) { model.leaveMergeMode(returnsFocus: false) }
        }
        .onDisappear { outsideClicks.remove() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Merge panel")
        .accessibilityAction(named: Text(mode.confirmTitle)) { model.confirmMerge(on: mode.key) }
    }

    private var methodChoice: some View {
        HStack(spacing: 2) {
            ForEach(mode.methods, id: \.self) { method in
                MethodButton(title: method.title, isSelected: method == mode.method) { choose(method) }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
        .disabled(mode.phase != .ready)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Merge method")
        .accessibilityValue(mode.method?.title ?? "")
        .accessibilityAdjustableAction { direction in
            model.changeMergeMethod(by: direction == .increment ? 1 : -1)
        }
    }

    private func choose(_ method: MergeMethod) {
        guard let from = mode.method.flatMap(mode.methods.firstIndex(of:)), let to = mode.methods.firstIndex(of: method),
              from != to
        else { return }
        model.changeMergeMethod(by: to - from)
    }

    /// Merge is the accent-filled button; Merge anyway is filled amber, the warnings' colour, so the riskier
    /// step stands out from the recommended one without looking disabled.
    private var confirmButton: some View {
        AccentTextButton(
            title: confirmTitle,
            fill: mode.isSecondStep ? Palette.amberGlyph : .accentColor,
            text: mode.isSecondStep ? Palette.onAmber : Palette.onAccent
        ) { model.confirmMerge(on: mode.key) }
        .disabled(mode.phase != .ready)
        .accessibilityLabel(mode.phase == .ready ? mode.confirmTitle : confirmTitle)
    }

    private var confirmTitle: String {
        switch mode.phase {
        case .reading, .confirming: "Checking…"
        case .ready: "\(mode.confirmTitle) ⌃⌘↩"
        }
    }
}

private extension MergeMethod {
    var title: String {
        switch self {
        case .merge: "Merge commit"
        case .squash: "Squash"
        case .rebase: "Rebase"
        }
    }
}

/// One method in the choice: filled when chosen.
private struct MethodButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Palette.strongFill : .clear))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle())
        .focusable(false)
    }
}

/// Runs `outside` on a mouse-down anywhere but the views of `inside`. The event carries on to whatever it
/// hit. It fires before the button under the pointer acts, so `inside` has to hold any button that closes
/// the panel itself: Cancel would turn back into Merge under the pointer and the click would reopen it.
@MainActor
final class OutsideClickMonitor {
    private var monitor: Any?

    func install(inside anchors: [MenuAnchor], outside: @escaping @MainActor () -> Void) {
        remove()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
            // Local monitors run on the main thread; the event never leaves it.
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated {
                let isInside = anchors.contains { anchor in
                    guard let view = anchor.view, view.window === event.window else { return false }
                    return view.convert(view.bounds, to: nil).contains(event.locationInWindow)
                }
                if !isInside { outside() }
            }
            return event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The detail's line on merging: why it can't be done here, what's missing, the viewer's own auto-merge
/// with **Cancel auto-merge**, or a draft with **Ready for review**. Nothing while there's a Merge button or
/// nothing to say.
struct MergeSection: View {
    let model: AppModel
    let key: PRKey
    let webURL: URL

    var body: some View {
        switch model.draftOffer(for: key) {
        case .markReady(let autoMergeSet):
            let text = autoMergeSet
                ? "Draft, with auto-merge set. It can't merge until it's ready for review."
                : "Draft. It can't be merged until it's ready for review."
            let title = model.draftFlips.contains(key) ? "Marking ready…" : "Ready for review"
            section(text, link: webURL, button: (title, model.canFlipDraft(on: key), { model.flipDraft(on: key) }))
        case .permission(let permission):
            if let note = permission.note(for: .draft) { section(note, link: link(for: permission)) }
        case .convert, .hidden:
            mergeBody
        }
    }

    @ViewBuilder private var mergeBody: some View {
        switch model.mergeOffer(for: key) {
        case .reason(let text):
            section(text, link: webURL)
        case .permission(let permission):
            if let note = permission.note(for: .merge) { section(note, link: link(for: permission)) }
        case .cancelAutoMerge:
            section(
                "Merging by itself when its requirements pass.", link: webURL,
                button: ("Cancel auto-merge", !model.isPostInFlight(for: key), { model.cancelAutoMerge(on: key) }))
        case .action, .waiting, .hidden:
            EmptyView()
        }
    }

    /// Where the permission is put right: accepted, or installed where there's no installation.
    private func link(for permission: EditPermission) -> URL? {
        switch permission {
        case .needsAppApproval(_, _, let url): url
        case .unavailable: model.installURL
        case .ready, .needsGhScope: nil
        }
    }

    /// `button` comes first on the row, before **Open on GitHub**.
    private func section(
        _ text: String, link: URL?, button: (title: String, enabled: Bool, action: () -> Void)? = nil
    ) -> some View {
        DetailSection(title: "Merge") {
            DetailCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        if let button {
                            Button(button.title, action: button.action)
                                .buttonStyle(.link)
                                .disabled(!button.enabled)
                        }
                        if let link { Link("Open on GitHub", destination: link) }
                    }
                    .font(.system(size: 11))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        // A Merge when ready on its way shows as set, dimmed, as a review sending is.
        .opacity(model.sendingMerges.contains(key) ? 0.5 : 1)
    }
}
