import PullBullKit
import SwiftUI

/// The saved searches: rename, edit the query, drag to reorder, "+" adds and "−" deletes the selected
/// row without asking. Valid edits reach an open popover at once; an invalid field is outlined in red
/// while the store keeps its last valid value, which the row shows again once the tab closes.
struct SearchSettingsTab: View {
    @Bindable var model: AppModel
    @State private var editor = SavedSearchEditor()
    @State private var selection: UUID?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name(UUID), query(UUID)

        var row: UUID {
            switch self {
            case .name(let id), .query(let id): id
            }
        }
    }

    private static let nameWidth: CGFloat = 150
    private static let keyWidth: CGFloat = 24

    private var rows: [SavedSearchEditor.Row] { editor.rows(in: model.settings.savedSearches) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text("Save a search from the search field's bookmark button.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        columnHeader
                        Divider()
                        list
                    }
                    Divider()
                    addRemoveBar
                }
                .frame(height: 240)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Saved searches")
            } footer: {
                Text("Apply one from the empty search field: click it, or select it with ↓ and press Return. The first nine also apply with ⌃1–⌃9.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsTabHeight()
        // Editing a field selects its row, so "−" deletes the row being edited.
        .onChange(of: focusedField) { _, field in
            if let field { selection = field.row }
        }
        .onAppear { editor.open() }
        // Focus goes first, so the field's last push of its text lands before `close()` ignores edits.
        .onDisappear {
            focusedField = nil
            editor.close()
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 14, height: 1)
            Text("Key").frame(width: Self.keyWidth, alignment: .leading)
            Text("Name").frame(width: Self.nameWidth, alignment: .leading)
            Text("Query")
            Spacer()
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 24)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 8) {
                    // Somewhere to grab the row by: a drag that starts in a text field selects text instead.
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 14)
                        .accessibilityHidden(true)
                    // ⌃1–⌃9 apply the first nine saved; a new row has no key until it is saved.
                    Text(index < model.settings.savedSearches.items.count
                         ? SavedSearches.keyLabel(at: index) ?? "" : "")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: Self.keyWidth, alignment: .leading)
                    field(
                        "Name", label: "Name, saved search \(index + 1)", text: binding(row, \.name),
                        valid: row.nameIsValid, focus: .name(row.id))
                        .frame(width: Self.nameWidth)
                        .help(row.nameIsValid ? "" : "A name needs 1 to 40 characters")
                    field(
                        "Query", label: queryLabel(row, index: index), text: binding(row, \.query),
                        valid: row.queryIsValid, focus: .query(row.id))
                        .help(row.queryIsValid ? "" : "A query can't be empty")
                }
                .tag(row.id)
            }
            .onMove { offsets, destination in
                editor.move(fromOffsets: offsets, toOffset: destination, in: &model.settings.savedSearches)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // The form around it doesn't scroll; the list still does once it outgrows its height.
        .scrollDisabled(false)
    }

    /// VoiceOver names the row a query belongs to: by its name, or by position while the name is invalid.
    private func queryLabel(_ row: SavedSearchEditor.Row, index: Int) -> String {
        SavedSearch.validName(row.name).map { "Query for \($0)" } ?? "Query, saved search \(index + 1)"
    }

    private func field(
        _ title: String, label: String, text: Binding<String>, valid: Bool, focus: Field
    ) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focusedField, equals: focus)
            .accessibilityLabel(label)
            .accessibilityValue(valid ? text.wrappedValue : "\(text.wrappedValue), invalid")
            .padding(.horizontal, 4)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.red, lineWidth: 1)
                    .opacity(valid ? 0 : 1))
    }

    /// One field of `row`; a name over 40 characters shows as invalid, as an empty one does.
    private func binding(_ row: SavedSearchEditor.Row, _ key: KeyPath<SavedSearchEditor.Row, String>) -> Binding<String> {
        Binding {
            rows.first { $0.id == row.id }?[keyPath: key] ?? row[keyPath: key]
        } set: { typed in
            guard let current = rows.first(where: { $0.id == row.id }) else { return }
            let name = key == \.name ? typed : current.name
            let query = key == \.query ? typed : current.query
            editor.edit(row.id, name: name, query: query, in: &model.settings.savedSearches)
        }
    }

    private var addRemoveBar: some View {
        HStack(spacing: 0) {
            Button {
                let id = editor.addRow()
                selection = id
                DispatchQueue.main.async { focusedField = .query(id) }
            } label: {
                Image(systemName: "plus").frame(width: 24, height: 22)
            }
            .help("Add a saved search")
            .accessibilityLabel("Add saved search")
            Divider().frame(height: 16)
            Button {
                guard let id = selection else { return }
                focusedField = nil
                editor.delete(id, in: &model.settings.savedSearches)
                selection = nil
            } label: {
                Image(systemName: "minus").frame(width: 24, height: 22)
            }
            .disabled(selection.map { id in !rows.contains { $0.id == id } } ?? true)
            .help("Delete the selected search")
            .accessibilityLabel("Delete saved search")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .frame(height: 26)
    }
}
