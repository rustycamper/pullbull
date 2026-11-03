import Foundation

/// The repository and time focuses together. Either may be absent; a row stays when it passes both.
public struct ListFocus: Equatable, Sendable {
    public let repo: RepoFocus?
    public let time: TimeFocus?

    public init(repo: RepoFocus?, time: TimeFocus?) {
        self.repo = repo
        self.time = time
    }

    public var isActive: Bool { repo != nil || time != nil }

    public func scope(_ contents: TabContents) -> ScopedTab {
        RepoFocus.scopeRows(contents, keeping: keeps)
    }

    /// Each section narrowed to the focus, sections it empties left out.
    public func scope(_ list: PRList) -> ScopedPRList {
        var hidden = 0
        var sections: [ListSection] = []
        for section in list.sections {
            let scoped = scope(section.contents)
            hidden += scoped.hiddenCount
            if !scoped.contents.rows.isEmpty {
                sections.append(ListSection(section: section.section, contents: scoped.contents))
            }
        }
        return ScopedPRList(list: PRList(scope: list.scope, sections: sections), hiddenCount: hidden)
    }

    public func scope(_ closed: [PullRequest]) -> [PullRequest] {
        closed.filter(keeps)
    }

    /// Repository groups merge only while a repository focus is set.
    public func scope(_ contents: IssueTabContents) -> ScopedIssueTab {
        RepoFocus.scopeIssues(contents, keeping: keeps, mergeRepoGroups: repo != nil)
    }

    /// Each section narrowed to the focus; a section it empties is left out unless it is loading or failed.
    public func scope(_ list: IssueList) -> ScopedIssueList {
        var hidden = 0
        var sections: [IssueListSection] = []
        for section in list.sections {
            let kept = section.issues.filter(keeps)
            hidden += section.issues.count - kept.count
            switch section.state {
            case .loading, .failed:
                sections.append(section)
            case .rows, .stale:
                if !kept.isEmpty {
                    sections.append(IssueListSection(section: section.section, issues: kept, state: section.state))
                }
            }
        }
        let status = list.status.filter { key, _ in sections.contains { $0.issues.contains { $0.key == key } } }
        return ScopedIssueList(
            list: IssueList(
                sections: sections, status: status, nothingAssigned: list.nothingAssigned, isEmpty: list.isEmpty),
            hiddenCount: hidden)
    }

    /// "Nothing in widgets updated today on Review".
    public func emptyTitle(repoName: String?, tabTitle: String) -> String {
        var parts = ["Nothing"]
        if let repoName { parts.append("in \(repoName)") }
        if let time { parts.append("updated \(time.step.title)") }
        parts.append("on \(tabTitle)")
        return parts.joined(separator: " ")
    }

    /// The count of rows the focus hides: "3 in other repos" for a repository focus alone, else "3 hidden".
    public func hiddenText(_ count: Int) -> String {
        time == nil ? "\(count) in other repos" : "\(count) hidden"
    }

    private func keeps(_ pr: PullRequest) -> Bool {
        (repo?.matches(pr.key) ?? true) && (time?.matches(pr) ?? true)
    }

    private func keeps(_ issue: BoardIssue) -> Bool {
        (repo?.matches(issue.key) ?? true) && (time?.matches(issue) ?? true)
    }
}
