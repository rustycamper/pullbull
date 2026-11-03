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

/// Pull request results laid out in the list's sections (Everywhere and Mine): the open ones in the
/// section the list holds them in, the rest in Other results, then the merged and closed ones.
public struct SearchSectionLayout: Sendable {
    public let scope: PRScope
    /// The open results: non-empty sections in `PRSection` order. Nothing folds in search.
    public let sections: [ListSection]
    /// Merged and closed results, the most recently closed first.
    public let ended: [PullRequest]

    /// The shown groups of rows, in display order: one per section, then Closed when expanded and not empty.
    public func groups(closedExpanded: Bool) -> [[PRKey]] {
        var groups = sections.map { $0.contents.rows.map(\.pr.key) }
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

/// Issue results laid out in All's sections (Everywhere): the open ones in the section the list holds
/// them in, the rest in Other results, those done on the board in Done, then the closed ones.
public struct SearchIssueSectionLayout: Sendable {
    /// The open results: non-empty sections in `IssueSection` order, each in `.rows` state. Nothing folds in search.
    public let sections: [IssueListSection]
    /// Open results whose board copy is done, in All's order.
    public let done: [BoardIssue]
    /// Closed results, the most recently closed (or, without a close date, updated) first.
    public let ended: [BoardIssue]
    /// The shown Status of each result that has one, for the row chip.
    public let status: [PRKey: BoardStatusValue]

    /// The shown groups of rows, in display order: one per section, Done when expanded, then Closed when
    /// expanded. Empty groups are left out.
    public func groups(closedExpanded: Bool, doneExpanded: Bool) -> [[PRKey]] {
        var groups = sections.map { $0.issues.map(\.key) }
        if doneExpanded && !done.isEmpty { groups.append(done.map(\.key)) }
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
    /// row rule for each open result and its sort (`settings.sort(for: tab)`). Closed results stay newest-closed first.
    public static func pullRequests(
        _ results: SearchResults, on tab: PRTab, grouping: PRGrouping, settings: AppSettings, org: OrgContext,
        now: Date
    ) -> SearchPRLayout {
        let rows = results.openPRs.map { TabBuilder.row(for: $0, on: tab, me: org.viewer, myTeams: org.myTeams) }
        let contents = TabBuilder.contents(
            rows, sort: settings.sort(for: tab), on: tab, me: org.viewer, myTeams: org.myTeams, now: now)
        let ended = closed(results.closedPRs)
        return SearchPRLayout(tab: tab, grouping: grouping, contents: contents, ended: ended)
    }

    /// The pull request results in the list's sections. An open result sits in the section the list holds
    /// it in; else, when it is mine, where `PRSection.mine` puts it; else in Other results. Its row follows
    /// the section's fetched list, and each section follows the scope's sort (`settings.sort(for: scope)`).
    public static func sections(
        _ results: SearchResults, scope: PRScope, tabs: BuiltTabs, settings: AppSettings, org: OrgContext,
        now: Date
    ) -> SearchSectionLayout {
        let held: [(PRSection, Set<PRKey>)] = [
            (.needsReview, Set(tabs.review.rows.map(\.id))),
            (.yourPRs, Set(tabs.yourPRs.rows.map(\.id))),
            (.waiting, Set(tabs.waitingOnOthers.rows.map(\.id))),
            (.team, Set(tabs.teamSection.rows.map(\.id))),
        ]
        func section(of pr: PullRequest) -> PRSection {
            if let found = held.first(where: { $0.1.contains(pr.key) }) { return found.0 }
            return pr.author.caseInsensitiveCompare(org.viewer) == .orderedSame ? PRSection.mine(pr) : .otherResults
        }
        let bySection = Dictionary(grouping: results.openPRs, by: section(of:))
        let built: [ListSection] = PRSection.allCases.compactMap { section in
            guard let prs = bySection[section], let tab = section.rowTab else { return nil }
            let rows = prs.map { TabBuilder.row(for: $0, on: tab, me: org.viewer, myTeams: org.myTeams) }
            let contents = TabBuilder.contents(
                rows, sort: settings.sort(for: scope), on: tab, me: org.viewer, myTeams: org.myTeams, now: now)
            return ListSection(section: section, contents: contents)
        }
        return SearchSectionLayout(scope: scope, sections: built, ended: closed(results.closedPRs))
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
        return SearchIssueLayout(tab: tab, contents: contents, ended: endedIssues(results.closedIssues))
    }

    /// The issue results in All's sections. A result done on the board goes to Done; else it sits in the
    /// section the list holds it in; else, assigned to `viewer`, in Assigned to you; else, opened by
    /// `viewer`, in You opened; else in Other results. Each section follows All's sort.
    public static func issueSections(
        _ results: SearchResults, tabs: BuiltIssueTabs, snap: Snapshot, settings: AppSettings, viewer: String
    ) -> SearchIssueSectionLayout {
        let list = IssueList.build(tabs, snap: snap, settings: settings)
        let done = IssueList.doneKeys(in: snap)
        let held = Dictionary(
            list.sections.flatMap { section in section.issues.map { ($0.key, section.section) } },
            uniquingKeysWith: { first, _ in first })
        func matches(_ login: String?) -> Bool {
            login.map { $0.caseInsensitiveCompare(viewer) == .orderedSame } ?? false
        }
        func section(of issue: BoardIssue) -> IssueSection {
            if let found = held[issue.key] { return found }
            if issue.assignees.contains(where: { matches($0.login) }) { return .assignedToYou }
            return matches(issue.author) ? .youOpened : .otherResults
        }
        let ordered = IssueList.ordering(settings.sort(for: .all, boardAvailable: tabs.board != nil), snap: snap)
        let doneResults = results.openIssues.filter { done.contains($0.key) }
        let bySection = Dictionary(
            grouping: results.openIssues.filter { !done.contains($0.key) }, by: section(of:))
        let built = IssueSection.allCases.compactMap { section -> IssueListSection? in
            guard section != .doneStillOpen, let issues = bySection[section] else { return nil }
            return IssueListSection(section: section, issues: ordered(issues), state: .rows)
        }
        let shown = IssueList.shownStatus(in: snap)
        var status: [PRKey: BoardStatusValue] = [:]
        for issue in results.openIssues + results.closedIssues { status[issue.key] = shown(issue) }
        return SearchIssueSectionLayout(
            sections: built, done: ordered(doneResults), ended: endedIssues(results.closedIssues), status: status)
    }

    /// The tab whose chips a result's row shows: Team's for someone else's PR on Mine, which hides the
    /// author and offers Ready to merge; otherwise `tab`'s.
    public static func chipTab(for pr: PullRequest, on tab: PRTab, viewer: String) -> PRTab {
        tab == .mine && pr.author.caseInsensitiveCompare(viewer) != .orderedSame ? .team : tab
    }

    /// Whether a result's row names its repository: not under a repo header, nor inside the repo focus. A
    /// link or `owner/repo#123` can bring a result from outside the focus.
    public static func showsRepo(_ key: PRKey, underRepoHeader: Bool, focus: RepoFocus?) -> Bool {
        !underRepoHeader && !(focus?.matches(key) ?? false)
    }

    private static func endedIssues(_ issues: [BoardIssue]) -> [BoardIssue] {
        issues.sorted { a, b in
            let da = a.closedAt ?? a.updatedAt ?? .distantPast, db = b.closedAt ?? b.updatedAt ?? .distantPast
            if da != db { return da > db }
            return tieBreak(a.key, b.key)
        }
    }

    private static func closed(_ prs: [PullRequest]) -> [PullRequest] {
        prs.sorted { a, b in
            let ca = a.closedAt ?? .distantPast, cb = b.closedAt ?? .distantPast
            if ca != cb { return ca > cb }
            return tieBreak(a.key, b.key)
        }
    }

    private static func tieBreak(_ a: PRKey, _ b: PRKey) -> Bool {
        a.repo != b.repo ? a.repo < b.repo : a.number < b.number
    }
}
