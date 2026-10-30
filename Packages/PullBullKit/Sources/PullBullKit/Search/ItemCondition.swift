import Foundation

/// An `is:` search token for what a pull request needs, as opposed to the state it is in.
public enum ItemCondition: String, CaseIterable, Equatable, Sendable {
    case ready
    case conflict
    case failing
    case approved
    case unanswered

    /// `is:ready`, as typed in the field.
    public var token: String { QueryScanner.stateQualifier + rawValue }

    /// What the condition lists, for the completion row.
    public var summary: String {
        switch self {
        case .ready: "ready to merge"
        case .conflict: "merge conflicts"
        case .failing: "checks failed"
        case .approved: "has an approval"
        case .unanswered: "reply owed"
        }
    }

    /// What GitHub gets for the condition, or nil when it can't say. `is:approved` sends nothing: GitHub's
    /// `review:approved` reads the overall review verdict, narrower than "has an approval" here, so it would
    /// drop rows the local filter keeps.
    public var serverQualifier: String? {
        switch self {
        case .failing: "status:failure"
        case .ready, .conflict, .approved, .unanswered: nil
        }
    }

    /// Whether the condition is about pull requests only; a search with one skips issues.
    public var prOnly: Bool { self != .unanswered }

    /// `unanswered` reads the viewer: an open pull request of theirs whose newest comment is someone else's,
    /// and not a bot's.
    func matches(_ pr: PullRequest, viewer: String) -> Bool {
        switch self {
        case .ready: ReviewRules.isReadyToMerge(pr)
        case .conflict: pr.hasConflicts
        case .failing: pr.ci == .failure
        case .approved: pr.latestReviews.contains { $0.state == .approved }
        case .unanswered:
            pr.state == .open && pr.author.caseInsensitiveCompare(viewer) == .orderedSame
                && LastComment.isOwed(author: pr.lastCommentAuthor, byBot: pr.lastCommentByBot, viewer: viewer)
        }
    }

    /// Only `unanswered` can match an issue: an open one assigned to or opened by the viewer, whose newest
    /// comment is someone else's, and not a bot's.
    func matches(_ issue: BoardIssue, viewer: String) -> Bool {
        guard self == .unanswered, issue.isOpen else { return false }
        func isViewer(_ login: String?) -> Bool { login?.caseInsensitiveCompare(viewer) == .orderedSame }
        return (isViewer(issue.author) || issue.assignees.contains { isViewer($0.login) })
            && LastComment.isOwed(author: issue.lastCommentAuthor, byBot: issue.lastCommentByBot, viewer: viewer)
    }
}

/// A `review:` search token.
public enum ReviewFilter: String, CaseIterable, Equatable, Sendable {
    case changes
    case none

    /// `review:changes`, as typed in the field.
    public var token: String { QueryScanner.reviewQualifier + rawValue }

    /// What GitHub gets. `review:changes` sends nothing: GitHub's `changes_requested` reads the overall
    /// review verdict, narrower than "has a changes-requested review" here.
    public var serverQualifier: String? {
        switch self {
        case .changes: nil
        case .none: "review:none"
        }
    }

    public var summary: String {
        switch self {
        case .changes: "changes requested"
        case .none: "no reviews"
        }
    }

    func matches(_ pr: PullRequest) -> Bool {
        switch self {
        case .changes: pr.latestReviews.contains { $0.state == .changesRequested }
        case .none: pr.latestReviews.isEmpty
        }
    }
}

/// What follows `is:`: a state, or a condition.
public enum IsValue: Equatable, Sendable {
    case state(StateFilter)
    case condition(ItemCondition)

    /// The word after `is:`.
    public var name: String {
        switch self {
        case .state(let state): state.rawValue
        case .condition(let condition): condition.rawValue
        }
    }

    public var token: String { QueryScanner.stateQualifier + name }

    public var summary: String {
        switch self {
        case .state(let state): state.summary
        case .condition(let condition): condition.summary
        }
    }

    /// Every `is:` value in completion order: the states, then the conditions.
    static let all: [IsValue] = StateFilter.allCases.map(IsValue.state) + ItemCondition.allCases.map(IsValue.condition)
}

public struct ReviewCandidate: CompletionCandidate {
    public let review: ReviewFilter

    public var id: String { review.rawValue }
    public var insertText: String { review.token }

    public init(review: ReviewFilter) {
        self.review = review
    }

    /// The filters whose name starts with `prefix`, ignoring case, in `ReviewFilter` order.
    static func candidates(prefix: String) -> [ReviewCandidate] {
        let p = prefix.lowercased()
        return ReviewFilter.allCases.filter { $0.rawValue.hasPrefix(p) }.map(ReviewCandidate.init)
    }
}

/// Who wrote the newest comment, for `is:unanswered`.
public enum LastComment {
    /// Whether the author is a bot: GitHub's `Bot` type when known, else the `[bot]` login suffix.
    public static func isBot(login: String?, byBot: Bool?) -> Bool {
        byBot ?? login?.lowercased().hasSuffix("[bot]") ?? false
    }

    /// The newest comment is someone else's: there is one, and neither the viewer nor a bot wrote it.
    static func isOwed(author: String?, byBot: Bool?, viewer: String) -> Bool {
        guard let author, author.caseInsensitiveCompare(viewer) != .orderedSame else { return false }
        return !isBot(login: author, byBot: byBot)
    }
}
