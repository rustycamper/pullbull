import Foundation

/// Pull request results laid out as the reference tab lays out its list: the open ones as that tab's
/// rows, grouped and ordered as it groups them, then the merged and closed ones in a Closed section.
public struct SearchPRLayout: Sendable {
    public let tab: PRTab
    public let grouping: PRGrouping
    /// The open results as `tab` rows (`TabBuilder.row(for:on:me:myTeams:)`), in the tab's order.
    public let contents: TabContents
    /// Merged and closed results, the most recently closed first.
    public let ended: [PullRequest]

    /// Whether the open rows show group headers to jump between.
    public var isGrouped: Bool { ListNavigation.isGrouped(prGrouping: grouping) }

    /// The shown groups of rows, in display order: the tab's groups, then Closed when expanded and not empty.
    public func groups(closedExpanded: Bool) -> [[PRKey]] {
        var groups = ListNavigation.prGroups(
            tab: tab, contents: contents, grouping: grouping, recentlyClosed: [], closedExpanded: false)
        if closedExpanded && !ended.isEmpty { groups.append(ended.map(\.key)) }
        return groups
    }

    /// The rows as shown, `groups` flattened.
    public func keys(closedExpanded: Bool) -> [PRKey] {
        groups(closedExpanded: closedExpanded).flatMap { $0 }
    }
}

/// Issue results laid out as the reference tab lays out its list: the open ones in its groups, Done
/// included, then the closed ones in a Closed section.
public struct SearchIssueLayout: Sendable {
    public let tab: IssueTab
    /// The open results' groups, the uncounted Done group included.
    public let contents: IssueTabContents
    /// Closed results, the most recently closed (or, without a close date, updated) first.
    public let ended: [BoardIssue]

    /// Whether the open groups show headers to jump between.
    public var isGrouped: Bool { ListNavigation.isGrouped(contents) }

    /// The shown groups of rows, in display order: the open groups, Done when expanded, then Closed when
    /// expanded. Empty groups are left out.
    public func groups(closedExpanded: Bool, doneExpanded: Bool) -> [[PRKey]] {
        var groups = ListNavigation.issueGroups(contents, doneExpanded: doneExpanded, folded: [])
        if closedExpanded && !ended.isEmpty { groups.append(ended.map(\.key)) }
        return groups
    }

    /// The rows as shown, `groups` flattened.
    public func keys(closedExpanded: Bool, doneExpanded: Bool) -> [PRKey] {
        groups(closedExpanded: closedExpanded, doneExpanded: doneExpanded).flatMap { $0 }
    }
}

/// Search results in the reference tab's layout (`SearchScope.reference`).
public enum SearchLayout {
    /// The pull request results as `tab`, grouped by `grouping` (`PRGrouping.forTab`), shows them: its
    /// row rule for each open result and its sort, Review's "Oldest review request first" included.
    public static func pullRequests(
        _ results: SearchResults, on tab: PRTab, grouping: PRGrouping, settings: AppSettings, org: OrgContext
    ) -> SearchPRLayout {
        let rows = results.openPRs.map { TabBuilder.row(for: $0, on: tab, me: org.viewer, myTeams: org.myTeams) }
        let contents = TabBuilder.contents(rows, oldestFirst: tab == .review && settings.reviewOldestFirst)
        let ended = results.closedPRs.sorted { a, b in
            let ca = a.closedAt ?? .distantPast, cb = b.closedAt ?? .distantPast
            if ca != cb { return ca > cb }
            return tieBreak(a.key, b.key)
        }
        return SearchPRLayout(tab: tab, grouping: grouping, contents: contents, ended: ended)
    }

    /// The issue results as `tab` groups its open items (`IssueTabBuilder.groups(of:on:in:settings:)`).
    /// Under a repo focus the repo groups merge into one untitled group, as the tab's do; an item from
    /// another repository (a link) stays in it.
    public static func issues(
        _ results: SearchResults, on tab: IssueTab, settings: AppSettings, focus: RepoFocus?, snap: Snapshot
    ) -> SearchIssueLayout {
        var contents = IssueTabContents(
            groups: IssueTabBuilder.groups(of: results.openIssues, on: tab, in: snap, settings: settings))
        if focus != nil {
            contents = RepoFocus.scopeIssues(contents, keeping: { _ in true }, mergeRepoGroups: true).contents
        }
        let ended = results.closedIssues.sorted { a, b in
            let da = a.closedAt ?? a.updatedAt ?? .distantPast, db = b.closedAt ?? b.updatedAt ?? .distantPast
            if da != db { return da > db }
            return tieBreak(a.key, b.key)
        }
        return SearchIssueLayout(tab: tab, contents: contents, ended: ended)
    }

    private static func tieBreak(_ a: PRKey, _ b: PRKey) -> Bool {
        a.repo != b.repo ? a.repo < b.repo : a.number < b.number
    }
}
