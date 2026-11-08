import Foundation

/// An issue named by another issue or PR: its parent, a sub-issue, a blocker, a blocked issue or a
/// closing reference.
public struct RelatedIssue: Codable, Sendable, Hashable {
    public let key: PRKey
    public let title: String
    public let url: URL
    public let isOpen: Bool
    public let stateReason: IssueStateReason?

    public init(key: PRKey, title: String, url: URL, isOpen: Bool, stateReason: IssueStateReason? = nil) {
        self.key = key
        self.title = title
        self.url = url
        self.isOpen = isOpen
        self.stateReason = stateReason
    }

    /// The state glyph, derived as for `BoardIssue`.
    public var glyph: IssueGlyph {
        if isOpen { return .open }
        switch stateReason {
        case .notPlanned, .duplicate: return .notPlanned
        default: return .completed
        }
    }

    /// "#N" in `repo` (compared ignoring case), else "owner/repo#N".
    public func reference(from repo: String) -> String {
        key.repo.caseInsensitiveCompare(repo) == .orderedSame ? "#\(key.number)" : "\(key.repo)#\(key.number)"
    }
}

/// One group of related issues: the rows GitHub returned, and how many it holds in all.
public struct RelatedIssues: Codable, Sendable, Equatable {
    /// The nodes that decoded; null nodes (issues the account can't read) are dropped.
    public let items: [RelatedIssue]
    public let totalCount: Int
    /// Every node GitHub returned, null ones included.
    public let returned: Int

    public init(items: [RelatedIssue], totalCount: Int, returned: Int) {
        self.items = items
        self.totalCount = totalCount
        self.returned = returned
    }

    public static let empty = RelatedIssues(items: [], totalCount: 0, returned: 0)

    /// Issues beyond the ones returned.
    public var moreCount: Int { max(totalCount - returned, 0) }

    /// Whether the group has anything to show: a group of only null nodes is empty.
    public var isShown: Bool { !items.isEmpty || moreCount > 0 }
}

/// An issue's parent, sub-issues and dependencies.
public struct IssueRelations: Codable, Sendable, Equatable {
    public let parent: RelatedIssue?
    public let subIssues: RelatedIssues
    public let subIssuesTotal: Int
    public let subIssuesCompleted: Int
    public let blockedBy: RelatedIssues
    /// GitHub's count of open blockers; nil when it gave none.
    public let openBlockedBy: Int?
    public let blocking: RelatedIssues
    /// GitHub's count of open issues this one blocks; nil when it gave none.
    public let openBlocking: Int?

    public init(
        parent: RelatedIssue? = nil, subIssues: RelatedIssues = .empty, subIssuesTotal: Int = 0,
        subIssuesCompleted: Int = 0, blockedBy: RelatedIssues = .empty, openBlockedBy: Int? = nil,
        blocking: RelatedIssues = .empty, openBlocking: Int? = nil
    ) {
        self.parent = parent
        self.subIssues = subIssues
        self.subIssuesTotal = subIssuesTotal
        self.subIssuesCompleted = subIssuesCompleted
        self.blockedBy = blockedBy
        self.openBlockedBy = openBlockedBy
        self.blocking = blocking
        self.openBlocking = openBlocking
    }

    /// No relations at all, as opposed to nil on an `IssueDetail` cached before they were read.
    public static let none = IssueRelations()

    /// Whether the issue has a parent or any dependency.
    public var hasDependencies: Bool { parent != nil || blockedBy.isShown || blocking.isShown }

    public var blockedBySummary: String { Self.openSummary(openBlockedBy ?? blockedBy.items.filter(\.isOpen).count) }
    public var blockingSummary: String { Self.openSummary(openBlocking ?? blocking.items.filter(\.isOpen).count) }

    /// "N open", or "all closed" when none is.
    public static func openSummary(_ open: Int) -> String { open > 0 ? "\(open) open" : "all closed" }

    public var subIssuesSummary: String { "\(subIssuesCompleted) of \(subIssuesTotal) done" }
}
