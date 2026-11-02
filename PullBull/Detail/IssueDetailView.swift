import AppKit
import SwiftUI
import PullBullKit

/// The detail of one issue inside the popover: state and author, a board card (Status, Assignees, Labels,
/// each changeable where offered), the pull requests that close it, the description and the last two
/// comments, with the comment field, View on board and Open on GitHub pinned at the bottom. It shows the
/// list data and the cached detail at once; `AppModel` refreshes the detail in place.
struct IssueDetailView: View {
    let model: AppModel
    let key: PRKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The list copy: on the board it carries the Status and the board item.
    private var listIssue: BoardIssue? { model.issue(for: key) }
    private var detail: IssueDetail? { model.issueDetails[key] }
    /// The freshest row fields: the detail's, else the list's, with pending edits laid over them.
    private var issue: BoardIssue? { (detail?.issue).map(model.edits.overrides.apply(to:)) ?? listIssue }
    private var fetch: DetailFetch? { model.issueDetailFetch?.key == key ? model.issueDetailFetch : nil }
    private var webURL: URL { issue?.url ?? GitHubLinks.issue(key) }
    private var isOnBoard: Bool { model.shownSnapshot?.boardIssues.contains { $0.key == key } == true }
    /// Only for an issue on the board; another issue would land on the board with no item open.
    private var boardURL: URL? {
        guard let snapshot = model.shownSnapshot, let board = snapshot.board,
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
                            DescriptionSection(source: detail.body)
                            conversationSection(detail, now: context.date)
                        } else {
                            placeholder
                        }
                    }
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // An edit of the sets grows or shrinks the card; what's below it slides, not jumps.
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: issue?.assignees)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: issue?.labels)
                }
            }
            .frame(maxHeight: .infinity)
            bottomBar
                // The failure line sits on top of it, following the comment field as it grows.
                .detailBottomInset(for: key)
        }
        // Links in issue text are untrusted: only web links open, anything else is dropped.
        .environment(\.openURL, OpenURLAction { url in
            LinkPolicy.canOpen(url) ? .systemAction(url) : .discarded
        })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            DetailBackButton(
                title: backTitle, position: model.detailWalk?.position(showing: key, kind: .issue),
                action: model.closeIssueDetail)
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
                // Clear of the back button's "2 of 6" too, so the title doesn't move when it shows.
                .padding(.horizontal, 96)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private var backTitle: String {
        model.askReturn.backTitle ?? (model.issueDetailReturnRoute == .search ? "Search" : model.selectedTabTitle)
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
                            Byline(parts: OpenedLine.parts(
                                author: author, opened: issue.createdAt, updated: issue.updatedAt,
                                ended: issue.isOpen
                                    ? nil : EndedAge.label(state: .closed, closedAt: issue.closedAt, now: now),
                                now: now))
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

    // MARK: Board card

    private func boardCard(_ issue: BoardIssue) -> some View {
        let me = model.snapshot?.org.viewer ?? model.settings.account ?? ""
        let status = model.boardStatus(for: key)
        return DetailSection(title: (isOnBoard ? model.snapshot?.boardTitle : nil) ?? "Details") {
            DetailCard {
                if let status {
                    let color = model.shownSnapshot?.boardStatusOptions?.first { $0.id == status.optionId }?.color
                    statusRow(name: status.name) { StatusDot(color: color) }
                    CardDivider()
                } else if !isOnBoard, model.snapshot?.boardStatus == .available {
                    statusRow(name: "Not on board") { statusGlyph(BoardStatusGlyph.notOnBoard) }
                    CardDivider()
                } else if model.isStatusOffered(for: key) {
                    // On the board without a Status: still the place to set one.
                    statusRow(name: "No status") { statusGlyph("circle.dotted") }
                    CardDivider()
                }
                SetEditRow(model: model, key: key, field: .assignees) {
                    if issue.assignees.isEmpty {
                        EmptyValue(text: "No one")
                    } else {
                        AssigneeFlow(assignees: issue.assignees, me: me)
                    }
                }
                CardDivider()
                SetEditRow(model: model, key: key, field: .labels) {
                    if issue.labels.isEmpty {
                        EmptyValue(text: "None")
                    } else {
                        DetailLabels(labels: issue.labels, color: issue.labelColor(at:))
                    }
                }
            }
        }
    }

    /// Clickable where Status is offered: it opens the Status picker here.
    @ViewBuilder private func statusRow(name: String, @ViewBuilder mark: () -> some View) -> some View {
        let mark = mark()
        let row = CardRow(name: "Status") {
            HStack(spacing: 6) {
                mark
                Text(name)
                    .lineLimit(1)
            }
        }
        if model.isStatusOffered(for: key) {
            Button { model.openStatusPicker(for: key) } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Set Status (⌥⌘S)")
            .accessibilityHint("Opens the Status picker")
            .editPickerAnchor(for: key, field: .status, model: model)
        } else {
            row
        }
    }

    private func statusGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    // MARK: Sections

    @ViewBuilder private func linkedPRsSection(_ prs: [LinkedPR]) -> some View {
        if prs.isEmpty {
            // As the PR page's empty sections: the heading, then the empty line in a card.
            DetailSection(title: "Linked pull requests") {
                DetailCard { EmptyLine(text: "No linked pull requests") }
            }
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

    private func conversationSection(_ detail: IssueDetail, now: Date) -> some View {
        // The page shows the newest two, comments posted from here included until the detail holds them.
        let shown = model.postedComments.conversation(
            for: key, held: detail.lastComments, total: detail.commentTotal, keep: 2, now: now)
        return ConversationSection(
            comments: shown.comments, total: shown.total, earlier: shown.earlier,
            sendingIndex: shown.sendingIndex, webURL: webURL, now: now)
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

    /// The comment field, View on board and Open on GitHub, on one row.
    private var bottomBar: some View {
        CommentField(model: model, key: key, isPullRequest: false) {
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
    }
}

// MARK: - Pieces

/// Open gray, completed muted purple, not planned gray; each with its own glyph.
private struct IssueStatePill: View {
    let issue: BoardIssue

    var body: some View {
        switch issue.glyph {
        case .open:
            Pill(symbol: Palette.issueGlyph(.open).symbol, text: "Open", foreground: Palette.pillText, fill: Palette.strongFill)
        case .completed, .notPlanned:
            IssueEndedPill(glyph: issue.glyph, symbol: Palette.issueGlyph(issue.glyph).symbol)
        }
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
