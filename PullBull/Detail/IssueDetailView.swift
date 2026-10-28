import AppKit
import SwiftUI
import PullBullKit

/// The read-only detail of one issue inside the popover: state and author, a board card (Status,
/// Assignees, Labels), the pull requests that close it, the description and the last two comments, with
/// View on board and Open on GitHub pinned at the bottom. It shows the list data and the cached detail
/// at once; `AppModel` refreshes the detail in place.
struct IssueDetailView: View {
    let model: AppModel
    let key: PRKey

    /// The list copy: on the board it carries the Status and the board item.
    private var listIssue: BoardIssue? { model.issue(for: key) }
    private var detail: IssueDetail? { model.issueDetails[key] }
    /// The freshest row fields: the detail's, else the list's.
    private var issue: BoardIssue? { detail?.issue ?? listIssue }
    private var fetch: DetailFetch? { model.issueDetailFetch?.key == key ? model.issueDetailFetch : nil }
    private var webURL: URL { issue?.url ?? GitHubLinks.issue(key) }
    private var isOnBoard: Bool { model.snapshot?.boardIssues.contains { $0.key == key } == true }
    /// Only for an issue on the board; another issue would land on the board with no item open.
    private var boardURL: URL? {
        guard let snapshot = model.snapshot, let board = snapshot.board,
              let item = snapshot.boardIssues.first(where: { $0.key == key })
        else { return nil }
        return GitHubLinks.boardItem(board, itemId: item.boardItemId)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        summary(now: context.date)
                        if let issue { boardCard(issue) }
                        if let detail {
                            if let error = fetch?.error {
                                RefreshFailedNote(message: error) { model.reloadIssueDetail() }
                            }
                            linkedPRsSection(detail.linkedPRs)
                            descriptionSection(detail.body)
                            conversationSection(detail, now: context.date)
                        } else {
                            placeholder
                        }
                    }
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            bottomBar
        }
        // Links in issue text are untrusted: only web links open, anything else is dropped.
        .environment(\.openURL, OpenURLAction { url in
            LinkPolicy.canOpen(url) ? .systemAction(url) : .discarded
        })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            DetailBackButton(title: backTitle, action: model.closeIssueDetail)
            Spacer(minLength: 0)
            // A checkmark for a moment after ⌥⌘C.
            DetailIconButton(
                symbol: CopyConfirmation.shared.message == nil ? "link" : "checkmark", help: "Copy Link"
            ) { PRActions.copy(webURL.absoluteString) }
            if fetch?.isLoading == true {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Refreshing")
            } else {
                DetailIconButton(symbol: "arrow.clockwise", help: "Refresh", action: model.reloadIssueDetail)
            }
        }
        // Centred on the whole bar, clear of the buttons on either side.
        .overlay {
            Text("\(repoName) #\(String(key.number))")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 72)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private var backTitle: String {
        model.issueDetailReturnRoute == .search ? "Search" : model.selectedTabTitle
    }

    private var repoName: String {
        key.repo.split(separator: "/").last.map(String.init) ?? key.repo
    }

    // MARK: Summary

    private func summary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(issue?.title ?? "\(key.repo) #\(key.number)")
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let issue {
                HStack(spacing: 8) {
                    IssueStatePill(issue: issue)
                    if let author = issue.author ?? (issue.createdAt != nil ? "ghost" : nil) {
                        HStack(spacing: 6) {
                            AvatarView(login: author, url: URL(string: "https://github.com/\(author).png"), size: 20)
                            Text(openedText(author: author, issue: issue, now: now))
                                .lineLimit(1)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, Metrics.detailGutter)
        .padding(.top, 14)
    }

    private func openedText(author: String, issue: BoardIssue, now: Date) -> String {
        guard let created = issue.createdAt else { return "\(author) opened" }
        return "\(author) opened \(RelativeAge.ago(created, now: now))"
    }

    // MARK: Board card

    private func boardCard(_ issue: BoardIssue) -> some View {
        let me = model.snapshot?.org.viewer ?? model.settings.account ?? ""
        let status = model.boardStatus(for: key)
        return DetailSection(title: (isOnBoard ? model.snapshot?.boardTitle : nil) ?? "Details") {
            DetailCard {
                if let status {
                    statusRow(symbol: BoardStatusGlyph.symbol(forStatusNamed: status.name), name: status.name)
                    CardDivider()
                } else if !isOnBoard, model.snapshot?.boardStatus == .available {
                    statusRow(symbol: BoardStatusGlyph.notOnBoard, name: "Not on board")
                    CardDivider()
                }
                CardRow(name: "Assignees") {
                    if issue.assignees.isEmpty {
                        Text("No one").foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 10, lineSpacing: 6) {
                            ForEach(issue.assignees, id: \.login) { assignee in
                                HStack(spacing: 5) {
                                    AvatarView(login: assignee.login, url: assignee.avatarURL, size: 20)
                                    Text(assignee.login).lineLimit(1)
                                    if assignee.login.caseInsensitiveCompare(me) == .orderedSame {
                                        Text("(you)").foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                CardDivider()
                CardRow(name: "Labels") {
                    if issue.labels.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 4, lineSpacing: 4) {
                            ForEach(Array(issue.labels.enumerated()), id: \.offset) { index, label in
                                LabelChip(name: label, color: LabelDotColor.parse(issue.labelColor(at: index)))
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusRow(symbol: String, name: String) -> some View {
        CardRow(name: "Status") {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(name)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private func linkedPRsSection(_ prs: [LinkedPR]) -> some View {
        if prs.isEmpty {
            Text("No linked pull requests")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Metrics.detailGutter)
                .padding(.top, 14)
        } else {
            DetailSection(title: "Linked pull requests", summary: String(prs.count)) {
                DetailCard {
                    ForEach(Array(prs.enumerated()), id: \.element.key) { index, pr in
                        if index > 0 { CardDivider() }
                        LinkedPRLine(pr: pr) { model.openDetail(pr.key) }
                    }
                }
            }
        }
    }

    private func descriptionSection(_ source: String) -> some View {
        DetailSection(title: "Description") {
            DetailCard {
                let body = source.trimmingCharacters(in: .whitespacesAndNewlines)
                Group {
                    if body.isEmpty {
                        Text("No description provided.")
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownText(body)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 12))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private func conversationSection(_ detail: IssueDetail, now: Date) -> some View {
        let total = detail.commentTotal
        return DetailSection(title: "Conversation", summary: total == 1 ? "1 comment" : "\(total) comments") {
            VStack(alignment: .leading, spacing: 10) {
                if detail.earlierCommentCount > 0 {
                    let earlier = detail.earlierCommentCount
                    HStack(spacing: 4) {
                        Text(earlier == 1 ? "1 earlier comment ·" : "\(earlier) earlier comments ·")
                            .monospacedDigit()
                        Link("view on GitHub", destination: webURL)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
                }
                if detail.lastComments.isEmpty {
                    Text("No comments")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(detail.lastComments.enumerated()), id: \.offset) { _, comment in
                        CommentLine(comment: comment, now: now)
                    }
                }
            }
        }
    }

    // MARK: Loading and errors

    /// Without a cached detail: placeholders while loading, else the failure with Retry. Never empty.
    @ViewBuilder private var placeholder: some View {
        if let error = fetch?.error {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20))
                    .foregroundStyle(Palette.amberGlyph)
                    .accessibilityHidden(true)
                Text("Couldn't load the details")
                    .font(.system(size: 13, weight: .medium))
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry", action: model.reloadIssueDetail)
                    .controlSize(.small)
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .frame(maxWidth: .infinity)
        } else {
            DetailSkeleton(layout: .issue)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let boardURL {
                OutlinedIconButton(
                    name: model.snapshot?.boardTitle.map { "Open in \($0)" } ?? "View on board",
                    systemImage: "rectangle.split.3x1"
                ) { NSWorkspace.shared.open(boardURL) }
            }
            OutlinedIconButton(name: "Open on GitHub", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.open(webURL)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Pieces

/// Open gray, completed muted purple, not planned gray; each with its own glyph.
private struct IssueStatePill: View {
    let issue: BoardIssue

    var body: some View {
        switch issue.glyph {
        case .open:
            Pill(symbol: Palette.issueGlyph(.open).symbol, text: "Open", foreground: Palette.secondaryText, fill: Palette.strongFill)
        case .completed:
            Pill(symbol: Palette.issueGlyph(.completed).symbol, text: "Closed", foreground: Palette.mergedText, fill: Palette.mergedFill)
        case .notPlanned:
            Pill(symbol: Palette.issueGlyph(.notPlanned).symbol, text: "Closed", foreground: Palette.secondaryText, fill: Palette.fill)
        }
    }
}

/// "Status   In progress": a fixed-width name, then the value.
private struct CardRow<Value: View>: View {
    let name: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .accessibilityElement(children: .combine)
    }
}

/// A muted outline chip, led by a dot in the label's GitHub colour when it has one. The text stays gray.
private struct LabelChip: View {
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

private struct LinkedPRLine: View {
    let pr: LinkedPR
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                let state = Self.state(pr.glyph)
                Image(symbol: state.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(state.color)
                    .frame(width: 14)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("#\(String(pr.key.number)) · \(pr.author) · \(state.text)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if pr.ci != .none {
                    let glyph = Palette.ciGlyph(pr.ci)
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(glyph.color)
                        .help(Palette.ciLabel(pr.ci))
                        .accessibilityLabel(Palette.ciLabel(pr.ci))
                }
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
        .help("Show \(pr.key.repo) #\(pr.key.number)")
        .accessibilityElement(children: .combine)
    }

    static func state(_ glyph: PRGlyph) -> (symbol: String, color: Color, text: String) {
        let text = switch glyph {
        case .open: "open"
        case .draft: "draft"
        case .merged: "merged"
        case .closed: "closed"
        }
        return (Palette.prGlyph(glyph), Palette.prGlyphColor(glyph), text)
    }
}

/// Lays children out left to right, wrapping to a new line when the width runs out.
private struct FlowLayout: Layout {
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
