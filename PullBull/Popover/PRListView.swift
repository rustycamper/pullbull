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
    private var focus: RepoFocus? { model.repoFocus }
    /// What the focus leaves listed: the rows, and on Mine the recently closed PRs.
    private var scopedTotal: Int { contents.rows.count + (tab == .mine ? recentlyClosed.count : 0) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                list
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.listSelection) { _, key in
                guard let key else { return }
                proxy.scrollTo(key)
            }
        }
    }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if contents.rows.isEmpty {
                Group {
                    if let focus, total > scopedTotal {
                        FocusedEmptyView(
                            model: model, repoName: model.displayName(of: focus.repo), tabTitle: tab.title, hiddenCount: scoped.hiddenCount)
                    } else {
                        EmptyTabView(model: model, tab: tab, now: now)
                    }
                }
                .frame(height: tab == .mine && !recentlyClosed.isEmpty ? 260 : 400)
            } else if model.listGroupedByRepo {
                ForEach(groups, id: \.repo) { group in
                    GroupHeader(model: model, repo: group.repo, count: group.rows.filter(\.counted).count)
                    rows(group.rows)
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
                model: model, row: row, tab: tab, compact: model.settings.compact, now: now,
                selected: model.listSelection == row.pr.key, wantedLabels: wantedLabels)
            .id(row.pr.key)
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
        Button {
            closedExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(closedExpanded ? 90 : 0))
                Text("Recently closed")
                Text("\(recentlyClosed.count)")
                    .fontWeight(.medium)
                    .monospacedDigit()
                Spacer()
                Text("Last 7 days")
                    .fontWeight(.regular)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel("Recently closed, \(recentlyClosed.count)")
        .accessibilityValue(closedExpanded ? "expanded" : "collapsed")
        if closedExpanded {
            ForEach(recentlyClosed) { pr in
                ClosedRow(model: model, pr: pr, now: now, selected: model.listSelection == pr.key)
                    .id(pr.key)
            }
        }
    }
}

private struct GroupHeader: View {
    let model: AppModel
    let repo: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed")
                .font(.system(size: 10))
            Text(repo.split(separator: "/").last.map(String.init) ?? repo)
            if count > 0 {
                Text("\(count)")
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .focusContextMenu(FocusMenuItem(model: model, repo: repo))
    }
}

private struct EmptyTabView: View {
    @Bindable var model: AppModel
    let tab: PRTab
    let now: Date

    var body: some View {
        VStack(spacing: 10) {
            Image(symbol: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Palette.fill))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.top, 4)
            // At least two lines held, so the one-line "You cleared…" copy doesn't move the view.
            ZStack {
                Text(verbatim: " \n ").hidden()
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
            if tab == .review && model.settings.hideApprovedByMe && model.hiddenApprovedCount > 0 {
                let n = model.hiddenApprovedCount
                HStack(spacing: 4) {
                    Text(n == 1 ? "1 PR you already approved is hidden ·" : "\(n) PRs you already approved are hidden ·")
                        .foregroundStyle(.secondary)
                    Button("Show") { model.settings.hideApprovedByMe = false }
                        .buttonStyle(.link)
                }
                .font(.system(size: 11))
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
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
