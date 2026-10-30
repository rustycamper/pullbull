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

    public func scope(_ closed: [PullRequest]) -> [PullRequest] {
        closed.filter(keeps)
    }

    /// Repository groups merge only while a repository focus is set.
    public func scope(_ contents: IssueTabContents) -> ScopedIssueTab {
        RepoFocus.scopeIssues(contents, keeping: keeps, mergeRepoGroups: repo != nil)
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
