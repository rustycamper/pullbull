import Foundation

/// A repository label as an edit sends it (`id`) and shows it (`name`, `color`).
public struct LabelRef: Hashable, Sendable {
    public let id: String
    public let name: String
    /// GitHub's 6-hex colour; nil when it gave none.
    public let color: String?

    public init(id: String, name: String, color: String?) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// A user as an assignee edit sends them (`id`) and shows them (`login`, `avatarURL`).
public struct PersonRef: Hashable, Sendable {
    public let id: String
    public let login: String
    public let avatarURL: URL?

    public init(id: String, login: String, avatarURL: URL?) {
        self.id = id
        self.login = login
        self.avatarURL = avatarURL
    }
}

/// How a Status edit changes whether the issue is on the board.
public enum BoardPlacement: Hashable, Sendable {
    /// It was on the board and stays.
    case already
    /// The edit added it.
    case added
    /// The edit took it off (only an undo of `added` does).
    case removed

    var inverse: BoardPlacement {
        switch self {
        case .already: .already
        case .added: .removed
        case .removed: .added
        }
    }
}

/// One edit to one issue or pull request: what it was and what it becomes, so it can be shown before
/// GitHub agrees, and undone.
public enum EditChange: Hashable, Sendable {
    case status(from: BoardStatusValue?, to: BoardStatusValue?, placement: BoardPlacement)
    case labels(added: [LabelRef], removed: [LabelRef])
    case assignees(added: [PersonRef], removed: [PersonRef])
    /// A pull request's review requests: people by login, teams by slug.
    case reviewers(added: [Reviewer], removed: [Reviewer])
    /// The viewer's submitted review of a pull request, on `commit`, with the text sent; never undone or part-applied.
    case review(state: ReviewState, commit: String, viewer: String, body: String = "")
    /// The viewer merged a pull request; never undone or part-applied.
    case merged(viewer: String)
    /// The viewer set a pull request to merge when ready, or cancelled that; never undone or part-applied.
    case autoMerge(enabled: Bool, viewer: String)
    /// The viewer marked a pull request ready for review (`isDraft` false) or converted it to draft; never
    /// undone or part-applied.
    case draft(isDraft: Bool, viewer: String)

    /// The edit that puts things back.
    public var inverse: EditChange {
        switch self {
        case .status(let from, let to, let placement): .status(from: to, to: from, placement: placement.inverse)
        case .labels(let added, let removed): .labels(added: removed, removed: added)
        case .assignees(let added, let removed): .assignees(added: removed, removed: added)
        case .reviewers(let added, let removed): .reviewers(added: removed, removed: added)
        case .review, .merged, .autoMerge, .draft: self
        }
    }

    /// The halves `result` says GitHub applied; a Status change is returned as is.
    public func keeping(_ result: SetChangeResult) -> EditChange {
        switch self {
        case .status, .review, .merged, .autoMerge, .draft: self
        case .labels(let added, let removed):
            .labels(added: result.addApplied ? added : [], removed: result.removeApplied ? removed : [])
        case .assignees(let added, let removed):
            .assignees(added: result.addApplied ? added : [], removed: result.removeApplied ? removed : [])
        case .reviewers(let added, let removed):
            .reviewers(added: result.addApplied ? added : [], removed: result.removeApplied ? removed : [])
        }
    }

    /// Nothing to send: no labels, assignees or reviewers toggled, or the same Status on an issue already on the board.
    public var isEmpty: Bool {
        switch self {
        case .status(let from, let to, let placement): placement == .already && from?.optionId == to?.optionId
        case .labels(let added, let removed): added.isEmpty && removed.isEmpty
        case .assignees(let added, let removed): added.isEmpty && removed.isEmpty
        case .reviewers(let added, let removed): added.isEmpty && removed.isEmpty
        case .review, .merged, .autoMerge, .draft: false
        }
    }
}
