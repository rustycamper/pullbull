import PullBullKit
import SwiftUI

/// Every shortcut by section, under a filter field that has focus on open. Esc clears the filter,
/// then closes.
struct ShortcutsView: View {
    let sections: [ShortcutSection]
    let close: () -> Void
    @State private var query = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        let shown = ShortcutCatalog.filter(sections, query: query)
        VStack(spacing: 0) {
            TextField("Filter", text: $query, prompt: Text("Filter: copy, board, search…"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($filterFocused)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 4)
            if shown.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                Form {
                    ForEach(shown) { section in
                        Section {
                            ForEach(section.shortcuts, id: \.self) { ShortcutRow(shortcut: $0) }
                        } header: {
                            Text(section.title)
                        } footer: {
                            if let note = section.note {
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 440, idealWidth: 480, minHeight: 360, idealHeight: 620)
        .onAppear { filterFocused = true }
        .onExitCommand {
            if query.isEmpty { close() } else { query = "" }
        }
    }
}

private struct ShortcutRow: View {
    let shortcut: Shortcut

    var body: some View {
        LabeledContent {
            if shortcut.keys.isEmpty {
                Text("Not set").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(shortcut.keys, id: \.self) { combo in
                        HStack(spacing: 3) {
                            ForEach(Array(combo.enumerated()), id: \.offset) { _, key in
                                Keycap(size: 12) { Text(key) }
                            }
                        }
                    }
                }
            }
        } label: {
            RowLabel(shortcut.action, note: shortcut.note)
        }
        .accessibilityElement(children: .combine)
    }
}
