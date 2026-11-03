import SwiftUI
import PullBullKit

/// The scrollable Issues All list: Assigned to you, You opened and Rest of the board, each under a pinned
/// header that folds, each issue once. Rows name their repository and show their board Status. A list still
/// loading shows its header over skeleton rows; one that failed with nothing kept, a "Couldn't load" line;
/// a kept list that didn't update, a warning on its header. Empty is said only of loaded lists.
struct IssueAllListView: View {
    @Bindable var model: AppModel
    let scoped: ScopedIssueList
    /// Every issue All lists, in any repository and at any age.
    let total: Int
    let now: Date

    private var list: IssueList { scoped.list }
    private var focus: ListFocus { model.listFocus }
    private var compact: Bool { model.settings.compact }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
            }
            .focusContextMenu(time: TimeFocusMenu(model: model))
            .scrollIndicators(.automatic)
            .onChange(of: model.listSelection) { _, key in
                guard let key else { return }
                proxy.scrollTo(key)
            }
            // A new sort keeps the selected row selected and in view.
            .onChange(of: model.settings.sorts) { _, _ in
                guard let key = model.listSelection else { return }
                proxy.scrollTo(key)
            }
            // An edit moved the selected row to another section.
            .onChange(of: model.editScrollRequest) { _, _ in
                guard let key = model.listSelection else { return }
                proxy.scrollTo(key)
            }
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if list.sections.isEmpty {
                Group {
                    if focus.isActive, total > list.rowCount {
                        FocusedEmptyView(model: model, tabTitle: IssueScope.all.title, hiddenCount: scoped.hiddenCount)
                    } else {
                        ListStateView(
                            symbol: "pullbull.issue", title: "No open issues assigned to you or opened by you")
                    }
                }
                .emptyStateFrame(.nothing)
            } else {
                if list.nothingAssigned {
                    IssueListLine(symbol: "checkmark", text: "Nothing assigned to you", compact: compact)
                }
                sections
                if scoped.hiddenCount > 0 {
                    OtherReposLine(model: model, count: scoped.hiddenCount)
                }
            }
        }
        .padding(.horizontal, Metrics.rowInset)
        .padding(.bottom, 6)
    }

    /// Each section under a header that folds; a hairline parts each from the one above.
    @ViewBuilder private var sections: some View {
        let first = list.sections.first?.section
        let folded = model.foldedIssueSections(in: list)
        ForEach(list.sections) { section in
            let s = section.section
            let isOpen = !folded.contains(s)
            if s != first {
                // Edge to edge, as the header's material below it is (`pinnedHeaderBackground`).
                Hairline()
                    .padding(.horizontal, -Metrics.rowInset)
                    .padding(.top, 6)
            }
            Section {
                if isOpen {
                    sectionBody(section)
                }
            } header: {
                ListSectionHeader(
                    glyph: s.glyph, title: s.title, count: count(of: section), warning: warning(of: section),
                    fold: .init(isOpen: isOpen) { model.toggleIssueSection(s) }, compact: compact)
                    .pinnedHeaderBackground()
            }
        }
    }

    @ViewBuilder private func sectionBody(_ section: IssueListSection) -> some View {
        switch section.state {
        case .rows, .stale:
            rows(section.issues, on: section.section.rowTab)
        case .loading:
            if let error = notLoadedError(section.section) {
                failedLine(section.section, error: error)
            } else {
                SkeletonRows(compact: compact, trailing: 18)
                    .skeletonShimmer()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading…")
            }
        case .failed(let error):
            failedLine(section.section, error: error)
        }
    }

    /// A list that never loaded says why once no refresh is running, as a tab's `IssueListNotLoadedView` does.
    private func notLoadedError(_ section: IssueSection) -> String? {
        guard !model.status.isRefreshing else { return nil }
        return model.snapshot?.issuesError(for: section.rowTab) ?? model.status.error.map(model.message(for:))
    }

    private func failedLine(_ section: IssueSection, error: String) -> some View {
        IssueListLine(
            symbol: "exclamationmark.triangle", text: Self.failedText(section), compact: compact, warning: true)
            .help(error)
    }

    /// Only a section with rows has a count; one loading or failed has none to give.
    private func count(of section: IssueListSection) -> Int? {
        switch section.state {
        case .rows, .stale: section.issues.count
        case .loading, .failed: nil
        }
    }

    /// The tooltip a stale tab count gave: why the kept rows didn't update.
    private func warning(of section: IssueListSection) -> String? {
        guard case .stale(let error, let since) = section.state else { return nil }
        guard let since else { return "Didn't update · \(error)" }
        return "Didn't update · last good \(RelativeAge.ago(since, now: now))"
    }

    private static func failedText(_ section: IssueSection) -> String {
        section == .youOpened ? "Couldn't load created issues" : "Couldn't load assigned issues"
    }

    private func rows(_ issues: [BoardIssue], on tab: IssueTab) -> some View {
        let wantedLabels = model.searchQuery.labels
        return ForEach(issues) { issue in
            IssueRow(
                model: model, issue: issue, tab: tab, now: now, selected: model.listSelection == issue.key,
                inRepoGroup: model.repoFocus != nil, wantedLabels: wantedLabels, status: list.status[issue.key])
                .scrollTarget(issue.key, clearance: PinnedHeader.clearance)
        }
    }
}

/// A one-line note in All, as tall as a section header: the glyph in the rows' icon column, then the words.
/// A plain line, not a header.
private struct IssueListLine: View {
    let symbol: String
    let text: String
    let compact: Bool
    /// An amber glyph: something didn't load.
    var warning = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(warning ? Palette.amberGlyph : Color.secondary)
                .frame(width: compact ? 16 : 20)
            Text(text)
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: ListSectionHeader.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
