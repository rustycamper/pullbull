import SwiftUI
import PullBullKit

/// PR text (description, comments) rendered block by block: headings, lists with task boxes, code,
/// quotes, rules, tables and collapsible details sections, with inline markdown inside each block. Links open through the environment's
/// `openURL`, which `PRDetailView` limits to http and https.
struct MarkdownText: View {
    let blocks: [MarkdownBlock]
    /// Quote and details nesting of these blocks; neither renders deeper than `MarkdownBlock.maxNesting`.
    var depth = 0

    /// Parses through `MarkdownCache`, so a re-render of the same text does not parse it again.
    init(_ source: String) {
        blocks = MarkdownCache.blocks(for: source)
    }

    init(blocks: [MarkdownBlock], depth: Int) {
        self.blocks = blocks
        self.depth = depth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, depth: depth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Parsed blocks by source text. Detail bodies and comments re-render often (the detail's 30s timeline,
/// refreshes, hover), and a body only changes when its text does, so the text is the key.
@MainActor enum MarkdownCache {
    private final class Entry {
        let blocks: [MarkdownBlock]
        init(_ blocks: [MarkdownBlock]) { self.blocks = blocks }
    }

    private static let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 300
        return cache
    }()

    static func blocks(for source: String) -> [MarkdownBlock] {
        let key = source as NSString
        if let hit = cache.object(forKey: key) { return hit.blocks }
        let blocks = MarkdownBlock.parse(source)
        cache.setObject(Entry(blocks), forKey: key)
        return blocks
    }
}

enum InlineMarkdown {
    /// Inline markdown (bold, code, links) with the line breaks kept; plain text if parsing fails.
    static func render(_ text: String) -> AttributedString {
        do {
            return try AttributedString(
                markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let depth: Int

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(InlineMarkdown.render(text))
                .font(.system(size: Self.headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 6 : 0)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(InlineMarkdown.render(text))
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    ListItemLine(item: item)
                }
            }
        case .code(_, let text):
            // Long lines scroll sideways, as tables do, instead of wrapping mid-token.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .lineSpacing(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .defaultScrollAnchor(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.fill))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        case .quote(let inner):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.strongFill)
                    .frame(width: 3)
                if depth < MarkdownBlock.maxNesting {
                    MarkdownText(blocks: inner, depth: depth + 1)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        case .rule:
            Hairline()
                .padding(.vertical, 2)
        case .table(let table):
            MarkdownTable(table: table)
        case .details(let summary, let inner, let open):
            MarkdownDetails(summary: summary, blocks: inner, depth: depth, initiallyExpanded: open)
        }
    }

    /// Kept below the 15pt detail title, so a description's `# H1` never competes with it.
    static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 13.5
        case 2: 13
        default: 12
        }
    }
}

private struct ListItemLine: View {
    let item: MarkdownBlock.ListItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if case .ordered(let number) = item.marker {
                Text("\(number).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let checked = item.task {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(checked ? "Done" : "Not done")
            } else if item.marker == .bullet {
                Text(Self.bullet(depth: item.indent))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(InlineMarkdown.render(item.text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(item.indent) * 14)
    }

    static func bullet(depth: Int) -> String {
        ["•", "◦", "▪"][depth % 3]
    }
}

/// A `<details>` section: a header row with a chevron and the summary that expands the content in place.
/// Collapsed unless the source said `<details open>`.
private struct MarkdownDetails: View {
    let summary: String
    let blocks: [MarkdownBlock]
    let depth: Int
    @State private var expanded: Bool
    @State private var hovering = false

    init(summary: String, blocks: [MarkdownBlock], depth: Int, initiallyExpanded: Bool) {
        self.summary = summary
        self.blocks = blocks
        self.depth = depth
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    Text(InlineMarkdown.render(summary))
                        .fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                // Drawn outside the row's frame, so hovering never moves the text.
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Palette.rowHover : .clear)
                        .padding(.horizontal, -5)
                        .padding(.vertical, -3)
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityLabel(String(InlineMarkdown.render(summary).characters))
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded, depth < MarkdownBlock.maxNesting {
                MarkdownText(blocks: blocks, depth: depth + 1)
                    .padding(.leading, 15)
            }
        }
    }
}

/// A table as a grid that scrolls sideways when its columns don't fit. Columns wrap at `maxColumnWidth`, and a
/// narrow table keeps its own width. VoiceOver reads each body row as one "Header: value, …" element; a table
/// with no body rows reads its header row instead.
private struct MarkdownTable: View {
    let table: MarkdownBlock.Table
    /// Plain-text VoiceOver label per body row, worked out once rather than on every render.
    private let rowLabels: [String]
    private let headerLabel: String

    static let maxColumnWidth: CGFloat = 220

    init(table: MarkdownBlock.Table) {
        self.table = table
        let headers = table.header.map(Self.plain)
        rowLabels = table.rows.map { Self.rowLabel(headers: headers, values: $0.map(Self.plain)) }
        headerLabel = headers.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private var columns: Range<Int> { table.header.indices }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(columns, id: \.self) { column in
                        if column == 0, table.rows.isEmpty {
                            headerCell(column)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(headerLabel)
                        } else {
                            headerCell(column)
                                .accessibilityHidden(true)
                        }
                    }
                }
                Hairline()
                    .gridCellUnsizedAxes(.horizontal)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { offset, row in
                    if offset > 0 {
                        Hairline()
                            .gridCellUnsizedAxes(.horizontal)
                    }
                    GridRow {
                        ForEach(columns, id: \.self) { column in
                            if column == 0 {
                                cell(row[column], column: column)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(rowLabels[offset])
                            } else {
                                cell(row[column], column: column)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.separator, lineWidth: 0.5))
        }
        .defaultScrollAnchor(.leading)
    }

    private func headerCell(_ column: Int) -> some View {
        cell(table.header[column], column: column)
            .fontWeight(.semibold)
            .gridColumnAlignment(Self.horizontal(table.alignments[column]))
    }

    private func cell(_ text: String, column: Int) -> some View {
        CappedWidth(maxWidth: Self.maxColumnWidth) {
            Text(InlineMarkdown.render(text))
                .multilineTextAlignment(Self.multiline(table.alignments[column]))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    /// "Header: value, Header: value". A cell with an empty header reads just its value, an empty cell just
    /// its header, and a column empty in both is skipped.
    private static func rowLabel(headers: [String], values: [String]) -> String {
        zip(headers, values).compactMap { header, value in
            switch (header.isEmpty, value.isEmpty) {
            case (true, true): nil
            case (true, false): value
            case (false, true): header
            case (false, false): "\(header): \(value)"
            }
        }
        .joined(separator: ", ")
    }

    private static func plain(_ text: String) -> String {
        String(InlineMarkdown.render(text).characters)
    }

    private static func horizontal(_ alignment: MarkdownBlock.Table.Alignment) -> HorizontalAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private static func multiline(_ alignment: MarkdownBlock.Table.Alignment) -> TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}

/// Sizes its one subview to its ideal width, or wraps it at `maxWidth` when the ideal is wider. Unlike
/// `frame(maxWidth:)`, a short cell stays short and a long one wraps even when the proposal is unbounded.
private struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

#if DEBUG
#Preview("Tables") {
    let checks = """
    | Header | Value | Why / what was checked |
    |---|---|---|
    | CI | green | Ran `make test` and the app build on the PR branch; both pass with zero warnings. |
    | Docs | **yes** | README lists the new key and [the spec](https://github.com) is linked. |
    """
    let wide = "| " + (1...8).map { "Column \($0)" }.joined(separator: " | ") + " |\n"
        + "|:---|:---:|---:|" + String(repeating: "---|", count: 5) + "\n"
        + "| " + (1...8).map { "Value \($0) with a longer note that wraps" }.joined(separator: " | ") + " |\n"
        + "| a | b | c | d | e | f | g | h |"
    return VStack(alignment: .leading, spacing: 16) {
        MarkdownText(checks)
        MarkdownText(wide)
    }
    .font(.system(size: 12))
    .padding()
    .frame(width: 420)
}

#Preview("Details") {
    let verification = """
    Fixes the footer.

    <details>
    <summary>Verification</summary>

    - [x] `swift test` passes
    - [x] App builds with zero warnings
    </details>

    <details open><summary>Notes</summary>

    Expanded from the start.
    </details>
    """
    return MarkdownText(verification)
        .font(.system(size: 12))
        .padding()
        .frame(width: 420)
}
#endif
