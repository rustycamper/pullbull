import SwiftUI
import PullBullKit

/// The scrollable list for one tab: rows grouped by repository (setting), an empty state, and on
/// Mine the folded "Recently closed" section.
struct PRListView: View {
    @Bindable var model: AppModel
    let tab: PRTab
    let scoped: ScopedTab
    /// Every item of the tab, in any repository, and on Mine the recently closed ones.
    let total: Int
    let recentlyClosed: [PullRequest]
    let now: Date
    @Binding var closedExpanded: Bool

    private var contents: TabContents { scoped.contents }
    private var focus: ListFocus { model.listFocus }
    /// What the focus leaves listed: the rows, and on Mine the recently closed PRs.
    private var scopedTotal: Int { contents.rows.count + (tab == .mine ? recentlyClosed.count : 0) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                list
            }
            .focusContextMenu(time: TimeFocusMenu(model: model))
            .scrollIndicators(.automatic)
            .onChange(of: model.listSelection) { _, key in
                guard let key else { return }
                proxy.scrollTo(key)
            }
        }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if contents.rows.isEmpty {
                Group {
                    if focus.isActive, total > scopedTotal {
                        FocusedEmptyView(model: model, tabTitle: tab.title, hiddenCount: scoped.hiddenCount)
                    } else {
                        EmptyTabView(model: model, tab: tab, now: now)
                    }
                }
                .frame(height: tab == .mine && !recentlyClosed.isEmpty ? 260 : 400)
            } else if model.listGroupedByRepo {
                ForEach(groups, id: \.repo) { group in
                    Section {
                        rows(group.rows)
                    } header: {
                        repoHeader(group.repo, count: group.rows.filter(\.counted).count)
                            .pinnedHeaderBackground()
                    }
                }
            } else {
                rows(contents.rows)
                    .padding(.top, 6)
            }
            if !contents.rows.isEmpty && scoped.hiddenCount > 0 {
                OtherReposLine(model: model, count: scoped.hiddenCount)
            }
            if tab == .mine && !recentlyClosed.isEmpty {
                closedSection
            }
        }
        .padding(.horizontal, Metrics.rowInset)
        .padding(.bottom, 6)
    }

    private func rows(_ rows: [Row]) -> some View {
        let wantedLabels = model.searchQuery.labels
        return ForEach(rows) { row in
            PRRow(
                model: model, row: row, context: .tab(tab), compact: model.settings.compact, now: now,
                selected: model.listSelection == row.pr.key, wantedLabels: wantedLabels)
            // Ungrouped rows have no header to clear.
            .scrollTarget(row.pr.key, clearance: model.listGroupedByRepo ? PinnedHeader.clearance : 0)
        }
    }

    /// Repo groups in the order of their most recently updated PR, as ↑/↓ walks them.
    private var groups: [(repo: String, rows: [Row])] {
        ListNavigation.repoGroups(contents.rows)
    }

    @ViewBuilder private var closedSection: some View {
        Hairline()
            .padding(.horizontal, 8)
            .padding(.top, 6)
        Section {
            if closedExpanded {
                ForEach(recentlyClosed) { pr in
                    ClosedRow(model: model, pr: pr, now: now, selected: model.listSelection == pr.key)
                        .scrollTarget(pr.key, clearance: PinnedHeader.clearance)
                }
            }
        } header: {
            closedHeader
                .pinnedHeaderBackground()
        }
    }

    private var closedHeader: some View {
        ListSectionHeader(
            glyph: nil, title: "Recently closed", count: recentlyClosed.count, trailing: "Last 7 days",
            fold: .init(isOpen: closedExpanded) { closedExpanded.toggle() }, compact: model.settings.compact)
    }

    /// A repo group's header, counting what the tab counts; it offers the repo focus.
    private func repoHeader(_ repo: String, count: Int) -> some View {
        ListSectionHeader(
            glyph: "book.closed", title: repo.split(separator: "/").last.map(String.init) ?? repo,
            count: count > 0 ? count : nil, compact: model.settings.compact)
            .focusContextMenu(FocusMenuItem(model: model, repo: repo), time: TimeFocusMenu(model: model))
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
