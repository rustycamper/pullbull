import Foundation

/// An issue named by another issue or PR: its parent, a sub-issue, a blocker, a blocked issue or a
/// closing reference.
public struct RelatedIssue: Codable, Sendable, Hashable {
    /// The issue's repo and number.
    public let key: PRKey
    /// The issue's title as GitHub sent it.
    public let title: String
    /// The issue on GitHub.
    public let url: URL
    /// Open, as opposed to closed.
    public let isOpen: Bool
    /// Why it was closed; nil while open or when GitHub gave none.
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
    /// How many the group holds on GitHub: the page read and any beyond it.
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
    /// The issue this one is a sub-issue of.
    public let parent: RelatedIssue?
    /// The issue's own sub-issues.
    public let subIssues: RelatedIssues
    /// How many sub-issues it has: GitHub's summary, else the group's count.
    public let subIssuesTotal: Int
    /// How many of them are closed: GitHub's summary, else the closed rows read.
    public let subIssuesCompleted: Int
    /// The issues blocking this one.
    public let blockedBy: RelatedIssues
    /// GitHub's count of open blockers; nil when it gave none.
    public let openBlockedBy: Int?
    /// The issues this one blocks.
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
    public static let empty = IssueRelations()

    /// Whether the issue has a parent or any dependency.
    public var hasDependencies: Bool { parent != nil || blockedBy.isShown || blocking.isShown }

    /// "N open" or "all closed" for Blocked by.
    public var blockedBySummary: String { Self.openSummary(openBlockedBy ?? blockedBy.items.filter(\.isOpen).count) }
    /// "N open" or "all closed" for Blocking.
    public var blockingSummary: String { Self.openSummary(openBlocking ?? blocking.items.filter(\.isOpen).count) }

    /// "N open", or "all closed" when none is.
    public static func openSummary(_ open: Int) -> String { open > 0 ? "\(open) open" : "all closed" }

    /// "N of M done" for Sub-issues.
    public var subIssuesSummary: String { "\(subIssuesCompleted) of \(subIssuesTotal) done" }
}
