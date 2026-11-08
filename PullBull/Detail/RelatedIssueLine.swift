import AppKit
import SwiftUI
import PullBullKit

/// A related issue in a detail card: state glyph, title, and "#N · state" under it, opening that issue's
/// detail. `repo` is the repository of the page it sits on, so a same-repo issue shows as "#N".
struct RelatedIssueLine: View {
    let issue: RelatedIssue
    let repo: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                let glyph = Palette.issueGlyph(issue.glyph)
                Image(symbol: glyph.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(glyph.color)
                    .frame(width: 14)
                    .accessibilityLabel(glyph.label)
                VStack(alignment: .leading, spacing: 1) {
                    Text(issue.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(issue.reference(from: repo)) · \(stateWord)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show \(issue.key.repo) #\(issue.key.number)")
        .accessibilityElement(children: .combine)
    }

    private var stateWord: String {
        switch issue.glyph {
        case .open: "open"
        case .completed: "closed"
        case .notPlanned: "not planned"
        }
    }
}

/// The line that ends a list GitHub cut short: how many more it holds, opening `url` on GitHub.
struct MoreOnGitHubLine: View {
    let count: Int
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Text("+\(count) more on GitHub")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open on GitHub")
    }
}
