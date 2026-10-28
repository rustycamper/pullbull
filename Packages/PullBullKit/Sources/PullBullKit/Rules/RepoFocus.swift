import Foundation

/// A transient single-repository focus that narrows what a list shows. It only filters: counts, the
/// badge and notifications are computed from the unscoped tabs.
public struct RepoFocus: Equatable, Sendable {
    /// `owner/name`.
    public let repo: String

    public init(repo: String) { self.repo = repo }

    /// The last path component of `repo`.
    public var name: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    public func matches(_ key: PRKey) -> Bool { matches(repo: key.repo) }

    public func scope(_ contents: TabContents) -> ScopedTab {
        let focused = contents.rows.filter { matches($0.pr.key) }
        let others = contents.rows.filter { !matches($0.pr.key) }
        return ScopedTab(
            contents: TabContents(rows: focused), otherCount: others.filter(\.counted).count,
            hiddenCount: others.count)
    }

    public func scope(_ closed: [PullRequest]) -> [PullRequest] {
        closed.filter { matches($0.key) }
    }

    /// Each group filtered to the focus with empty groups dropped. Repository groups merge into one
    /// ungrouped list where the first of them was.
    public func scope(_ contents: IssueTabContents) -> ScopedIssueTab {
        var groups: [IssueGroup] = []
        var mergedIndex: Int?
        var other = 0
        var hidden = 0
        for group in contents.groups {
            let focused = group.issues.filter { matches($0.key) }
            hidden += group.issues.count - focused.count
            if group.counted { other += group.issues.count - focused.count }
            if case .repo = group.kind {
                if let index = mergedIndex {
                    groups[index] = IssueGroup(kind: .all, issues: groups[index].issues + focused, counted: true)
                } else if !focused.isEmpty {
                    mergedIndex = groups.count
                    groups.append(IssueGroup(kind: .all, issues: focused, counted: true))
                }
            } else if !focused.isEmpty {
                groups.append(IssueGroup(kind: group.kind, issues: focused, counted: group.counted))
            }
        }
        return ScopedIssueTab(contents: IssueTabContents(groups: groups), otherCount: other, hiddenCount: hidden)
    }

    private func matches(repo other: String) -> Bool {
        repo.caseInsensitiveCompare(other) == .orderedSame
    }

    /// How the focus is named on screen: `owner/name` when another repository in `choices` shares the
    /// name or the owner is not `org`, otherwise the name alone.
    public func displayName(among choices: [RepoChoice], org: String) -> String {
        Self.displayName(of: repo, among: choices, org: org)
    }

    static func displayName(of repo: String, among choices: [RepoChoice], org: String) -> String {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return repo }
        let sameName = Set(choices.filter { $0.name.caseInsensitiveCompare(parts[1]) == .orderedSame }.map(\.id))
            .union([repo.lowercased()])
        let otherOwner = parts[0].caseInsensitiveCompare(org) != .orderedSame
        return sameName.count > 1 || otherOwner ? repo : parts[1]
    }
}

/// A repository in the focus menu.
public struct RepoChoice: Equatable, Sendable, Identifiable {
    /// `owner/name`, as first seen.
    public let repo: String
    /// Counted Review rows.
    public let reviewCount: Int
    /// Distinct counted PRs and issues across the six tabs.
    public let openCount: Int

    public var id: String { repo.lowercased() }
    public var name: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    /// The menu title: the same rule as `RepoFocus.displayName(among:org:)`.
    public func displayName(among choices: [RepoChoice], org: String) -> String {
        RepoFocus.displayName(of: repo, among: choices, org: org)
    }

    public init(repo: String, reviewCount: Int, openCount: Int) {
        self.repo = repo
        self.reviewCount = reviewCount
        self.openCount = openCount
    }
}

extension RepoFocus {
    /// Every repository with anything listed (Recently closed and Done included) plus the current
    /// focus, ordered by Review count, then open count, then name.
    public static func choices(prs: BuiltTabs, issues: BuiltIssueTabs?, current: RepoFocus?) -> [RepoChoice] {
        struct Tally {
            var repo: String
            var review = 0
            var open = Set<Int>()
        }
        var tallies: [String: Tally] = [:]
        func touch(_ repo: String) -> String {
            let id = repo.lowercased()
            if tallies[id] == nil { tallies[id] = Tally(repo: repo) }
            return id
        }
        func countRows(_ contents: TabContents, review: Bool = false) {
            for row in contents.rows {
                let id = touch(row.pr.key.repo)
                guard row.counted else { continue }
                tallies[id]?.open.insert(row.pr.key.number)
                if review { tallies[id]?.review += 1 }
            }
        }
        countRows(prs.review, review: true)
        countRows(prs.mine)
        countRows(prs.team)
        for closed in prs.recentlyClosed { _ = touch(closed.key.repo) }
        if let issues {
            for contents in [issues.assigned, issues.created, issues.board].compactMap({ $0 }) {
                for group in contents.groups {
                    for issue in group.issues {
                        let id = touch(issue.key.repo)
                        if group.counted { tallies[id]?.open.insert(issue.key.number) }
                    }
                }
            }
        }
        if let current { _ = touch(current.repo) }
        return tallies.values
            .map { RepoChoice(repo: $0.repo, reviewCount: $0.review, openCount: $0.open.count) }
            .sorted {
                if $0.reviewCount != $1.reviewCount { return $0.reviewCount > $1.reviewCount }
                if $0.openCount != $1.openCount { return $0.openCount > $1.openCount }
                let byName = $0.name.caseInsensitiveCompare($1.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return $0.id < $1.id
            }
    }

    /// False only when the repository is provably gone: its owner is the current org, the org's repo
    /// list is complete, non-empty and lacks it, and nothing listed (Recently closed and Done included)
    /// is in it.
    public func isValid(prs: BuiltTabs, issues: BuiltIssueTabs?, org: OrgContext) -> Bool {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].caseInsensitiveCompare(org.org) == .orderedSame,
            org.reposComplete, !org.repos.isEmpty,
            !org.repos.contains(where: { $0.caseInsensitiveCompare(parts[1]) == .orderedSame })
        else { return true }
        let listedPRs = [prs.review, prs.mine, prs.team].contains { $0.rows.contains { matches($0.pr.key) } }
        if listedPRs || prs.recentlyClosed.contains(where: { matches($0.key) }) { return true }
        guard let issues else { return false }
        return [issues.assigned, issues.created, issues.board].contains { contents in
            contents?.issues.contains { matches($0.key) } ?? false
        }
    }
}

public struct ScopedTab: Sendable {
    /// The focused rows in their original order, `dimmed` and `counted` kept.
    public let contents: TabContents
    /// Counted rows in other repositories (for tallies).
    public let otherCount: Int
    /// Every row in other repositories, counted or dimmed (for the lines that state the gap).
    public let hiddenCount: Int

    /// No focus: the tab as it is, with nothing in other repositories.
    public init(unscoped contents: TabContents) { self.init(contents: contents, otherCount: 0, hiddenCount: 0) }

    init(contents: TabContents, otherCount: Int, hiddenCount: Int) {
        self.contents = contents
        self.otherCount = otherCount
        self.hiddenCount = hiddenCount
    }
}

public struct ScopedIssueTab: Equatable, Sendable {
    public let contents: IssueTabContents
    /// Issues in counted groups of other repositories (for tallies).
    public let otherCount: Int
    /// Every issue in other repositories, uncounted groups (Done) included.
    public let hiddenCount: Int

    /// No focus: the tab as it is, with nothing in other repositories.
    public init(unscoped contents: IssueTabContents) {
        self.init(contents: contents, otherCount: 0, hiddenCount: 0)
    }

    init(contents: IssueTabContents, otherCount: Int, hiddenCount: Int) {
        self.contents = contents
        self.otherCount = otherCount
        self.hiddenCount = hiddenCount
    }
}
