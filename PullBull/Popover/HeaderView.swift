import AppKit
import SwiftUI
import PullBullKit

/// The header: the mode switch, tabs and settings, and under them the search field. Both rows stay put
/// while searching; only the list below changes.
struct HeaderView: View {
    let model: AppModel
    /// Results are on screen (`Route.search`).
    let searching: Bool
    /// Results, or the empty field's hints, are on screen.
    let searchOpen: Bool
    var fieldFocused: FocusState<Bool>.Binding
    /// Set while the qualifier ghost is drawn, so Tab never writes one that is hidden.
    @Binding var ghostDrawn: Bool
    /// The popover's window, whose field editor holds the caret.
    let window: () -> NSWindow?
    /// Closes a field that shows no results (its hints, or a lone token being completed), before a tab is picked.
    let onCancelSearch: () -> Void
    /// The mode switch, the same as ⌘1 / ⌘2.
    let onSwitchMode: (PopoverMode) -> Void
    /// The bookmark in the field: opens the save row under it.
    let onSaveSearch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            searchRow
        }
    }

    /// The mode switch, then the mode's tabs filling the width. While results are on screen
    /// the tabs narrow them instead of showing their lists.
    private var titleRow: some View {
        HStack(spacing: 4) {
            ModeToggle(model: model, select: onSwitchMode)
            TabBar(model: model, searching: searching) {
                if searchOpen { onCancelSearch() }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 40)
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            TextField(placeholder, text: Binding(
                get: { model.searchText },
                set: { text in
                    // Opening a detail unfocuses the field, which pushes its text back; a detail on
                    // screen takes no edits from the hidden field.
                    switch model.route {
                    case .detail, .issueDetail, .ask: return
                    case .list, .search:
                        // The editor already holds `text`; its caret drives the "@user" completion.
                        model.updateSearch(text, caret: FieldCaret.read(in: window(), text: text))
                    }
                }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(fieldFocused)
                .accessibilityLabel(placeholder)
                .overlay(alignment: .leading) {
                    if fieldFocused.wrappedValue, let ghost = model.qualifierGhost {
                        QualifierGhostText(typed: model.searchText, remainder: ghost.remainder, drawn: $ghostDrawn)
                    }
                }
            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SaveSearchButton(saved: model.searchIsSaved, action: onSaveSearch)
            }
            if !model.searchText.isEmpty {
                Button {
                    model.updateSearch("")
                    fieldFocused.wrappedValue = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Palette.strongFill))
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            } else if !fieldFocused.wrappedValue {
                // The field's label already names it; the shortcut is only a reminder.
                Text("⌘F")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.field))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.separator, lineWidth: 0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 6 + 3)
                .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3.5)
                .padding(-3.5)
                .opacity(fieldFocused.wrappedValue ? 1 : 0))
        .padding(.horizontal, Metrics.rowInset)
        .padding(.bottom, 6)
    }

    /// Search follows the mode; the field's label reads the same.
    private var placeholder: String {
        model.mode == .issues ? "Search issues" : "Search pull requests"
    }
}

/// The grey rest of a qualifier, drawn just after the typed text (`sta` then `tus:`); Tab writes it. Shown
/// only while it fits, since a field scrolled past its start would put it in the wrong place.
private struct QualifierGhostText: View {
    let typed: String
    let remainder: String
    @Binding var drawn: Bool

    /// Where the field editor starts drawing text, inside the field.
    private static let textInset: CGFloat = 0
    private static let font = NSFont.systemFont(ofSize: 12)

    var body: some View {
        GeometryReader { geometry in
            let typedWidth = Self.width(typed)
            if Self.textInset + typedWidth + Self.width(remainder) <= geometry.size.width {
                Text(remainder)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: Self.textInset + typedWidth)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .onAppear { drawn = true }
                    .onDisappear { drawn = false }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// The bookmark in the search field: "Save search…" opens the save row; filled while the query is saved,
/// when it does nothing (saved searches are managed in Settings).
private struct SaveSearchButton: View {
    let saved: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if !saved { action() }
        } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 11))
                .foregroundStyle(saved ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(saved ? "Saved search" : "Save search…")
        .accessibilityLabel(saved ? "Saved search" : "Save search")
    }
}
