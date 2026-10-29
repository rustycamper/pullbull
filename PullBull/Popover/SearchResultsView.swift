import SwiftUI
import PullBullKit

/// The current mode's search results in two groups (open and closed-or-merged PRs, or open and closed
/// issues), with an explicit state: "Searching…", the line pointing to the other mode when only its kind
/// matches, the no-match message, or the remote failure. Narrowed to a tab, the context line names it and
/// the no-match state offers everything instead.
struct SearchResultsView: View {
    let model: AppModel
    let now: Date

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    contextLine
                    askLine
                    if let results = model.searchResults, !results.isEmpty(in: model.mode) {
                        if let message = results.failure(in: model.mode) {
                            FailureBanner(message: message)
                        }
                        groups(results)
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

    private var states: [StateFilter] { model.searchQuery.states }

    private var statuses: [BoardStatusFilter] { model.searchQuery.statuses }

    private var viewer: String { model.snapshot?.org.viewer ?? "" }

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

    private var contextLine: some View {
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
                .lineLimit(1)
                .accessibilityLabel(contextLabel)
            Spacer(minLength: 0)
            if let results = model.searchResults, results.phase == .searching, !results.isEmpty(in: model.mode) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Searching GitHub")
            }
            // Ask is offered only once a key is saved; ⌥⌘↩ is the one way to send anything to Anthropic.
            if model.offersAsk {
                Text("⌥⌘↩ Ask AI")
                    .fixedSize()
                    .accessibilityLabel("Option Command Return to Ask AI")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .frame(minHeight: 24)
    }

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

    private var matchCount: Int { model.searchItemKeys.count }

    private var contextText: String {
        // The filter row above names the focus.
        if let scopeTitle {
            return SearchContext.narrowedText(model.searchQuery, tab: scopeTitle, matches: matchCount)
        }
        // A pasted link names its own repository, whatever the focus.
        if case .item(let repo, let n) = model.searchQuery { return "\(model.displayName(of: repo)) #\(n)" }
        if !logins.isEmpty || !labels.isEmpty || !states.isEmpty || !statuses.isEmpty {
            return SearchContext.text(
                logins: logins, labels: labels, states: states, statuses: statuses, words: words, org: org,
                repo: focusName,
                startedOnTab: model.searchStartedOnTab?.title)
        }
        // The filter row above names the focus too.
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
        guard !logins.isEmpty || !labels.isEmpty || !states.isEmpty || !statuses.isEmpty else { return contextText }
        return SearchContext.accessibilityLabel(
            logins: logins, labels: labels, states: states, statuses: statuses, words: words, org: org,
            repo: focusName)
    }

    @ViewBuilder private var stateMessage: some View {
        let results = model.searchResults
        if results == nil, model.snapshot == nil, let error = model.status.error {
            // Nothing to search yet because loading failed: say so instead of searching forever.
            failure(
                model.message(for: error),
                symbol: error == .offline ? "wifi.slash" : "exclamationmark.triangle")
        } else if let fallback = model.searchFallback {
            fallbackLine(fallback)
        } else if let message = results?.failure(in: model.mode) {
            failure(message, symbol: "wifi.slash")
        } else if let scopeTitle, let results, results.phase == .done, results.isEmpty(in: model.mode) {
            narrowedEmpty(scopeTitle)
        } else if let message = results?.emptyMessage(
            org: focusName ?? org, query: model.searchQuery, scope: model.snapshot?.scope, mode: model.mode) {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Palette.fill))
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let unknown = unknownToken {
                    Text("\(unknown) isn't on anything PullBull has loaded")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // With a key saved, Ask may find it from a looser description.
                if model.offersAsk {
                    Text("Try other words, or ⌥⌘↩ to Ask AI.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 40)
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
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Palette.fill))
                .accessibilityHidden(true)
            Text(SearchContext.noMatches(inTab: tab))
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Search everything") { model.searchEverything() }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .help(model.mode == .issues
                    ? "Search every issue for this query" : "Search every pull request for this query")
        }
        .padding(.horizontal, 40)
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

    private func failure(_ message: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Palette.amberGlyph)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
    }

    // MARK: Groups

    @ViewBuilder private func groups(_ results: SearchResults) -> some View {
        switch model.mode {
        case .pullRequests: prGroups(results)
        case .issues: issueGroups(results)
        }
    }

    @ViewBuilder private func prGroups(_ results: SearchResults) -> some View {
        prGroup("Open pull requests", results.openPRs)
        prGroup("Closed and merged pull requests", results.closedPRs)
    }

    @ViewBuilder private func issueGroups(_ results: SearchResults) -> some View {
        issueGroup("Open issues", results.openIssues)
        issueGroup("Closed issues", results.closedIssues)
    }

    @ViewBuilder private func prGroup(_ title: String, _ prs: [PullRequest]) -> some View {
        if !prs.isEmpty {
            SearchGroupHeader(title: title, count: prs.count)
            ForEach(prs) { pr in
                SearchPRRow(
                    pr: pr, words: words, labels: labels, role: role(of: pr), viewer: viewer, now: now,
                    selected: model.searchSelection == pr.key, flashing: model.rowFlash.key == pr.key
                ) {
                    if PRActions.commandClicked { model.openSearchResultOnGitHub(pr) } else { model.openSearchResult(pr) }
                }
                .prContextMenu(
                    pr, focus: FocusMenuItem(model: model, repo: pr.key.repo),
                    person: .person(model: model, login: pr.author))
                .id(pr.key)
            }
        }
    }

    @ViewBuilder private func issueGroup(_ title: String, _ issues: [BoardIssue]) -> some View {
        if !issues.isEmpty {
            SearchGroupHeader(title: title, count: issues.count)
            ForEach(issues) { issue in
                SearchIssueRow(
                    issue: issue, words: words, labels: labels, role: role(of: issue), now: now,
                    selected: model.searchSelection == issue.key, flashing: model.rowFlash.key == issue.key
                ) {
                    if PRActions.commandClicked { model.openSearchResultOnGitHub(issue) } else { model.openSearchResult(issue) }
                }
                .issueContextMenu(
                    issue, focus: FocusMenuItem(model: model, repo: issue.key.repo),
                    person: .person(model: model, login: issue.author))
                .id(issue.key)
            }
        }
    }
}

/// The result count (or the arrow-key hint after typing anywhere) and the Return / Esc hints, in place of
/// the list footer while searching.
struct SearchFooter: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            // "Copied" takes the leading hint's or count's place for a moment.
            if let copied = CopyConfirmation.shared.message {
                CopiedNote(message: copied)
                Spacer()
                hint(["↩"], returnLabel)
                hint(["esc"], model.searchStartedOnTab.map { "Back to \($0.title)" } ?? "Clear")
            } else if let tab = model.searchStartedOnTab {
                hint(["↑", "↓"], "Select")
                Spacer()
                hint(["↩"], returnLabel)
                hint(["esc"], "Back to \(tab.title)")
            } else {
                Text(countText)
                    .monospacedDigit()
                Spacer()
                hint(["↩"], returnLabel)
                hint(["esc"], "Clear")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .top) { Hairline() }
    }

    private var countText: String {
        let count = model.searchItemKeys.count
        guard let results = model.searchResults, count > 0 || results.phase != .searching else { return "" }
        return count == 1 ? "1 result" : "\(count) results"
    }

    /// Return follows the fallback line when it is all there is.
    private var returnLabel: String {
        guard let target = model.searchFallback?.target else { return "Open" }
        return target == .issues ? "Show issues" : "Show pull requests"
    }

    private func hint(_ keys: [String], _ label: String) -> some View { KeyHint(keys: keys, label: label) }
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

private struct SearchGroupHeader: View {
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count {
                Text("\(count)")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

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

private struct SearchPRRow: View {
    let pr: PullRequest
    let words: [String]
    /// The labels a `~label` search asks for, whose chips lead.
    let labels: [String]
    let role: String?
    let viewer: String
    let now: Date
    let selected: Bool
    let flashing: Bool
    let action: () -> Void

    private var own: Bool { pr.author.caseInsensitiveCompare(viewer) == .orderedSame }

    var body: some View {
        let open = pr.state == .open
        SearchRowButton(selected: selected, flashing: flashing, action: action) {
            HStack(alignment: .top, spacing: 10) {
                glyph
                    .font(.system(size: 13))
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Highlight.title(pr.title, words: words))
                        .font(.system(size: 13))
                        .lineSpacing(1)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(open && !pr.isDraft ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                        // On the title alone: a row-wide tip would cover the chips' and glyphs' own.
                        .help(pr.title)
                    meta
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
                    .padding(.top, 1)
            }
        }
    }

    @ViewBuilder private var glyph: some View {
        switch pr.state {
        case .merged:
            Image(symbol: Palette.prGlyph(pr.glyph))
                .foregroundStyle(Palette.mergedText)
                .accessibilityLabel("Merged pull request")
        case .closed:
            Image(symbol: Palette.prGlyph(pr.glyph))
                .foregroundStyle(Palette.closedText)
                .accessibilityLabel("Closed pull request")
        case .open:
            Image(symbol: Palette.prGlyph(pr.glyph))
                .foregroundStyle(.secondary)
                .accessibilityLabel(pr.isDraft ? "Draft pull request" : "Open pull request")
        }
    }

    @ViewBuilder private var trailing: some View {
        switch pr.state {
        case .merged: EndedPill(merged: true)
        case .closed: EndedPill(merged: false)
        // Someone else's failure is gray, as on Team.
        case .open: CIGlyph(state: pr.ci, muted: !own)
        }
    }

    /// One line at a fixed height, like a tab row's: the review signals that hold on any tab, then label
    /// chips, which drop off the end into "+N". Under pressure the repo name gives way first; the age and
    /// counts never truncate.
    private var meta: some View {
        let chips = RowChips(searchResult: pr, viewer: viewer)
        let labels = LabelChipSet(pr, first: self.labels)
        return ChipsThatFit(set: labels) { fitting in
            metaLine(chips: chips, labels: labels, fitting: fitting)
        }
        .metaLineStyle()
        .frame(height: 16)
    }

    private func metaLine(chips: RowChips, labels: LabelChipSet, fitting: ChipFit) -> some View {
        HStack(spacing: 5) {
            if pr.isDraft { DraftPill().fixedSize() }
            RepoNumber(key: pr.key)
                .layoutPriority(-1)
            MetaDot()
            Text(pr.author)
            MetaDot()
            Text(when)
                .fixedSize()
            if let role {
                MetaDot()
                Text(role)
            }
            ForEach(chips.info, id: \.text) { info in
                MetaDot()
                MetaInfo(info: info)
            }
            if pr.commentCount > 0 {
                CommentCount(count: pr.commentCount)
                    .padding(.leading, 4)
            }
            if let action = chips.action {
                ActionCapsule(action: action)
                    .padding(.leading, 4)
            }
            LabelChips(set: labels, fit: fitting)
        }
    }

    private var when: String {
        EndedAge.text(state: pr.state, closedAt: pr.closedAt, now: now)
            ?? RelativeAge.short(from: pr.updatedAt, to: now)
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
    let selected: Bool
    let flashing: Bool
    let action: () -> Void

    var body: some View {
        let glyph = Palette.issueGlyph(issue.glyph)
        SearchRowButton(selected: selected, flashing: flashing, action: action) {
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
                        .foregroundStyle(issue.isOpen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .help(issue.title)
                    IssueMetaLine(issue: issue, now: now, role: role, wantedLabels: labels)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let status = issue.status?.name {
                    Pill(symbol: nil, text: status, foreground: Palette.secondaryText, fill: Palette.fill)
                        .accessibilityLabel("Status: \(status)")
                }
            }
        }
    }
}

private struct SearchRowButton<Label: View>: View {
    let selected: Bool
    let flashing: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .modifier(RowFill(cornerRadius: 7, selected: selected, hovering: hovering, flashing: flashing))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private enum Highlight {
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
    /// The Ask line's place under the context line: small, muted, and as wide as the rows.
    func askLineStyle() -> some View {
        font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
    }
}
