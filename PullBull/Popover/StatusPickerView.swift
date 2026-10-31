import AppKit
import PullBullKit
import SwiftUI

/// Where the Status picker opens: the edited issue's row, or the detail's Status row.
struct StatusPickerAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    /// The topmost wins: a detail opened over the list, not the row hidden under it.
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Marks this view as where the Status picker for `key` opens.
    func statusPickerAnchor(for key: PRKey, model: AppModel) -> some View {
        anchorPreference(key: StatusPickerAnchorKey.self, value: .bounds) {
            model.statusPicker?.key == key ? $0 : nil
        }
    }
}

/// The open Status picker laid over the popover, below its anchor (above it when there's no room), and a
/// catcher behind it that closes it on a click outside.
struct StatusPickerLayer: View {
    let model: AppModel
    let anchor: Anchor<CGRect>?
    /// The picker's height as last laid out; placed from it so a short list stays by its row.
    @State private var height: CGFloat = 260

    var body: some View {
        if model.statusPicker != nil {
            GeometryReader { proxy in
                let frame = StatusPickerPlacement.frame(
                    anchor: anchor.map { proxy[$0] }, height: height, in: proxy.size)
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { model.closeStatusPicker() }
                    StatusPickerView(model: model)
                        .frame(width: frame.width)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                        .frame(maxHeight: proxy.size.height - 8, alignment: .top)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }
}

/// The Status picker: the issue it edits, a filter, then the board's options in board order with Clear
/// Status last. In place of the options, the note when this account may not set Status.
struct StatusPickerView: View {
    let model: AppModel
    @State private var filter = ""
    @FocusState private var filterFocused: Bool
    /// The options' full height; the list scrolls only beyond what the popover fits.
    @State private var rowsHeight: CGFloat?

    var body: some View {
        if let picker = model.statusPicker {
            VStack(alignment: .leading, spacing: 4) {
                Text(picker.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                if let note = picker.permission.note {
                    PermissionNote(note: note, permission: picker.permission)
                } else {
                    TextField("Set Status", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.rowHover))
                        .focused($filterFocused)
                        .onChange(of: filter) { _, text in model.filterStatusPicker(text) }
                        .accessibilityLabel("Filter Status options")
                    if picker.rows.isEmpty {
                        Text("No Status called “\(filter)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(picker.rows.enumerated()), id: \.element.id) { index, row in
                                StatusPickerRowView(row: row, selected: index == picker.selection) {
                                    model.moveStatusPicker(by: index - picker.selection)
                                    model.applyStatusPicker()
                                }
                            }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                    }
                    .frame(maxHeight: rowsHeight)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .onAppear { filterFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Status for \(picker.title)")
        }
    }
}

private struct StatusPickerRowView: View {
    let row: StatusPickerRow
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(row.name)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                if let count = row.openCount, count > 0 {
                    Text("· \(count)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(row.isCurrent ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Palette.selection : hovering ? Palette.rowHover : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.isCurrent ? "\(row.name), current" : row.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }

    private var symbol: String {
        guard let option = row.option else { return "xmark.circle" }
        return BoardStatusGlyph.symbol(forStatusNamed: option.name)
    }

    /// The owner's Status colour, as the board's lane headers show it.
    private var color: Color {
        guard let color = row.option?.color else { return .secondary }
        return Palette.statusOptionColor(color)
    }
}

/// Why the picker can't set Status here, and the one step that fixes it.
private struct PermissionNote: View {
    let note: String
    let permission: EditPermission

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            switch permission {
            case .needsAppApproval(_, _, let url?):
                Button("Open on GitHub") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            case .needsGhScope(let command):
                Button("Copy Command") { PRActions.copy(command) }
                    .controlSize(.small)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
