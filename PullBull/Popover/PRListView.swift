import SwiftUI
import PullBullKit

/// The scrollable pull request list for one chip. All and Mine show their sections under pinned headers
/// that fold; Needs you and Team show their one section headerless, grouped by repository or author as
/// set. An empty list shows its empty state, on Mine above Recently closed.
struct PRListView: View {
    @Bindable var model: AppModel
    let scoped: ScopedPRList
    /// Every row of the chip, in any repository and at any age.
    let total: Int
    let now: Date

    private var list: PRList { scoped.list }
    private var scope: PRScope { list.scope }
    private var focus: ListFocus { model.listFocus }
    private var grouping: PRGrouping { model.listGrouping }
    private var openSections: [ListSection] { list.sections.filter { $0.section != .recentlyClosed } }
    private var closed: ListSection? { list.sections.first { $0.section == .recentlyClosed } }
    /// On Mine, a focus hides every open row but leaves recently closed ones: the section stands in for the
    /// empty state. With no open PRs at all nothing is hidden, so the empty state stays, as it does
    /// without a focus.
    private var closedOnly: Bool {
        scope == .mine && openSections.isEmpty && closed != nil && focus.isActive
            && model.prList?.sections.contains { $0.section != .recentlyClosed } == true
    }
    /// Mine with no open rows keeps its empty state, framed above Recently closed; elsewhere only a
    /// wholly empty list shows one.
    private var showsEmptyState: Bool {
        scope == .mine ? openSections.isEmpty && !closedOnly : list.isEmpty
    }
    /// What sits under an empty list: on Mine, Recently closed, whose hairline, header and the list's bottom
    /// padding take `closedSectionHeight` while it is folded.
    private var closedBelow: EmptyListFrame.Below {
        guard closed != nil else { return .nothing }
        return model.foldedSections.contains(.recentlyClosed) ? .folded(height: Self.closedSectionHeight) : .open
    }
    private static let closedSectionHeight = 6 + 1 + ListSectionHeader.height + 6

    /// The section holds the last 7×24 hours; a step that starts later, the week included, says so.
    private var closedWindow: String {
        guard let step = focus.time?.step, step.daysBack <= 6 else { return "Last 7 days" }
        return step.stripTitle
    }

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
            // The selection is shared by every chip: it stays in view across them.
            .onChange(of: model.prScope) { _, _ in
                guard let key = model.listSelection else { return }
                proxy.scrollTo(key)
            }
        }
    }

    private var content: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if showsEmptyState {
                Group {
                    if focus.isActive, total > list.rowCount {
                        FocusedEmptyView(model: model, tabTitle: scope.title, hiddenCount: scoped.hiddenCount)
                    } else {
                        EmptyTabView(model: model, tab: scope.tab ?? .review, now: now)
                    }
                }
                .emptyStateFrame(closedBelow)
            } else if list.nothingNeedsYou {
                NothingNeedsYouLine(compact: model.settings.compact)
            }
            if scope.showsSectionHeaders {
                sections
            } else if let section = list.sections.first, let tab = scope.tab {
                grouped(section.contents.rows, on: tab)
            }
            if !showsEmptyState && scoped.hiddenCount > 0 {
                OtherReposLine(model: model, count: scoped.hiddenCount)
            }
        }
        .padding(.horizontal, Metrics.rowInset)
        .padding(.bottom, 6)
    }

    /// All's and Mine's sections, each under a header that folds; a hairline parts each from the one above,
    /// and Mine's Recently closed from the empty state.
    @ViewBuilder private var sections: some View {
        let first = list.sections.first?.section
        ForEach(list.sections) { section in
            let s = section.section
            let isOpen = !model.foldedSections.contains(s)
            if s != first || showsEmptyState {
                // Edge to edge, as the header's material below it is (`pinnedHeaderBackground`).
                Hairline()
                    .padding(.horizontal, -Metrics.rowInset)
                    .padding(.top, 6)
            }
            Section {
                if isOpen {
                    if let tab = s.rowTab {
                        rows(section.contents.rows, on: tab, clearance: PinnedHeader.clearance)
                    } else {
                        ForEach(section.contents.rows) { row in
                            ClosedRow(model: model, pr: row.pr, now: now, selected: model.listSelection == row.pr.key)
                                .scrollTarget(row.pr.key, clearance: PinnedHeader.clearance)
                        }
                    }
                }
            } header: {
                ListSectionHeader(
                    glyph: s.glyph, glyphColor: s.glyphColor, title: s.title, count: section.count,
                    trailing: s == .recentlyClosed ? closedWindow : nil,
                    fold: .init(isOpen: isOpen) { model.toggleSection(s) }, compact: model.settings.compact)
                    .pinnedHeaderBackground()
            }
        }
    }

    /// Needs you's or Team's one section, grouped by repository or author as set, or ungrouped.
    @ViewBuilder private func grouped(_ all: [Row], on tab: PRTab) -> some View {
        switch grouping {
        case .repository:
            ForEach(ListNavigation.repoGroups(all), id: \.repo) { group in
                Section {
                    rows(group.rows, on: tab, clearance: PinnedHeader.clearance)
                } header: {
                    RepoGroupHeader(model: model, repo: group.repo, rows: group.rows, menus: .list)
                        .pinnedHeaderBackground()
                }
            }
        case .author:
            ForEach(ListNavigation.authorGroups(all), id: \.author) { group in
                Section {
                    rows(group.rows, on: tab, clearance: PinnedHeader.clearance)
                } header: {
                    AuthorGroupHeader(model: model, author: group.author, rows: group.rows, menus: .list)
                        .pinnedHeaderBackground()
                }
            }
        case .none:
            // Ungrouped rows have no header to clear.
            rows(all, on: tab, clearance: 0)
                .padding(.top, 6)
        }
    }

    private func rows(_ rows: [Row], on tab: PRTab, clearance: CGFloat) -> some View {
        let wantedLabels = model.searchQuery.labels
        return ForEach(rows) { row in
            PRRow(
                model: model, row: row, context: .tab(tab), compact: model.settings.compact, now: now,
                selected: model.listSelection == row.pr.key, wantedLabels: wantedLabels)
            .scrollTarget(row.pr.key, clearance: clearance)
        }
    }
}

/// All's first line when nothing waits on me: a checkmark in the rows' icon column and the words, as tall
/// as a section header. A plain line, not a header.
private struct NothingNeedsYouLine: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: "checkmark")
                .font(.system(size: compact ? 10 : 11))
                .frame(width: compact ? 16 : 20)
            Text("Nothing needs you")
                .font(.system(size: 12))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: ListSectionHeader.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nothing needs you")
    }
}

private struct EmptyTabView: View {
    @Bindable var model: AppModel
    let tab: PRTab
    let now: Date

    var body: some View {
        ListStateView(symbol: symbol, title: title, detail: subtitle) {
            if tab == .review && model.settings.hideApprovedByMe && model.hiddenApprovedCount > 0 {
                let n = model.hiddenApprovedCount
                HStack(spacing: 4) {
                    Text(n == 1 ? "1 PR you already approved is hidden ·" : "\(n) PRs you already approved are hidden ·")
                        .foregroundStyle(.secondary)
                    Button("Show") { model.settings.hideApprovedByMe = false }
                        .buttonStyle(.link)
                }
                .font(.system(size: 11))
                .padding(.top, 2)
            }
        }
    }

    private var symbol: String {
        switch tab {
        case .review: "checkmark"
        case .mine: "pullbull.pullrequest"
        case .team: "person.2"
        }
    }

    private var title: String {
        switch tab {
        case .review: "Nothing needs your review"
        case .mine: "No open pull requests"
        case .team: "No open team pull requests"
        }
    }

    private var subtitle: String {
        if tab == .review, let cleared = model.reviewCleared.clearedAt {
            return ClearedTracker.subtitle(clearedAt: cleared, now: now)
        }
        return switch tab {
        case .review: "New review requests show up here and in the menu bar."
        case .mine: "Pull requests you open show up here."
        case .team: "Open pull requests by your teammates show up here."
        }
    }
}
