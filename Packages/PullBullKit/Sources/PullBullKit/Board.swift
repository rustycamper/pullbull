import Foundation

/// Who owns a Projects (v2) board: an organization, or a user (a personal board).
public enum BoardOwner: Hashable, Sendable {
    case org(String)
    case user(String)

    public var login: String {
        switch self {
        case .org(let login), .user(let login): login
        }
    }

    public var isUser: Bool {
        guard case .user = self else { return false }
        return true
    }

    /// The same kind of owner with the same login, which GitHub compares without regard to case.
    public func matches(_ other: BoardOwner) -> Bool {
        isUser == other.isUser && login.caseInsensitiveCompare(other.login) == .orderedSame
    }

    /// The owner's kind and login, which GitHub compares without regard to case: "org:acme", "user:me".
    public var key: String { "\(isUser ? "user" : "org"):\(login.lowercased())" }
}

extension BoardOwner: Codable {
    private enum CodingKeys: String, CodingKey { case kind, login }
    private enum Kind: String, Codable { case org, user }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let login = try c.decode(String.self, forKey: .login)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .org: self = .org(login)
        case .user: self = .user(login)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isUser ? Kind.user : Kind.org, forKey: .kind)
        try c.encode(login, forKey: .login)
    }
}

/// One Projects board: its owner and its number, which is unique only within that owner.
public struct BoardRef: Codable, Hashable, Sendable {
    public let owner: BoardOwner
    public let number: Int

    public init(owner: BoardOwner, number: Int) {
        self.owner = owner
        self.number = number
    }

    public static func org(_ login: String, _ number: Int) -> BoardRef {
        BoardRef(owner: .org(login), number: number)
    }

    public static func user(_ login: String, _ number: Int) -> BoardRef {
        BoardRef(owner: .user(login), number: number)
    }

    /// The same board: the same number of a matching owner.
    public func matches(_ other: BoardRef?) -> Bool {
        guard let other else { return false }
        return number == other.number && owner.matches(other.owner)
    }
}

/// The node IDs board mutations take: the project's, and its single-select Status field's (nil when the
/// board has none).
public struct BoardIds: Codable, Sendable, Equatable {
    public let projectId: String
    public let statusFieldId: String?

    public init(projectId: String, statusFieldId: String?) {
        self.projectId = projectId
        self.statusFieldId = statusFieldId
    }
}

/// One board a picker offers.
public struct BoardSummary: Hashable, Sendable {
    public let board: BoardRef
    public let title: String

    public init(board: BoardRef, title: String) {
        self.board = board
        self.title = title
    }

    /// The board to choose when none is: the lowest-numbered (the owner's first).
    public static func first(of boards: [BoardSummary]) -> BoardSummary? {
        boards.min { $0.board.number < $1.board.number }
    }

    /// What a board picker offers: `boards` as loaded, with the chosen board first, by number, when
    /// they lack it (deleted, or no longer readable), so the choice still shows.
    public static func choices(_ boards: [BoardSummary], current: BoardRef?) -> [BoardSummary] {
        guard let current, !boards.contains(where: { $0.board == current }) else { return boards }
        return [BoardSummary(board: current, title: "#\(current.number)")] + boards
    }
}

public extension FetchScope {
    /// Whose boards this scope shows: the org's, or in no-org mode the user's own. Org mode never
    /// shows a personal board.
    var boardOwner: BoardOwner {
        switch self {
        case .org(let org): .org(org)
        case .personal(let login, _): .user(login)
        }
    }

    /// Whether `board` is one this scope shows: its owner is the scope's.
    func shows(_ board: BoardRef) -> Bool {
        board.owner.matches(boardOwner)
    }
}

/// How an account in no-org mode can get its personal board when its own token can't read it.
public enum PersonalBoardAccess: Equatable, Sendable {
    /// The token can read the board.
    case ready
    /// GitHub CLI already has this login with project access: switch PullBull to it.
    case useGhLogin(String)
    /// GitHub CLI has this login without project access: run `command`.
    case addScope(command: String)
    /// GitHub CLI doesn't have this login: run `command` to log in with project access.
    case logIn(command: String)

    /// GitHub Apps get no permission for user-owned boards, so an app account needs the same login
    /// from GitHub CLI; a `gh` login needs the `read:project` (or `project`) scope.
    public static func of(login: String, source: AccountSource, ghAccounts: [GhAccount]) -> PersonalBoardAccess {
        let gh = ghAccounts.first { $0.login.caseInsensitiveCompare(login) == .orderedSame }
        let activeLogin = ghAccounts.first(where: \.active)?.login
        switch source {
        case .gh:
            guard let gh, !gh.canReadProjects else { return .ready }
            return .addScope(command: GhCommands.addProjectScope(login: gh.login, activeLogin: activeLogin))
        case .gitHubApp:
            guard let gh else { return .logIn(command: GhCommands.logIn) }
            return gh.canReadProjects
                ? .useGhLogin(gh.login)
                : .addScope(command: GhCommands.addProjectScope(login: gh.login, activeLogin: activeLogin))
        }
    }
}
