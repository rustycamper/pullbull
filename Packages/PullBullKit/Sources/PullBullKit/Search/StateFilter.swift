import Foundation

/// An `is:` search token, named as GitHub's search names it.
public enum StateFilter: String, CaseIterable, Equatable, Sendable {
    /// Open pull requests (drafts included) and open issues.
    case open
    /// Closed pull requests (merged included) and closed issues.
    case closed
    /// Merged pull requests; never an issue.
    case merged
    /// Draft pull requests; never an issue.
    case draft

    /// `is:open`, as typed in the field and sent to GitHub.
    public var token: String { QueryScanner.stateQualifier + rawValue }

    /// What the state lists, for the completion row; true in either mode.
    public var summary: String {
        switch self {
        case .open: "open only"
        case .closed: "closed or merged"
        case .merged: "merged PRs"
        case .draft: "draft PRs"
        }
    }

    /// Whether an issue can be in this state; a search for one that can't skips issues.
    var appliesToIssues: Bool { self == .open || self == .closed }

    func matches(_ pr: PullRequest) -> Bool {
        switch self {
        case .open: pr.state == .open
        case .closed: pr.state != .open
        case .merged: pr.state == .merged
        case .draft: pr.isDraft
        }
    }

    func matches(_ issue: BoardIssue) -> Bool {
        switch self {
        case .open: issue.isOpen
        case .closed: !issue.isOpen
        case .merged, .draft: false
        }
    }
}

public struct StateCandidate: CompletionCandidate {
    public let value: IsValue

    public var id: String { value.name }
    public var insertText: String { value.token }

    public init(value: IsValue) {
        self.value = value
    }

    /// The `is:` values whose name starts with `prefix`, ignoring case: the states, then the conditions.
    static func candidates(prefix: String) -> [StateCandidate] {
        let p = prefix.lowercased()
        return IsValue.all.filter { $0.name.hasPrefix(p) }.map(StateCandidate.init)
    }
}
