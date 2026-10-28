import Foundation

/// Keyboard selection in the popover's lists: the rows ↑/↓ visit, in display order, and where a move
/// lands. Group headers are never rows; a folded group's rows are not visited.
public enum ListNavigation {
    /// PR rows grouped by repository, the groups in the order of their most recently updated PR (rows
    /// arrive sorted).
    public static func repoGroups(_ rows: [Row]) -> [(repo: String, rows: [Row])] {
        var order: [String] = []
        var byRepo: [String: [Row]] = [:]
        for row in rows {
            if byRepo[row.pr.key.repo] == nil { order.append(row.pr.key.repo) }
            byRepo[row.pr.key.repo, default: []].append(row)
        }
        return order.map { ($0, byRepo[$0] ?? []) }
    }

    /// The PR list's rows as shown: by repository when grouped, then Mine's "Recently closed" when
    /// expanded.
    public static func prKeys(
        tab: PRTab, contents: TabContents, groupedByRepo: Bool, recentlyClosed: [PullRequest],
        closedExpanded: Bool
    ) -> [PRKey] {
        let rows = groupedByRepo ? repoGroups(contents.rows).flatMap(\.rows) : contents.rows
        var keys = rows.map(\.pr.key)
        if tab == .mine && closedExpanded { keys += recentlyClosed.map(\.key) }
        return keys
    }

    /// An Issues list's rows as shown: every group but Done and the `folded` lanes, then Done when
    /// expanded.
    public static func issueKeys(
        _ contents: IssueTabContents, doneExpanded: Bool, folded: Set<IssueGroupKind> = []
    ) -> [PRKey] {
        let listed = contents.groups.filter { $0.kind != .done && !folded.contains($0.kind) }.flatMap(\.issues)
        let done = doneExpanded ? contents.groups.filter { $0.kind == .done }.flatMap(\.issues) : []
        return (listed + done).map(\.key)
    }

    /// The row `offset` steps from `selection`, stopping at the ends. With no selection, or one that is
    /// no longer shown, ↓ lands on the first row and ↑ on the last. Nil when there are no rows.
    public static func move(_ selection: PRKey?, by offset: Int, in keys: [PRKey]) -> PRKey? {
        guard !keys.isEmpty else { return nil }
        let current = selection.flatMap { keys.firstIndex(of: $0) } ?? (offset > 0 ? -1 : keys.count)
        return keys[min(max(current + offset, 0), keys.count - 1)]
    }

    /// The selection when it is one of the rows shown, else nil (its group folded or it left the list).
    public static func shown(_ selection: PRKey?, in keys: [PRKey]) -> PRKey? {
        selection.flatMap { keys.contains($0) ? $0 : nil }
    }

    /// The selection after a fold changed the rows from `old` to `new`: kept while still shown, else the
    /// next row after it that is shown (the row below the folded lane), else nil.
    public static func selection(_ selection: PRKey?, from old: [PRKey], to new: [PRKey]) -> PRKey? {
        guard let selection else { return nil }
        if new.contains(selection) { return selection }
        guard let index = old.firstIndex(of: selection) else { return nil }
        let shown = Set(new)
        return old[(index + 1)...].first { shown.contains($0) }
    }

    /// The sub-tab `offset` steps along the tab bar, stopping at the ends.
    public static func tab<Tab: CaseIterable & Equatable>(_ tab: Tab, movedBy offset: Int) -> Tab {
        self.tab(tab, movedBy: offset, among: Array(Tab.allCases))
    }

    /// The same along the tabs shown, `all`, when some are hidden.
    public static func tab<Tab: Equatable>(_ tab: Tab, movedBy offset: Int, among all: [Tab]) -> Tab {
        guard let index = all.firstIndex(of: tab) else { return tab }
        return all[min(max(index + offset, 0), all.count - 1)]
    }

    /// The short reference GitHub links in text: `owner/repo#123`.
    public static func reference(_ key: PRKey) -> String {
        "\(key.repo)#\(key.number)"
    }
}
