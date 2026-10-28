import AppKit
import SwiftUI
import PullBullKit

/// The read-only detail of one PR inside the popover: summary, description, checks, reviewers,
/// conversation and changed files, with Copy branch and Open on GitHub pinned at the bottom. It shows the
/// list data and the cached detail at once; `AppModel` refreshes the detail in place.
struct PRDetailView: View {
    let model: AppModel
    let key: PRKey

    @State private var checksExpanded = false
    @State private var filesExpanded = false

    /// Files listed before the rest fold behind "Show N more".
    private static let foldedFileCount = 5

    private var pr: PullRequest? { model.pullRequest(for: key) }
    private var detail: PRDetail? { model.detail(for: key) }
    private var fetch: DetailFetch? { model.detailFetch?.key == key ? model.detailFetch : nil }
    private var webURL: URL {
        pr?.url ?? URL(string: "https://github.com/\(key.repo)/pull/\(key.number)")!
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        summary(now: context.date)
                        if let detail {
                            if let error = fetch?.error { RefreshFailedNote(message: error) { model.reloadDetail() } }
                            sections(detail, now: context.date)
                        } else {
                            placeholder
                            if let pr { reviewersSection(reviews: pr.latestReviews, pr: pr) }
                        }
                    }
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            bottomBar
        }
        // Links in PR text are untrusted: only web links open, anything else is dropped.
        .environment(\.openURL, OpenURLAction { url in
            LinkPolicy.canOpen(url) ? .systemAction(url) : .discarded
        })
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            DetailBackButton(title: backTitle, action: model.closeDetail)
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
                DetailIconButton(symbol: "arrow.clockwise", help: "Refresh", action: model.reloadDetail)
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
        if let title = model.askReturn.backTitle { return title }
        switch model.detailReturnRoute {
        case .issueDetail(let issue): return "#\(issue.number)"
        case .search: return "Search"
        case .list, .ask, .detail: return model.selectedTabTitle
        }
    }

    private var repoName: String {
        key.repo.split(separator: "/").last.map(String.init) ?? key.repo
    }

    // MARK: Summary

    private func summary(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pr?.title ?? model.linkedPR(for: key)?.title ?? "\(key.repo) #\(key.number)")
                .font(.system(size: 15, weight: .semibold))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let pr {
                HStack(spacing: 8) {
                    StatePill(pr: pr)
                    HStack(spacing: 6) {
                        AvatarView(login: pr.author, url: pr.authorAvatarURL, size: 20)
                        Text("\(pr.author) opened \(RelativeAge.ago(pr.createdAt, now: now))")
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    // Equal priority: a chip that fits keeps its width and the other takes the rest; when
                    // neither fits they split the line, so neither collapses.
                    BranchChip(name: pr.headRef)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("into")
                    BranchChip(name: pr.baseRef)
                }
                .padding(.top, 10)
                if pr.state == .open && pr.hasConflicts {
                    ConflictLine(baseRef: pr.baseRef)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: Sections

    /// Open PRs lead with status (checks, reviewers); merged and closed ones keep the description first.
    @ViewBuilder private func sections(_ detail: PRDetail, now: Date) -> some View {
        if pr?.state == .open {
            statusSections(detail)
            descriptionSection(detail)
        } else {
            descriptionSection(detail)
            statusSections(detail)
        }
        conversationSection(detail.comments, now: now)
        filesSection(detail)
    }

    @ViewBuilder private func statusSections(_ detail: PRDetail) -> some View {
        checksSection(detail)
        if let pr {
            reviewersSection(reviews: detail.reviews, pr: pr)
        } else if !detail.reviews.isEmpty {
            reviewersSection(reviews: detail.reviews, pr: nil)
        }
    }

    private func descriptionSection(_ detail: PRDetail) -> some View {
        // Prose straight on the material at the section gutter, not boxed in a card: cards are for structured data.
        DetailSection(title: "Description") {
            let body = detail.body.trimmingCharacters(in: .whitespacesAndNewlines)
            Group {
                if body.isEmpty {
                    Text("No description provided.")
                        .foregroundStyle(.secondary)
                } else {
                    DescriptionText(source: body)
                }
            }
            .font(.system(size: 12.5))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checksSection(_ detail: PRDetail) -> some View {
        let checks = detail.checks
        let order: [CIState] = [.failure, .pending, .success, .skipped, .none]
        let sorted = order.flatMap { state in checks.filter { $0.state == state } }
        // On an open PR a green run folds to its summary; anything failed or running stays open.
        let folded = pr?.state == .open && !checksExpanded && !checks.isEmpty
            && checks.allSatisfy { [.success, .skipped, .none].contains($0.state) }
        // A folded list that never passed anything (all skipped) keeps the skipped glyph, not a check mark.
        let foldedState: CIState = checks.contains { $0.state == .success } ? .success : .skipped
        return DetailSection(title: "Checks", summary: Self.checksSummary(checks)) {
            DetailCard {
                if sorted.isEmpty {
                    EmptyLine(text: "No checks")
                } else if folded {
                    Button { checksExpanded = true } label: {
                        HStack(spacing: 8) {
                            let glyph = Palette.ciGlyph(foldedState)
                            Image(systemName: glyph.symbol)
                                .font(.system(size: 12))
                                .foregroundStyle(glyph.color)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text("No checks failed")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("No checks failed, show all checks")
                } else {
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, check in
                        if index > 0 { CardDivider() }
                        CheckLine(check: check)
                    }
                }
            }
            if detail.checksTruncated {
                TruncationNote(shown: checks.count, total: detail.checkTotal, noun: "checks", url: webURL)
            }
        }
    }

    static func checksSummary(_ checks: [Check]) -> String? {
        let parts: [(CIState, String)] = [
            (.failure, "failed"), (.pending, "running"), (.success, "passed"), (.skipped, "skipped"),
        ]
        let text = parts.compactMap { state, word -> String? in
            let n = checks.filter { $0.state == state }.count
            return n > 0 ? "\(n) \(word)" : nil
        }
        return text.isEmpty ? nil : text.joined(separator: " · ")
    }

    private func reviewersSection(reviews: [Review], pr: PullRequest?) -> some View {
        let entries = ReviewerEntry.entries(reviews: reviews, requests: pr?.reviewRequests ?? [], author: pr?.author)
        let me = model.snapshot?.org.viewer ?? model.settings.account
        return DetailSection(title: "Reviewers") {
            DetailCard {
                if entries.isEmpty {
                    EmptyLine(text: "No reviewers")
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { CardDivider() }
                        ReviewerLine(entry: entry, isMe: !entry.isTeam && entry.name.caseInsensitiveCompare(me ?? "") == .orderedSame)
                    }
                }
            }
        }
    }

    private func conversationSection(_ comments: [Comment], now: Date) -> some View {
        let total = max(pr?.commentCount ?? 0, comments.count)
        return DetailSection(title: "Conversation", summary: total == 1 ? "1 comment" : "\(total) comments") {
            VStack(alignment: .leading, spacing: 10) {
                if comments.isEmpty {
                    Text("No comments")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(comments.enumerated()), id: \.offset) { _, comment in
                        CommentLine(comment: comment, now: now)
                    }
                }
                if total > comments.count {
                    HStack(spacing: 4) {
                        Text("Showing the first \(comments.count) of \(total) ·")
                        Link("view on GitHub", destination: webURL)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 28)
                }
            }
        }
    }

    private func filesSection(_ detail: PRDetail) -> some View {
        let files = detail.files
        let total = detail.fileTotal
        let count = total == 1 ? "1 file" : "\(total) files"
        let summary = "+\(detail.additionsTotal) −\(detail.deletionsTotal) · \(count)"
        let blocks = DiffstatBlocks(additions: detail.additionsTotal, deletions: detail.deletionsTotal)
        return DetailSection(title: "Files changed", summary: summary) {
            DetailCard {
                if files.isEmpty {
                    EmptyLine(text: "No files changed")
                } else {
                    let hidden = max(0, files.count - Self.foldedFileCount)
                    let visible = filesExpanded ? files : Array(files.prefix(Self.foldedFileCount))
                    ForEach(Array(visible.enumerated()), id: \.offset) { index, file in
                        if index > 0 { CardDivider() }
                        FileLine(file: file)
                    }
                    if hidden > 0 {
                        CardDivider()
                        FoldToggle(
                            title: filesExpanded ? "Show fewer" : "Show \(hidden) more",
                            accessibilityLabel: filesExpanded ? "Show fewer files" : "Show \(hidden) more files"
                        ) { filesExpanded.toggle() }
                    }
                }
            }
            if detail.filesTruncated {
                TruncationNote(
                    shown: files.count, total: total, noun: "files", url: webURL.appendingPathComponent("files"))
            }
        } accessory: {
            DiffstatBar(blocks: blocks)
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
                Button("Retry", action: model.reloadDetail)
                    .controlSize(.small)
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .frame(maxWidth: .infinity)
        } else {
            DetailSkeleton(layout: pr?.state == .open ? .checks : .prose)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if let pr { CopyBranchButton(pr: pr) }
            OutlinedIconButton(name: "Open on GitHub", systemImage: "arrow.up.right.square") {
                NSWorkspace.shared.open(webURL)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: - Reviewers

struct ReviewerEntry: Identifiable, Equatable {
    enum Status: Equatable {
        case requested
        case reviewed(ReviewState)
    }

    let name: String
    let isTeam: Bool
    let status: Status
    var id: String { (isTeam ? "team:" : "user:") + name.lowercased() }

    /// Submitted reviews, with a pending request taking precedence (a re-request means a new review is
    /// wanted), then requested reviewers and teams that have not reviewed. The author is left out.
    static func entries(reviews: [Review], requests: [Reviewer], author: String?) -> [ReviewerEntry] {
        let requestedUsers = requests.compactMap { reviewer -> String? in
            if case .user(let login) = reviewer { return login }
            return nil
        }
        let requestedTeams = requests.compactMap { reviewer -> String? in
            if case .team(let slug) = reviewer { return slug }
            return nil
        }
        func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        var result: [ReviewerEntry] = []
        for review in reviews where !(author.map { same($0, review.author) } ?? false) {
            guard !result.contains(where: { same($0.name, review.author) }) else { continue }
            let requested = requestedUsers.contains { same($0, review.author) }
            result.append(ReviewerEntry(
                name: review.author, isTeam: false, status: requested ? .requested : .reviewed(review.state)))
        }
        for login in requestedUsers where !result.contains(where: { same($0.name, login) }) {
            result.append(ReviewerEntry(name: login, isTeam: false, status: .requested))
        }
        for slug in requestedTeams {
            result.append(ReviewerEntry(name: slug, isTeam: true, status: .requested))
        }
        return result
    }
}

private struct ReviewerLine: View {
    let entry: ReviewerEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 8) {
            if entry.isTeam {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Palette.strongFill))
                    .accessibilityHidden(true)
            } else {
                AvatarView(login: entry.name, url: URL(string: "https://github.com/\(entry.name).png"), size: 20)
            }
            HStack(spacing: 4) {
                Text(entry.name)
                if isMe { Text("(you)").foregroundStyle(.secondary) }
                if entry.isTeam { Text("team").foregroundStyle(.secondary) }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            let look = Self.look(entry.status)
            Pill(symbol: look.symbol, text: look.text, foreground: look.color, fill: look.fill, symbolColor: look.symbolColor)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .accessibilityElement(children: .combine)
    }

    /// Gray for every state except changes requested (orange) and the approved check (green glyph,
    /// gray text); each state has its own glyph.
    static func look(_ status: ReviewerEntry.Status)
        -> (symbol: String, text: String, color: Color, fill: Color, symbolColor: Color?)
    {
        switch status {
        case .requested: ("clock", "Requested", .secondary, Palette.fill, nil)
        case .reviewed(.approved): ("checkmark", "Approved", .secondary, Palette.fill, Palette.approved)
        case .reviewed(.changesRequested):
            ("arrow.uturn.backward", "Changes requested", Palette.changesRequested,
             Palette.changesRequested.opacity(0.12), nil)
        case .reviewed(.commented): ("bubble.left", "Commented", .secondary, Palette.fill, nil)
        case .reviewed(.dismissed): ("minus.circle", "Dismissed", .secondary, Palette.fill, nil)
        case .reviewed(.pending): ("ellipsis", "Pending", .secondary, Palette.fill, nil)
        }
    }
}

// MARK: - Pieces

/// Long descriptions fold to their first lines so the checks and reviewers stay in reach.
private struct DescriptionText: View {
    let source: String
    @State private var expanded = false

    private static let foldedLines = 10
    private static let foldedHeight: CGFloat = 170
    private var isLong: Bool {
        source.count > 600 || source.split(separator: "\n", omittingEmptySubsequences: false).count > Self.foldedLines
    }
    private var folded: Bool { isLong && !expanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarkdownText(source)
                .textSelection(.enabled)
                .frame(maxHeight: folded ? Self.foldedHeight : nil, alignment: .top)
                .clipped()
                .mask {
                    if folded {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.black
                    }
                }
            if isLong {
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
        }
    }
}

/// "Conflicts with main · resolve on GitHub" under the branches: an amber triangle, gray text.
private struct ConflictLine: View {
    let baseRef: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.amberGlyph)
                .accessibilityHidden(true)
            Text("Conflicts with \(baseRef) · resolve on GitHub")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12))
        .foregroundStyle(Palette.secondaryText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Merge conflicts with \(baseRef), resolve on GitHub")
    }
}

private struct CheckLine: View {
    let check: Check

    var body: some View {
        let glyph = Palette.ciGlyph(check.state)
        let line = HStack(spacing: 8) {
            Image(systemName: glyph.symbol)
                .font(.system(size: 12))
                .foregroundStyle(glyph.color)
                .frame(width: 14)
                .accessibilityLabel(Self.label(check.state))
            Text(check.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.label(check.state))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let url = check.url, LinkPolicy.canOpen(url) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
        .contentShape(Rectangle())

        // Status contexts carry any URL an integration set; only web links open.
        if let url = check.url, LinkPolicy.canOpen(url) {
            Button { NSWorkspace.shared.open(url) } label: { line }
                .buttonStyle(.plain)
                .help("Open \(check.name)")
        } else {
            line
        }
    }

    static func label(_ state: CIState) -> String {
        switch state {
        case .success: "passed"
        case .failure: "failed"
        case .pending: "running"
        case .skipped: "skipped"
        case .none: "no result"
        }
    }
}

/// "Showing first 100 of 140 files · view on GitHub" under a list the API cut short.
private struct TruncationNote: View {
    let shown: Int
    let total: Int
    let noun: String
    let url: URL

    var body: some View {
        HStack(spacing: 4) {
            Text("Showing first \(shown) of \(total) \(noun) ·")
                .monospacedDigit()
            Link("view on GitHub", destination: url)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.leading, 2)
    }
}

/// The link-styled "Show more" button row at the foot of a folded list.
private struct FoldToggle: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        HStack {
            Button(title, action: action)
                .buttonStyle(.link)
                .font(.system(size: 11, weight: .medium))
                .accessibilityLabel(accessibilityLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
    }
}

/// Leads with the file name so a file is found by name; the directory follows, dimmed and cut from the head
/// so its innermost folders stay visible. The counts sit in a fixed column so they line up down the card.
/// GitHub's five-block bar after the Files changed summary: green additions, red deletions, gray
/// for none. Hidden from VoiceOver, since the summary already reads the numbers.
private struct DiffstatBar: View {
    let blocks: DiffstatBlocks

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<DiffstatBlocks.total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(at: index))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(at index: Int) -> Color {
        if index < blocks.additions { return Palette.approved }
        if index < blocks.additions + blocks.deletions { return Palette.closedText }
        return Palette.strongFill
    }
}

private struct FileLine: View {
    let file: ChangedFile

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(file.fileName)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if !file.directory.isEmpty {
                    Text(file.directory)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(file.path)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(file.path)
            Text("+\(file.additions) −\(file.deletions)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)
                .accessibilityLabel("\(file.additions) additions, \(file.deletions) deletions")
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
    }
}

/// One line, truncated in the middle; the tooltip and VoiceOver always get the full name.
private struct BranchChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Palette.fill))
            .textSelection(.enabled)
            .help(name)
            .accessibilityLabel(name)
    }
}

private struct CopyBranchButton: View {
    let pr: PullRequest
    @State private var copied = false

    var body: some View {
        OutlinedIconButton(
            name: copied ? "Branch name copied" : "Copy branch \(pr.headRef)",
            systemImage: copied ? "checkmark" : "doc.on.doc"
        ) {
            PRActions.copyBranch(pr)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }
}
