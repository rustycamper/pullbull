import Foundation

/// What the issue list shows: everything, or one of the fetched lists. The tab raw values are the
/// `settings.sorts` keys, so the sorts saved per `IssueTab` carry over; All's is `issuesAll`, as
/// `PRScope.all` owns `all`.
public enum IssueScope: String, Codable, CaseIterable, Sendable {
    case all = "issuesAll", assigned, created, board

    public init(_ tab: IssueTab) {
        switch tab {
        case .assigned: self = .assigned
        case .created: self = .created
        case .board: self = .board
        }
    }

    /// The fetched list this scope shows; nil for All, which spans them.
    public var tab: IssueTab? {
        switch self {
        case .all: nil
        case .assigned: .assigned
        case .created: .created
        case .board: .board
        }
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .assigned: "Assigned"
        case .created: "Created"
        case .board: "Board"
        }
    }

    /// The scope after clicking `scope`'s chip: the selected chip goes back to All.
    public func picking(_ scope: IssueScope) -> IssueScope {
        self == scope ? .all : scope
    }
}
