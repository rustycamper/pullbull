import AppKit
import SwiftUI
import PullBullKit

// Building blocks shared by the PR and issue detail views.

struct DetailSection<Content: View, Accessory: View>: View {
    let title: String
    var summary: String?
    @ViewBuilder let content: () -> Content
    /// Drawn after the summary, such as the Files changed diffstat bar.
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let summary {
                    Text(summary)
                        .monospacedDigit()
                }
                accessory()
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

extension DetailSection where Accessory == EmptyView {
    init(title: String, summary: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, summary: summary, content: content, accessory: { EmptyView() })
    }
}

/// The glyph for a board Status, shared by the list's group headers and the issue detail: work in
/// progress is a half-filled circle, anything else an outline.
enum BoardStatusGlyph {
    static func symbol(forStatusNamed name: String) -> String {
        let name = name.lowercased()
        if name.contains("progress") || name.contains("review") || name.contains("doing") {
            return "circle.lefthalf.filled"
        }
        return "circle.dashed"
    }

    static let notOnBoard = "square.dashed"
}

struct DetailCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.separator, lineWidth: 0.5))
    }
}

struct CardDivider: View {
    var body: some View {
        Hairline()
    }
}

struct EmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
    }
}

struct CommentLine: View {
    let comment: Comment
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(login: comment.author, url: URL(string: "https://github.com/\(comment.author).png"), size: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(comment.author).fontWeight(.semibold)
                    Text("· \(RelativeAge.short(from: comment.createdAt, to: now))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                MarkdownText(comment.body.trimmingCharacters(in: .whitespacesAndNewlines))
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Open / Draft gray, Merged / Closed muted tints; each with its own glyph.
struct StatePill: View {
    let pr: PullRequest

    var body: some View {
        switch pr.state {
        case .merged:
            Pill(symbol: Palette.prGlyph(.merged), text: "Merged", foreground: Palette.mergedText, fill: Palette.mergedFill)
        case .closed:
            Pill(symbol: Palette.prGlyph(.closed), text: "Closed", foreground: Palette.closedText, fill: Palette.closedFill)
        case .open:
            if pr.isDraft {
                Pill(symbol: Palette.prGlyph(.draft), text: "Draft", foreground: Palette.secondaryText, fill: .clear)
                    .overlay(Capsule().strokeBorder(Palette.separator, lineWidth: 0.5))
            } else if ReviewRules.isReadyToMerge(pr) {
                ReadyToMergePill(fill: Palette.strongFill)
            } else {
                Pill(symbol: Palette.prGlyph(.open), text: "Open", foreground: Palette.secondaryText, fill: Palette.strongFill)
            }
        }
    }
}

/// The detail header's way back: a chevron in the same quiet 28pt button as the header's other icons.
/// Where it leads is in the tooltip and VoiceOver label.
struct DetailBackButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Back to \(title) (esc)")
        .accessibilityLabel("Back to \(title)")
    }
}

struct DetailIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct RefreshFailedNote: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.amberGlyph)
                .accessibilityHidden(true)
            Text("Couldn't refresh · \(message)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.amberFill))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// An outlined icon button for a detail view's bottom bar; the name is its tooltip and VoiceOver label.
struct OutlinedIconButton: View {
    let name: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Palette.fill : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.separator))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(name)
        .accessibilityLabel(name)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// An item's labels as chips, wrapping onto more lines; `color(i)` is the GitHub colour of `labels[i]`.
struct DetailLabels: View {
    let labels: [String]
    let color: (Int) -> String?

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: 4) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                DetailLabelChip(name: label, color: LabelDotColor.parse(color(index)))
            }
        }
    }
}

/// A muted outline chip, led by a dot in the label's GitHub colour when it has one. The text stays gray.
struct DetailLabelChip: View {
    let name: String
    let color: UInt32?

    var body: some View {
        HStack(spacing: 4) {
            if let color { LabelDot(color: color) }
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .frame(height: 16)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.separator, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// Lays children out left to right, wrapping to a new line when the width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2), anchor: .topLeading,
                    proposal: .init(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: maxWidth, height: nil))
            let itemWidth = min(size.width, maxWidth)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
