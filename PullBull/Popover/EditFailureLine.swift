import AppKit
import PullBullKit
import SwiftUI

/// The height of each detail's bottom row (the comment field and the item's buttons), by item, so the
/// failure line sits right on the shown detail's field as it grows.
struct DetailBottomInsetKey: PreferenceKey {
    static let defaultValue: [PRKey: CGFloat] = [:]

    static func reduce(value: inout [PRKey: CGFloat], nextValue: () -> [PRKey: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's height as the bottom of the detail of `key` (`DetailBottomInsetKey`).
    func detailBottomInset(for key: PRKey) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: DetailBottomInsetKey.self, value: [key: proxy.size.height])
        })
    }
}

/// Why the last edit didn't stick, just above the footer or, on a detail, its bottom row with the
/// comment field (or the note in its place), until it's dismissed, the next edit, or leaving the item it's about.
struct EditFailureLine: View {
    let model: AppModel

    var body: some View {
        if let failure = model.edits.failure {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.amberGlyph)
                    .accessibilityHidden(true)
                Text(failure.text)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(failure.text)
                Button("Open on GitHub") { NSWorkspace.shared.open(failure.url) }
                    .buttonStyle(.link)
                Button {
                    model.dismissEditFailure()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
            .font(.system(size: 11))
            .padding(.leading, Metrics.listGutter)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .background(Palette.amberFill)
            .overlay(alignment: .top) { Hairline() }
            .accessibilityElement(children: .contain)
            .onAppear { AccessibilityNotification.Announcement(failure.text).post() }
        }
    }
}
