import PullBullKit
import SwiftUI

/// The assignee or label picker: the issue it edits, a filter, then the candidates with the ticked ones
/// first. In place of the rows, the note when this account may not edit here.
struct SetPickerView: View {
    let model: AppModel
    @State private var filter = ""
    @FocusState private var filterFocused: Bool
    /// The rows' full height; the list scrolls only beyond what the popover fits.
    @State private var rowsHeight: CGFloat?

    var body: some View {
        if let picker = model.setPicker {
            let labels = picker.field == .labels
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
                    TextField(labels ? "Filter labels" : "Filter people", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.rowHover))
                        .focused($filterFocused)
                        .onChange(of: filter) { _, text in model.filterSetPicker(text) }
                        .accessibilityLabel(labels ? "Filter labels" : "Filter people")
                    if picker.rows.isEmpty {
                        status(picker, labels: labels)
                    } else if let error = picker.loadError {
                        message(error)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(picker.rows.enumerated()), id: \.element.id) { index, row in
                                    SetPickerRowView(row: row, labels: labels, selected: index == picker.selection) {
                                        model.moveSetPicker(by: index - picker.selection)
                                        model.toggleSetPicker()
                                    }
                                }
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
                        }
                        .frame(maxHeight: rowsHeight)
                        .scrollBounceBehavior(.basedOnSize)
                        // ↑/↓ keep the highlighted row in view.
                        .onChange(of: picker.selection) { _, selection in
                            guard picker.rows.indices.contains(selection) else { return }
                            proxy.scrollTo(picker.rows[selection].id)
                        }
                    }
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            // Once the filter is in the window: asked for sooner, the focus lands on the search field.
            .onAppear { DispatchQueue.main.async { filterFocused = true } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(labels ? "Labels" : "Assignees") for \(picker.title)")
        }
    }

    /// What stands in for the rows: why loading failed, that it's loading, or that nothing matches.
    @ViewBuilder
    private func status(_ picker: SetPicker, labels: Bool) -> some View {
        if let error = picker.loadError {
            message(error)
        } else if picker.isLoading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(labels ? "Loading labels…" : "Loading people…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        } else if filter.isEmpty {
            message(labels ? "No labels" : "No people")
        } else {
            message(labels ? "No label called “\(filter)”" : "No one called “\(filter)”")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}

private struct SetPickerRowView: View {
    let row: SetPickerRow
    let labels: Bool
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(row.isChecked ? 1 : 0)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                if labels {
                    if let color = LabelDotColor.parse(row.candidate.color) {
                        LabelDot(color: color)
                    }
                } else {
                    AvatarView(login: row.candidate.name, url: row.candidate.avatarURL, size: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.candidate.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if let detail = row.candidate.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Palette.selection : hovering ? Palette.rowHover : .clear))
            .opacity(row.isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            row.isChecked ? "\(row.candidate.name), \(labels ? "applied" : "assigned")" : row.candidate.name)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}
