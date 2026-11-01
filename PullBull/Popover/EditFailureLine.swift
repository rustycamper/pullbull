import AppKit
import PullBullKit
import SwiftUI

/// Why the last edit didn't stick, just above the footer or the detail's bottom bar, until it's
/// dismissed or the next edit.
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
