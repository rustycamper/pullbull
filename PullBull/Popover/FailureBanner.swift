import SwiftUI

/// What couldn't be loaded, on an amber fill: the search's remote failure, and Stats' with its Retry.
struct FailureBanner: View {
    let message: String
    var symbol = "wifi.slash"
    /// A link-style button at the trailing edge, such as Retry; nil for none.
    var action: Action? = nil

    struct Action {
        let title: String
        let perform: () -> Void
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Palette.amberGlyph)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.amberFill))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}
