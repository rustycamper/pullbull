import Foundation

/// The boards the Board tab's menu offers, per account and owner, kept for this session only. A list
/// is loaded when the menu first opens and again once it is `maxAge` old; a reload keeps the boards
/// on screen, and a failed load is tried again the next time the menu opens.
public struct BoardList: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case loading
        case loaded([BoardSummary])
        case failed(String)
    }

    public static let maxAge: TimeInterval = 300

    private struct Key: Hashable, Sendable {
        let account: AccountRef
        let ownerIsUser: Bool
        /// GitHub compares logins without regard to case.
        let ownerLogin: String

        init(_ account: AccountRef, _ owner: BoardOwner) {
            self.account = account
            ownerIsUser = owner.isUser
            ownerLogin = owner.login.lowercased()
        }
    }

    private struct Entry: Equatable, Sendable {
        var boards: [BoardSummary]?
        var loadedAt: Date?
        var error: String?
        var isLoading = false
    }

    private var entries: [Key: Entry] = [:]

    public init() {}

    /// What the menu shows: the boards once loaded (kept while a reload runs or after it failed), else
    /// loading or the failure; nil when never asked for.
    public func state(account: AccountRef, owner: BoardOwner) -> State? {
        guard let entry = entries[Key(account, owner)] else { return nil }
        if let boards = entry.boards { return .loaded(boards) }
        if let error = entry.error, !entry.isLoading { return .failed(error) }
        return .loading
    }

    /// No load is running and the list was never loaded, failed last time, or is `maxAge` old.
    public func needsLoad(account: AccountRef, owner: BoardOwner, now: Date) -> Bool {
        guard let entry = entries[Key(account, owner)] else { return true }
        guard !entry.isLoading else { return false }
        guard entry.error == nil, let loadedAt = entry.loadedAt else { return true }
        return now.timeIntervalSince(loadedAt) >= Self.maxAge
    }

    public mutating func began(account: AccountRef, owner: BoardOwner) {
        entries[Key(account, owner), default: Entry()].isLoading = true
    }

    public mutating func loaded(_ boards: [BoardSummary], account: AccountRef, owner: BoardOwner, at date: Date) {
        entries[Key(account, owner)] = Entry(boards: boards, loadedAt: date)
    }

    public mutating func failed(_ message: String, account: AccountRef, owner: BoardOwner) {
        let key = Key(account, owner)
        entries[key, default: Entry()].error = message
        entries[key]?.isLoading = false
    }
}

/// One line of the Board tab's menu.
public enum BoardMenuItem: Equatable, Sendable {
    case board(BoardRef, label: String, isCurrent: Bool)
    case loading
    case empty(owner: String)
    /// The list couldn't load, for this reason.
    case failed(String)

    public var title: String {
        switch self {
        case .board(_, let label, _): label
        case .loading: "Loading Boards…"
        case .empty(let owner): "No Projects Boards for \(owner)"
        case .failed: "Couldn't Load Boards"
        }
    }
}

/// What the Board tab's board menu and the filter row's board name that opens it show.
public enum BoardPicker {
    /// The owner's boards as loaded, the chosen one checked, with the chosen board first when the list
    /// lacks it; otherwise one disabled line for loading, no boards or a failure.
    public static func items(_ state: BoardList.State?, current: BoardRef?, owner: BoardOwner) -> [BoardMenuItem] {
        switch state {
        case nil, .loading:
            return [.loading]
        case .failed(let message):
            return [.failed(message)]
        case .loaded(let boards):
            var items = boards.map { summary in
                BoardMenuItem.board(
                    summary.board, label: label(of: summary, among: boards),
                    isCurrent: summary.board.matches(current))
            }
            if let current, !boards.contains(where: { $0.board.matches(current) }) {
                items.insert(.board(current, label: untitled(current), isCurrent: true), at: 0)
            }
            return items.isEmpty ? [.empty(owner: owner.login)] : items
        }
    }

    /// The board's title; "Board #3" for a blank one, and "Roadmap #3" when another of `boards` has the
    /// same title.
    public static func label(of summary: BoardSummary, among boards: [BoardSummary]) -> String {
        let title = trimmed(summary.title)
        guard !title.isEmpty else { return untitled(summary.board) }
        let namesakes = boards.filter { trimmed($0.title).caseInsensitiveCompare(title) == .orderedSame }
        return namesakes.count > 1 ? "\(title) #\(summary.board.number)" : title
    }

    /// The filter row's name for the chosen board: its label in the loaded list, else the title the last
    /// poll fetched for it (`fetchedTitle`, only when the poll was of this board), else its number.
    public static func title(current: BoardRef?, state: BoardList.State?, fetchedTitle: String?) -> String {
        guard let current else { return "Choose a Board" }
        if case .loaded(let boards) = state, let summary = boards.first(where: { $0.board.matches(current) }) {
            return label(of: summary, among: boards)
        }
        if let fetchedTitle, !trimmed(fetchedTitle).isEmpty { return trimmed(fetchedTitle) }
        return untitled(current)
    }

    /// Whether the Board tab offers the menu: not while it explains missing access instead (a personal
    /// board that needs GitHub CLI, no project permission or scope, or Check again running).
    public static func isOffered(
        canReadProjects: Bool, personalAccess: PersonalBoardAccess?, boardError: String?, checkingAccess: Bool
    ) -> Bool {
        if let personalAccess, personalAccess != .ready { return false }
        return canReadProjects && !checkingAccess
            && boardError != RefreshError(APIError.insufficientScopes).message
    }

    private static func untitled(_ board: BoardRef) -> String { "Board #\(board.number)" }

    private static func trimmed(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
}
