import SwiftUI
import PullBullKit

/// The current mode's search results laid out as the reference tab lays out its list (its repo, author
/// or Status groups and headers, and Done), then the merged and closed ones under a folding Closed
/// section, with an explicit state: "Searching…", the line pointing to the other mode when only its kind
/// matches, the no-match message, or the remote failure. Narrowed to a tab, the footer's summary names it and
/// the no-match state offers everything instead.
struct SearchResultsView: View {
    let model: AppModel
    let now: Date

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Only the groups' headers pin; the Ask line and banners scroll away.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    askLine
                    if let results = model.searchResults, !results.isEmpty(in: model.mode) {
                        if let message = results.failure(in: model.mode) {
                            FailureBanner(message: message)
                        }
                        groups
                        if let note = results.truncationNote {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 10)
                        }
                    } else {
                        // The other kind's matches stand in for this mode's; the failure still says what's missing.
                        if model.searchFallback != nil, let message = model.searchResults?.failure(in: model.mode) {
                            FailureBanner(message: message)
                        }
                        stateMessage
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                    }
                }
                .padding(.horizontal, Metrics.rowInset)
                .padding(.bottom, 6)
            }
            .onChange(of: model.searchSelection) { _, key in
                guard let key else { return }
                proxy.scrollTo(key)
            }
        }
    }

    /// Where a number was looked up: the org, or "your repos" in no-org mode.
    private var org: String {
        guard let snapshot = model.snapshot else { return model.settings.org ?? "" }
        return snapshot.scope.org ?? "your repos"
    }

    /// The focused repository's display name; nil unfocused.
    private var focusName: String? { model.repoFocus.map { model.displayName(of: $0.repo) } }

    private var words: [String] { model.searchQuery.words }

    private var logins: [String] { model.searchQuery.logins }

    private var labels: [String] { model.searchQuery.labels }

    private var viewer: String { model.snapshot?.org.viewer ?? model.settings.account ?? "" }

    /// The first `@` token's role on a row, as the muted suffix; nil without a token or a role.
    private func role(of pr: PullRequest) -> String? {
        guard let login = logins.first else { return nil }
        return PersonMatch.label(for: PersonMatch.roles(of: pr, login: login, viewer: viewer), author: nil)
    }

    private func role(of issue: BoardIssue) -> String? {
        guard let login = logins.first else { return nil }
        return PersonMatch.label(for: PersonMatch.roles(of: issue, login: login, viewer: viewer), author: issue.author)
    }

    // MARK: State

    /// "Asking…" while an Ask runs, else its failure or the no-key notice; the normal results stay below.
    @ViewBuilder private var askLine: some View {
        if model.asking != nil {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
                Text("Asking…")
                Spacer(minLength: 0)
            }
            .askLineStyle()
            .accessibilityElement(children: .combine)
        } else if let line = model.askErrorLine ?? model.askNotice {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .accessibilityHidden(true)
                Text(verbatim: line)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .askLineStyle()
            .accessibilityElement(children: .combine)
        }
    }

    /// The tab the results are narrowed to; nil for everything.
    private var scopeTitle: String? { model.searchScopeTitle }

    @ViewBuilder private var stateMessage: some View {
        let results = model.searchResults
        if results == nil, model.snapshot == nil, let error = model.status.error {
            // Nothing to search yet because loading failed: say so instead of searching forever.
            failure(
                model.message(for: error),
                symbol: error == .offline ? "wifi.slash" : "exclamationmark.triangle", help: "Retry (⌘R)",
                retry: { model.refresh() })
        } else if let fallback = model.searchFallback {
            fallbackLine(fallback)
        } else if let message = results?.failure(in: model.mode) {
            failure(message, symbol: "wifi.slash", retry: { model.retrySearch() })
        } else if let scopeTitle, let results, results.phase == .done, results.isEmpty(in: model.mode) {
            narrowedEmpty(scopeTitle)
        } else if let message = results?.emptyMessage(
            org: focusName ?? org, query: model.searchQuery, scope: model.snapshot?.scope, mode: model.mode) {
            ListStateView(symbol: "magnifyingglass", title: message) {
                if let unknown = unknownToken {
                    footerLine("\(unknown) isn't on anything PullBull has loaded")
                }
                // With a key saved, Ask may find it from a looser description.
                if model.offersAsk {
                    footerLine("Try other words, or ⌥⌘↩ to Ask AI.")
                }
            }
        } else {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Searching…")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    /// No match among the narrowed tab's items, with the way back to everything.
    private func narrowedEmpty(_ tab: String) -> some View {
        ListStateView(symbol: "magnifyingglass", title: SearchContext.noMatches(inTab: tab)) {
            Button("Search everything") { model.searchEverything() }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .help(model.mode == .issues
                    ? "Search every issue for this query" : "Search every pull request for this query")
        }
    }

    /// Only the other mode's kind matches: one quiet line in the empty message's place, which switches
    /// to that mode (as Return does), keeping the query.
    private func fallbackLine(_ fallback: CrossModeFallback) -> some View {
        Button { model.followSearchFallback() } label: {
            Text(fallback.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(fallback.target == .issues ? "Show issues" : "Show pull requests")
        .accessibilityLabel(fallback.accessibilityLabel)
        .padding(.horizontal, 40)
    }

    /// The first `@` name, else the first `~` label, that nothing PullBull has loaded carries.
    private var unknownToken: String? {
        if let login = logins.first(where: { $0.lowercased() != "me" && !model.people.contains($0) }) {
            return "@\(login)"
        }
        return labels.first { !model.labels.contains($0) }.map(SearchQuery.labelToken)
    }

    private func failure(
        _ message: String, symbol: String, help: String? = nil, retry: @escaping () -> Void
    ) -> some View {
        ListStateView(
            symbol: symbol, tone: .warning, title: message,
            action: .init(title: "Retry", help: help, disabled: model.status.isRefreshing, perform: retry))
    }

    private func footerLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Groups

    @ViewBuilder private var groups: some View {
        switch model.mode {
        case .pullRequests:
            if let layout = model.searchPRLayout { prGroups(layout) }
        case .issues:
            if let layout = model.searchIssueLayout { issueGroups(layout) }
        }
    }

    @ViewBuilder private func prGroups(_ layout: SearchPRLayout) -> some View {
        let rows = layout.contents.rows
        switch layout.grouping {
        case .repository:
            ForEach(ListNavigation.repoGroups(rows), id: \.repo) { group in
                Section {
                    prRows(group.rows.map(\.pr))
                } header: {
                    RepoGroupHeader(model: model, repo: group.repo, rows: group.rows, menus: .none)
                        .pinnedHeaderBackground()
                }
            }
        case .author:
            ForEach(ListNavigation.authorGroups(rows), id: \.author) { group in
                Section {
                    prRows(group.rows.map(\.pr))
                } header: {
                    AuthorGroupHeader(model: model, author: group.author, rows: group.rows, menus: .none)
                        .pinnedHeaderBackground()
                }
            }
        case .none:
            // Ungrouped rows have no header to clear.
            prRows(rows.map(\.pr), clearance: 0)
                .padding(.top, 6)
        }
        if !layout.ended.isEmpty {
            closedSection(title: "Closed and merged", count: layout.ended.count) {
                prRows(layout.ended)
            }
        }
    }

    @ViewBuilder private func issueGroups(_ layout: SearchIssueLayout) -> some View {
        let groups = layout.contents.groups
        ForEach(groups.filter { $0.kind != .done }) { group in
            // Under a focus the kit merges repo groups into one untitled group.
            if group.title.isEmpty {
                Color.clear.frame(height: 6)
                // No header pins above it, so there is none to clear.
                issueRows(group.issues, clearance: 0)
            } else {
                Section {
                    issueRows(group.issues)
                } header: {
                    // Lanes never fold while searching, so their headers have no chevron.
                    IssueGroupHeader(model: model, group: group, fold: nil, menus: .none)
                        .pinnedHeaderBackground()
                }
            }
        }
        if let done = groups.first(where: { $0.kind == .done }) {
            Section {
                if model.searchExpansion.done {
                    issueRows(done.issues)
                }
            } header: {
                ListSectionHeader(
                    glyph: "checkmark.circle", title: "Done", count: done.issues.count, note: "still open",
                    fold: .init(isOpen: model.searchExpansion.done) { model.toggleSearchDone() },
                    compact: model.settings.compact)
                    .pinnedHeaderBackground()
            }
        }
        if !layout.ended.isEmpty {
            closedSection(title: "Closed", count: layout.ended.count) {
                issueRows(layout.ended)
            }
        }
    }

    /// The merged and closed results under a hairline, folded with the header's chevron.
    @ViewBuilder private func closedSection<Rows: View>(
        title: String, count: Int, @ViewBuilder rows: () -> Rows
    ) -> some View {
        Hairline()
            .padding(.horizontal, 8)
            .padding(.top, 6)
        Section {
            if model.searchExpansion.closed {
                rows()
            }
        } header: {
            ListSectionHeader(
                glyph: nil, title: title, count: count,
                fold: .init(isOpen: model.searchExpansion.closed) { model.toggleSearchClosed() },
                compact: model.settings.compact)
                .pinnedHeaderBackground()
        }
    }

    private func prRows(_ prs: [PullRequest], clearance: CGFloat = PinnedHeader.clearance) -> some View {
        ForEach(prs) { pr in
            PRRow(
                model: model, row: Row(pr: pr, dimmed: false, counted: false),
                context: .search(words: words, role: role(of: pr), viewer: viewer),
                compact: model.settings.compact, now: now,
                selected: model.searchSelection == pr.key, wantedLabels: labels)
            .scrollTarget(pr.key, clearance: clearance)
        }
    }

    private func issueRows(_ issues: [BoardIssue], clearance: CGFloat = PinnedHeader.clearance) -> some View {
        ForEach(issues) { issue in
            SearchIssueRow(
                issue: issue, words: words, labels: labels, role: role(of: issue), now: now,
                compact: model.settings.compact,
                selected: model.searchSelection == issue.key, flashing: model.rowFlash.key == issue.key
            ) {
                if PRActions.commandClicked { model.openSearchResultOnGitHub(issue) } else { model.openSearchResult(issue) }
            }
            .issueContextMenu(
                issue, focus: FocusMenuItem(model: model, repo: issue.key.repo),
                person: .person(model: model, login: issue.author))
            .scrollTarget(issue.key, clearance: clearance)
        }
    }
}

/// What the search covers and how many match, then the Ask AI, Return and Esc hints, in place of the list
/// footer while searching. The Ask hint shows only when the whole line fits.
struct SearchFooter: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            // "Copied" takes the summary's place for a moment.
            if let copied = CopyConfirmation.shared.message {
                CopiedNote(message: copied)
                Spacer()
                hints
            } else {
                ViewThatFits(in: .horizontal) {
                    line(withAsk: model.offersAsk)
                    line(withAsk: false)
                }
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .top) { Hairline() }
    }

    private func line(withAsk: Bool) -> some View {
        HStack(spacing: 10) {
            SearchSummary(model: model)
            Spacer()
            if withAsk {
                // Ask is offered only once a key is saved; ⌥⌘↩ is the one way to send anything to Anthropic.
                Text("⌥⌘↩ Ask AI")
                    .fixedSize()
                    .accessibilityLabel("Option Command Return to Ask AI")
            }
            hints
        }
    }

    @ViewBuilder private var hints: some View {
        hint(["↩"], returnLabel)
        hint(["esc"], model.searchStartedOnTab.map { "Back to \($0.title)" } ?? "Clear")
    }

    /// Return follows the fallback line when it is all there is.
    private var returnLabel: String {
        guard let target = model.searchFallback?.target else { return "Open" }
        return target == .issues ? "Show issues" : "Show pull requests"
    }

    private func hint(_ keys: [String], _ label: String) -> some View { KeyHint(keys: keys, label: label) }
}

/// The footer's leading text: what the search covers and, once known, how many match, led by the
/// started-typing, person or label glyph, and trailed by a spinner while GitHub answers.
struct SearchSummary: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            if model.searchStartedOnTab != nil, scopeTitle == nil {
                Image(systemName: "keyboard")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
            }
            if let login = logins.first {
                AvatarView(login: model.people.display(login), url: model.people.avatarURL(login), size: 14)
                    .accessibilityHidden(true)
            } else if !labels.isEmpty {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
            }
            Text(contextText)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(-1)
                .accessibilityLabel(contextLabel)
            if let results = model.searchResults, results.phase == .searching, !results.isEmpty(in: model.mode) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Searching GitHub")
            }
        }
    }

    /// Where a number was looked up: the org, or "your repos" in no-org mode.
    private var org: String {
        guard let snapshot = model.snapshot else { return model.settings.org ?? "" }
        return snapshot.scope.org ?? "your repos"
    }

    /// The focused repository's display name; nil unfocused.
    private var focusName: String? { model.repoFocus.map { model.displayName(of: $0.repo) } }

    private var logins: [String] { model.searchQuery.logins }

    private var labels: [String] { model.searchQuery.labels }

    /// The tab the results are narrowed to; nil for everything.
    private var scopeTitle: String? { model.searchScopeTitle }

    private var matchCount: Int { model.searchMatchCount }

    /// The count of an unscoped search, once known; a narrowed text already ends with it.
    private var matches: Int? {
        guard let results = model.searchResults, matchCount > 0 || results.phase != .searching else { return nil }
        return matchCount
    }

    private var contextText: String {
        if let scopeTitle {
            return SearchContext.narrowedText(model.searchQuery, tab: scopeTitle, matches: matchCount)
        }
        return SearchContext.footerText(coverage, matches: matches)
    }

    /// What an unscoped search covers.
    private var coverage: String {
        // A pasted link names its own repository, whatever the focus.
        if case .item(let repo, let n) = model.searchQuery { return "\(model.displayName(of: repo)) #\(n)" }
        if let filter = model.searchQuery.filter {
            return SearchContext.text(
                filter: filter, org: org, repo: focusName, startedOnTab: model.searchStartedOnTab?.title)
        }
        // The filter row above names the focus.
        if let focusName {
            if case .number(let n) = model.searchQuery { return "#\(n) in \(focusName)" }
            if let tab = model.searchStartedOnTab { return "Started typing on \(tab.title) · searching \(focusName)" }
            return "Titles in \(focusName)"
        }
        // Before the first launch has found an org there is no name to show; no-org mode searches the
        // user's own repos.
        let personal = model.snapshot.map { $0.scope.org == nil } ?? false
        let repos = personal ? "your repos" : org.isEmpty ? "every repo" : "every \(org) repo"
        let scope = personal ? "your repos" : org.isEmpty ? "the organization" : org
        if case .number(let n) = model.searchQuery { return "#\(n) in \(repos)" }
        if let tab = model.searchStartedOnTab { return "Started typing on \(tab.title) · searching all of \(scope)" }
        return "Titles in all of \(scope)"
    }

    private var contextLabel: String {
        if let scopeTitle {
            return SearchContext.narrowedAccessibilityLabel(
                model.searchQuery, tab: scopeTitle, matches: matchCount, repo: focusName)
        }
        let label = model.searchQuery.filter.map {
            SearchContext.accessibilityLabel(filter: $0, org: org, repo: focusName)
        } ?? coverage
        return matches.map { label + ", " + SearchContext.matchCount($0) } ?? label
    }
}

/// The completion list's keys, in place of the search or list footer while the list is open.
struct CompletionFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            hint(["↑", "↓"], "Choose")
            hint(["↩", "⇥"], "Complete")
            hint(["esc"], "Close")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .top) { Hairline() }
    }

    private func hint(_ keys: [String], _ label: String) -> some View { KeyHint(keys: keys, label: label) }
}

/// A footer hint: keycaps, then what they do, read as one element.
private struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in Keycap { Text(key) } }
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A key drawn as a small outlined keycap.
struct Keycap<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Palette.secondaryText)
            .padding(.horizontal, 6)
            .frame(minWidth: 18, minHeight: 16)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.separator, lineWidth: 0.5))
    }
}

// MARK: - Rows

private struct FailureBanner: View {
    let message: String
    var symbol = "wifi.slash"

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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.amberFill))
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// An issue result: the state glyph, the highlighted title, the Issues list's meta line and a muted
/// board Status pill (search results are not grouped by Status).
private struct SearchIssueRow: View {
    let issue: BoardIssue
    let words: [String]
    /// The labels a `~label` search asks for, whose chips lead.
    let labels: [String]
    let role: String?
    let now: Date
    let compact: Bool
    let selected: Bool
    let flashing: Bool
    let action: () -> Void

    private var glyph: (symbol: String, color: Color, label: String) { Palette.issueGlyph(issue.glyph) }

    var body: some View {
        SearchRowButton(compact: compact, selected: selected, flashing: flashing, action: action) {
            if compact { compactBody } else { fullBody }
        }
    }

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(symbol: glyph.symbol)
                .font(.system(size: 13))
                .foregroundStyle(glyph.color)
                .frame(width: 20, height: 20)
                .accessibilityLabel(glyph.label)
            VStack(alignment: .leading, spacing: 0) {
                Text(Highlight.title(issue.title, words: words))
                    .font(.system(size: 13))
                    .lineSpacing(1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(titleStyle)
                    .fixedSize(horizontal: false, vertical: true)
                    // On the title alone: a row-wide tip would cover the chips' and glyphs' own.
                    .help(issue.title)
                IssueMetaLine(issue: issue, now: now, role: role, wantedLabels: labels)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            statusPill
        }
    }

    /// The tab rows' compact line, with the Status pill where a tab row has its assignees.
    private var compactBody: some View {
        CompactRowLayout(
            repoNumber: RepoNumber(key: issue.key, compact: true),
            age: IssueMetaLine.age(of: issue, now: now), ageWidth: issue.isOpen ? 24 : nil
        ) {
            Image(symbol: glyph.symbol)
                .font(.system(size: 11))
                .foregroundStyle(glyph.color)
                .frame(width: 16)
                .accessibilityLabel(glyph.label)
        } title: {
            Text(Highlight.title(issue.title, words: words))
                .foregroundStyle(titleStyle)
                .help(issue.title)
        } badges: {
            EmptyView()
        } trailing: {
            // Sized to fit, so the title truncates first.
            statusPill
                .fixedSize()
        }
    }

    private var titleStyle: AnyShapeStyle {
        issue.isOpen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    @ViewBuilder private var statusPill: some View {
        if let status = issue.status?.name {
            Pill(symbol: nil, text: status, foreground: Palette.secondaryText, fill: Palette.fill)
                .accessibilityLabel("Status: \(status)")
        }
    }
}

private struct SearchRowButton<Label: View>: View {
    /// A compact label brings its own height and padding (`CompactRowLayout`).
    let compact: Bool
    let selected: Bool
    let flashing: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, compact ? 0 : 8)
                .padding(.top, compact ? 0 : 7)
                .padding(.bottom, compact ? 0 : 8)
                .contentShape(Rectangle())
                .modifier(RowFill(
                    cornerRadius: compact ? 6 : 7, selected: selected, hovering: hovering, flashing: flashing))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

enum Highlight {
    /// The title with every query word in bold.
    static func title(_ title: String, words: [String]) -> AttributedString {
        var attributed = AttributedString(title)
        for word in words where !word.isEmpty {
            var searchStart = title.startIndex
            while let range = title.range(of: word, options: .caseInsensitive, range: searchStart..<title.endIndex) {
                if let attributedRange = Range(range, in: attributed) {
                    attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }
}

private extension View {
    /// The Ask line's place at the top of the results: small, muted, and as wide as the rows.
    func askLineStyle() -> some View {
        font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }
}
