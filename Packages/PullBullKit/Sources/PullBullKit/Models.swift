import Foundation

public struct PRKey: Hashable, Codable, Sendable {
    public let repo: String
    public let number: Int

    public init(repo: String, number: Int) {
        self.repo = repo
        self.number = number
    }
}

public enum PRState: String, Codable, Sendable, Hashable {
    case open, closed, merged
}

/// The pull request's state glyph, told apart by shape. Draft shows only while the PR is open.
public enum PRGlyph: Sendable {
    case open, draft, merged, closed

    public init(state: PRState, isDraft: Bool) {
        switch state {
        case .open: self = isDraft ? .draft : .open
        case .merged: self = .merged
        case .closed: self = .closed
        }
    }
}

public enum CIState: String, Codable, Sendable, Hashable {
    /// `skipped`: every check run ended skipped or neutral, so nothing ran to pass; as a check's state,
    /// that one run did. It passes for Ready to merge, like `none`, but never shows as passed.
    case success, failure, pending, skipped, none
}

/// Whether GitHub can merge the PR without conflicts, from GraphQL's `MergeableState`. `unknown`
/// (still computing after a push) is shown as nothing, like a PR without the field.
public enum Mergeable: String, Codable, Sendable, Hashable {
    case mergeable = "MERGEABLE", conflicting = "CONFLICTING", unknown = "UNKNOWN"
}

public enum ReviewState: String, Codable, Sendable, Hashable {
    case approved, changesRequested, commented, dismissed, pending
}

public struct Review: Hashable, Codable, Sendable {
    public let author: String
    public let state: ReviewState
    public let submittedAt: Date?
    /// The commit the review was submitted on; nil when unknown (older caches, detail reviews).
    public let commitOid: String?

    public init(author: String, state: ReviewState, submittedAt: Date?, commitOid: String? = nil) {
        self.author = author
        self.state = state
        self.submittedAt = submittedAt
        self.commitOid = commitOid
    }
}

public enum Reviewer: Hashable, Codable, Sendable {
    case user(String)
    case team(String)
}

public struct PullRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: PRKey { key }
    public let key: PRKey
    public let title: String
    public let url: URL
    public let author: String
    public let authorAvatarURL: URL?
    public let state: PRState
    public let isDraft: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let closedAt: Date?
    public let headRef: String
    public let baseRef: String
    public let ci: CIState
    public let headCommitDate: Date?
    public let commentCount: Int
    public let lastCommentAuthor: String?
    public let latestReviews: [Review]
    public let reviewRequests: [Reviewer]
    /// The head commit's oid; nil in snapshots cached before it was stored.
    public let headCommitOid: String?
    /// Label names; empty in snapshots cached before they were stored.
    public let labels: [String]
    /// Who merged it; nil while unmerged, for a deleted account, and in snapshots cached before it was stored.
    public let mergedBy: String?
    /// Nil when GitHub sent none or a value this build doesn't know, and in snapshots cached before it was stored.
    public let mergeable: Mergeable?

    public var glyph: PRGlyph { PRGlyph(state: state, isDraft: isDraft) }
    /// Only a definite CONFLICTING counts; UNKNOWN and a missing value don't.
    public var hasConflicts: Bool { mergeable == .conflicting }

    public init(
        key: PRKey, title: String, url: URL, author: String, authorAvatarURL: URL?,
        state: PRState, isDraft: Bool, createdAt: Date, updatedAt: Date, closedAt: Date?,
        headRef: String, baseRef: String, ci: CIState, headCommitDate: Date?,
        commentCount: Int, lastCommentAuthor: String?,
        latestReviews: [Review], reviewRequests: [Reviewer], headCommitOid: String? = nil, labels: [String] = [],
        mergedBy: String? = nil, mergeable: Mergeable? = nil
    ) {
        self.key = key
        self.title = title
        self.url = url
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.state = state
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.headRef = headRef
        self.baseRef = baseRef
        self.ci = ci
        self.headCommitDate = headCommitDate
        self.commentCount = commentCount
        self.lastCommentAuthor = lastCommentAuthor
        self.latestReviews = latestReviews
        self.reviewRequests = reviewRequests
        self.headCommitOid = headCommitOid
        self.labels = labels
        self.mergedBy = mergedBy
        self.mergeable = mergeable
    }

    /// Pull requests cached before labels were stored have none.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(PRKey.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        author = try c.decode(String.self, forKey: .author)
        authorAvatarURL = try c.decodeIfPresent(URL.self, forKey: .authorAvatarURL)
        state = try c.decode(PRState.self, forKey: .state)
        isDraft = try c.decode(Bool.self, forKey: .isDraft)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        headRef = try c.decode(String.self, forKey: .headRef)
        baseRef = try c.decode(String.self, forKey: .baseRef)
        ci = try c.decode(CIState.self, forKey: .ci)
        headCommitDate = try c.decodeIfPresent(Date.self, forKey: .headCommitDate)
        commentCount = try c.decode(Int.self, forKey: .commentCount)
        lastCommentAuthor = try c.decodeIfPresent(String.self, forKey: .lastCommentAuthor)
        latestReviews = try c.decode([Review].self, forKey: .latestReviews)
        reviewRequests = try c.decode([Reviewer].self, forKey: .reviewRequests)
        headCommitOid = try c.decodeIfPresent(String.self, forKey: .headCommitOid)
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        mergedBy = try c.decodeIfPresent(String.self, forKey: .mergedBy)
        mergeable = try c.decodeIfPresent(String.self, forKey: .mergeable).flatMap(Mergeable.init(rawValue:))
    }
}

/// Why an issue was closed (or that it was reopened), from GraphQL's `IssueStateReason`.
public enum IssueStateReason: String, Codable, Sendable, Hashable {
    case completed, notPlanned, duplicate, reopened
}

/// The issue's state glyph, told apart by shape.
public enum IssueGlyph: Sendable {
    case open, completed, notPlanned
}

/// The colour the owner gave a Status option, from GraphQL's `ProjectV2SingleSelectFieldOptionColor`.
public enum StatusOptionColor: String, Codable, Sendable, Hashable, CaseIterable {
    case gray = "GRAY", blue = "BLUE", green = "GREEN", yellow = "YELLOW"
    case orange = "ORANGE", red = "RED", pink = "PINK", purple = "PURPLE"
}

/// One option of a board's single-select Status field, in the board's order.
public struct StatusOption: Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    /// Nil when GitHub sent none or a value this build doesn't know.
    public let color: StatusOptionColor?

    public init(id: String, name: String, color: StatusOptionColor? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }

    /// Options cached before colours were stored have none; an unknown colour is dropped, not an error.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color).flatMap(StatusOptionColor.init(rawValue:))
    }
}

/// A board item's Status value.
public struct BoardStatusValue: Codable, Sendable, Hashable {
    public let optionId: String
    public let name: String

    public init(optionId: String, name: String) {
        self.optionId = optionId
        self.name = name
    }
}

public struct Assignee: Codable, Sendable, Hashable {
    public let login: String
    public let avatarURL: URL?

    public init(login: String, avatarURL: URL?) {
        self.login = login
        self.avatarURL = avatarURL
    }
}

/// The latest assignment that added the viewer; `actor` is nil for a deleted account.
public struct Assignment: Codable, Sendable, Hashable {
    public let actor: String?
    public let at: Date

    public init(actor: String?, at: Date) {
        self.actor = actor
        self.at = at
    }
}

public struct BoardIssue: Identifiable, Hashable, Codable, Sendable {
    public var id: PRKey { key }
    public let key: PRKey
    public let title: String
    public let url: URL
    public let isOpen: Bool
    /// Nil for a deleted (ghost) author and in issues cached before it was stored.
    public let author: String?
    public let stateReason: IssueStateReason?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let closedAt: Date?
    public let commentCount: Int
    public let labels: [String]
    /// GitHub's 6-hex colour for each of `labels`, by position; nil where it's missing, and empty in
    /// issues cached before it was stored. Read it through `labelColor(at:)`.
    public let labelColors: [String?]
    public let assignees: [Assignee]
    /// The board item's Status; set only on board items.
    public let status: BoardStatusValue?
    /// `ProjectV2Item.databaseId`, for "View on board"; set only on board items.
    public let boardItemId: Int?
    /// Set only on Assigned search results.
    public let myAssignment: Assignment?

    /// The colour of the label at `index`, nil when GitHub gave none or the cache predates it.
    public func labelColor(at index: Int) -> String? {
        labelColors.indices.contains(index) ? labelColors[index] : nil
    }

    public var glyph: IssueGlyph {
        if isOpen { return .open }
        switch stateReason {
        case .notPlanned, .duplicate: return .notPlanned
        default: return .completed
        }
    }

    public init(
        key: PRKey, title: String, url: URL, isOpen: Bool,
        author: String? = nil, stateReason: IssueStateReason? = nil,
        createdAt: Date? = nil, updatedAt: Date? = nil, closedAt: Date? = nil,
        commentCount: Int = 0, labels: [String] = [], labelColors: [String?] = [], assignees: [Assignee] = [],
        status: BoardStatusValue? = nil, boardItemId: Int? = nil, myAssignment: Assignment? = nil
    ) {
        self.key = key
        self.title = title
        self.url = url
        self.isOpen = isOpen
        self.author = author
        self.stateReason = stateReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.commentCount = commentCount
        self.labels = labels
        self.labelColors = labelColors
        self.assignees = assignees
        self.status = status
        self.boardItemId = boardItemId
        self.myAssignment = myAssignment
    }

    /// Issues cached before the Issues mode hold only key, title, url and isOpen.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(PRKey.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        isOpen = try c.decode(Bool.self, forKey: .isOpen)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        stateReason = try c.decodeIfPresent(IssueStateReason.self, forKey: .stateReason)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        labelColors = try c.decodeIfPresent([String?].self, forKey: .labelColors) ?? []
        assignees = try c.decodeIfPresent([Assignee].self, forKey: .assignees) ?? []
        status = try c.decodeIfPresent(BoardStatusValue.self, forKey: .status)
        boardItemId = try c.decodeIfPresent(Int.self, forKey: .boardItemId)
        myAssignment = try c.decodeIfPresent(Assignment.self, forKey: .myAssignment)
    }
}
