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
    public let state: StateFilter

    public var id: String { state.rawValue }
    public var insertText: String { state.token }

    public init(state: StateFilter) {
        self.state = state
    }

    /// The states whose name starts with `prefix`, ignoring case, in `StateFilter` order.
    static func candidates(prefix: String) -> [StateCandidate] {
        let p = prefix.lowercased()
        return StateFilter.allCases.filter { $0.rawValue.hasPrefix(p) }.map(StateCandidate.init)
    }
}
