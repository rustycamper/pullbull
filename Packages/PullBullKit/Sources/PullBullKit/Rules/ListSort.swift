import Foundation

/// The order of a list tab's rows: what's new, what's stuck, or what's old. Each choice has one fixed
/// direction. PR tabs offer Waiting longest (the review wait); issue tabs offer Newest first.
public enum ListSort: String, Codable, CaseIterable, Sendable {
    /// Last update, newest first: every tab's default and the order before sorting existed.
    case recentlyUpdated
    /// The longest review wait first (`ReviewWait.since`); PRs with none follow in updated order.
    case waitingLongest
    /// When it was opened, oldest first.
    case oldestFirst
    /// When it was opened, newest first.
    case newestFirst
    /// The board's Status order, for All. Reads as Recently updated wherever there is no board.
    case boardStatus

    public var title: String {
        switch self {
        case .recentlyUpdated: "Recently updated"
        case .waitingLongest: "Waiting longest"
        case .oldestFirst: "Oldest first"
        case .newestFirst: "Newest first"
        case .boardStatus: "Board status"
        }
    }

    public static func choices(for scope: PRScope) -> [ListSort] { [.recentlyUpdated, .waitingLongest, .oldestFirst] }
    public static func choices(for tab: PRTab) -> [ListSort] { choices(for: PRScope(tab)) }
    public static func choices(for tab: IssueTab) -> [ListSort] { [.recentlyUpdated, .newestFirst, .oldestFirst] }

    /// All offers Board status while a board is available; a tab scope offers its tab's choices.
    public static func choices(for scope: IssueScope, boardAvailable: Bool) -> [ListSort] {
        guard let tab = scope.tab else {
            return choices(for: IssueTab.assigned) + (boardAvailable ? [.boardStatus] : [])
        }
        return choices(for: tab)
    }
}

extension AppSettings {
    /// `scope`'s sort: the stored one when the scope offers it, else Recently updated.
    public func sort(for scope: PRScope) -> ListSort {
        sorts[scope.rawValue].flatMap { ListSort.choices(for: scope).contains($0) ? $0 : nil } ?? .recentlyUpdated
    }

    public func sort(for tab: PRTab) -> ListSort { sort(for: PRScope(tab)) }

    public func sort(for tab: IssueTab) -> ListSort {
        sorts[tab.rawValue].flatMap { ListSort.choices(for: tab).contains($0) ? $0 : nil } ?? .recentlyUpdated
    }

    /// `scope`'s sort: the stored one when the scope offers it, else Recently updated.
    public func sort(for scope: IssueScope, boardAvailable: Bool) -> ListSort {
        sorts[scope.rawValue].flatMap {
            ListSort.choices(for: scope, boardAvailable: boardAvailable).contains($0) ? $0 : nil
        } ?? .recentlyUpdated
    }

    public mutating func setSort(_ sort: ListSort, for scope: IssueScope) { sorts[scope.rawValue] = sort }
    public mutating func setSort(_ sort: ListSort, for scope: PRScope) { sorts[scope.rawValue] = sort }
    public mutating func setSort(_ sort: ListSort, for tab: PRTab) { setSort(sort, for: PRScope(tab)) }
    public mutating func setSort(_ sort: ListSort, for tab: IssueTab) { sorts[tab.rawValue] = sort }
}
