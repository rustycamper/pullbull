import Foundation

/// Where the issue list opens each time the popover opens.
public enum IssueOpenOn: String, Codable, CaseIterable, Sendable {
    case all, lastUsed, assigned, created, board

    public var title: String {
        switch self {
        case .lastUsed: "Last used"
        case .all: IssueScope.all.title
        case .assigned: IssueScope.assigned.title
        case .created: IssueScope.created.title
        case .board: IssueScope.board.title
        }
    }

    /// The scope this choice opens on; nil for Last used, which follows `AppSettings.lastIssueScope`.
    public var scope: IssueScope? {
        switch self {
        case .lastUsed: nil
        case .all: .all
        case .assigned: .assigned
        case .created: .created
        case .board: .board
        }
    }
}

extension AppSettings {
    /// The scope the issue list opens on; every chip is always shown.
    public var issueScopeOnOpen: IssueScope { issueOpenOn.scope ?? lastIssueScope }

    /// The close-time rule: remembers the chip shown, whatever `issueOpenOn` is.
    public mutating func recordLastIssueScope(_ shown: IssueScope) {
        guard lastIssueScope != shown else { return }
        lastIssueScope = shown
    }
}
