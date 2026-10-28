import PullBullKit
import SwiftUI

/// The row under the search field that names the query before saving it, opened by the field's
/// bookmark. Return saves and Esc cancels (the popover's key handling); Save is off while the name is
/// blank, and the name takes at most 40 characters.
struct SaveSearchRow: View {
    @Binding var name: String
    var focused: FocusState<Bool>.Binding
    let onSave: () -> Void
    let onCancel: () -> Void

    private var canSave: Bool { SavedSearch.validName(name) != nil }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused(focused)
                .accessibilityLabel("Saved search name")
                // Set after the edit, so the field shows the capped text too.
                .onChange(of: name) { _, typed in
                    let capped = SavedSearch.capped(typed)
                    if capped != typed { name = capped }
                }
            Button("Cancel", action: onCancel)
                .controlSize(.small)
            Button("Save", action: onSave)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }
}
