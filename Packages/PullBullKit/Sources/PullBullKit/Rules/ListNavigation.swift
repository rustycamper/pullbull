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

    /// PR rows grouped by author, the groups by name (case-insensitive); rows keep their order in a group.
    public static func authorGroups(_ rows: [Row]) -> [(author: String, rows: [Row])] {
        var byAuthor: [String: (author: String, rows: [Row])] = [:]
        for row in rows {
            let id = row.pr.author.lowercased()
            byAuthor[id, default: (row.pr.author, [])].rows.append(row)
        }
        return byAuthor.keys.sorted().compactMap { byAuthor[$0] }
    }

    /// The PR list's shown groups of rows, in display order: by `grouping`, then Mine's "Recently closed"
    /// last when expanded. An ungrouped list is one group.
    public static func prGroups(
        tab: PRTab, contents: TabContents, grouping: PRGrouping, recentlyClosed: [PullRequest],
        closedExpanded: Bool
    ) -> [[PRKey]] {
        var groups: [[PRKey]]
        switch grouping {
        case .repository: groups = repoGroups(contents.rows).map { $0.rows.map(\.pr.key) }
        case .author: groups = authorGroups(contents.rows).map { $0.rows.map(\.pr.key) }
        case .none: groups = [contents.rows.map(\.pr.key)]
        }
        if tab == .mine && closedExpanded { groups.append(recentlyClosed.map(\.key)) }
        return groups
    }

    /// The PR list's rows as shown, `prGroups` flattened.
    public static func prKeys(
        tab: PRTab, contents: TabContents, grouping: PRGrouping, recentlyClosed: [PullRequest],
        closedExpanded: Bool
    ) -> [PRKey] {
        prGroups(
            tab: tab, contents: contents, grouping: grouping, recentlyClosed: recentlyClosed,
            closedExpanded: closedExpanded
        ).flatMap { $0 }
    }

    public static func prKeys(
        tab: PRTab, contents: TabContents, groupedByRepo: Bool, recentlyClosed: [PullRequest],
        closedExpanded: Bool
    ) -> [PRKey] {
        prKeys(
            tab: tab, contents: contents, grouping: groupedByRepo ? .repository : .none,
            recentlyClosed: recentlyClosed, closedExpanded: closedExpanded)
    }

    /// An Issues list's rows as shown: every group but Done and the `folded` lanes, then Done when
    /// expanded.
    public static func issueKeys(
        _ contents: IssueTabContents, doneExpanded: Bool, folded: Set<IssueGroupKind> = []
    ) -> [PRKey] {
        issueGroups(contents, doneExpanded: doneExpanded, folded: folded).flatMap { $0 }
    }

    /// An Issues list's shown groups of rows, in display order: every group but Done and the `folded`
    /// lanes, then Done when expanded. Empty groups are left out.
    public static func issueGroups(
        _ contents: IssueTabContents, doneExpanded: Bool, folded: Set<IssueGroupKind>
    ) -> [[PRKey]] {
        let listed = contents.groups.filter { $0.kind != .done && !folded.contains($0.kind) }
        let done = doneExpanded ? contents.groups.filter { $0.kind == .done } : []
        return (listed + done).map { $0.issues.map(\.key) }.filter { !$0.isEmpty }
    }

    /// Whether a PR list grouped this way shows group headers to jump between.
    public static func isGrouped(prGrouping: PRGrouping) -> Bool { prGrouping != .none }

    /// Whether an Issues list shows group headers to jump between: not when it lists only the ungrouped
    /// (`.all`) or the focus's merged, untitled group.
    public static func isGrouped(_ contents: IssueTabContents) -> Bool {
        contents.groups.contains { $0.kind != .done && !$0.title.isEmpty }
    }

    /// ⌥↓ / ⌥↑: the first row of the next group, or for ⌥↑ the first row of the selection's own group
    /// when it isn't already there, else of the previous one. With no selection shown, ⌥↓ lands on the
    /// first group and ⌥↑ on the last. Nil, to do nothing, past either end.
    public static func jump(_ selection: PRKey?, by offset: Int, in groups: [[PRKey]]) -> PRKey? {
        let groups = groups.filter { !$0.isEmpty }
        guard !groups.isEmpty, offset != 0 else { return nil }
        guard let selection, let current = groups.firstIndex(where: { $0.contains(selection) }) else {
            return offset > 0 ? groups.first?.first : groups.last?.first
        }
        if offset < 0, groups[current].first != selection { return groups[current].first }
        let target = current + offset
        return groups.indices.contains(target) ? groups[target].first : nil
    }

    /// ⌘↑ / ⌘↓: the first or last row; nil when there are none.
    public static func edge(last: Bool, in keys: [PRKey]) -> PRKey? {
        last ? keys.last : keys.first
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
