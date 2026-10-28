import Foundation

/// The Board tab's folded lanes, kept per board and by Status option id, so a renamed lane keeps its
/// state. Every lane starts open; Done keeps its own fold and is never a lane here.
public struct LaneFolds: Codable, Equatable, Sendable {
    /// Lane ids (`laneID`) folded on each board (`boardKey`).
    private var folded: [String: Set<String>] = [:]

    public init() {}

    /// The lane a group is on the Board tab: its Status option id, or a fixed id for "No status" and
    /// "Not on board". Nil for groups that don't fold this way (repos, the ungrouped list, Done).
    public static func laneID(_ kind: IssueGroupKind) -> String? {
        switch kind {
        case .status(let option): option.id
        case .noStatus: "~no-status"
        case .notOnBoard: "~not-on-board"
        case .repo, .all, .done: nil
        }
    }

    /// A board's key: its owner's kind and login (GitHub logins ignore case) and its number.
    static func boardKey(_ board: BoardRef) -> String {
        "\(board.owner.isUser ? "user" : "org"):\(board.owner.login.lowercased())#\(board.number)"
    }

    public func isFolded(_ kind: IssueGroupKind, on board: BoardRef) -> Bool {
        guard let lane = Self.laneID(kind) else { return false }
        return folded[Self.boardKey(board)]?.contains(lane) ?? false
    }

    /// Folds an open lane and opens a folded one; groups that are not lanes are left alone.
    public mutating func toggle(_ kind: IssueGroupKind, on board: BoardRef) {
        guard let lane = Self.laneID(kind) else { return }
        let key = Self.boardKey(board)
        var lanes = folded[key] ?? []
        if lanes.remove(lane) == nil { lanes.insert(lane) }
        folded[key] = lanes.isEmpty ? nil : lanes
    }

    /// The groups shown folded: none off the Board tab, without a board, or while a search is active
    /// (results never hide inside a fold; the stored state is kept for when the search ends).
    public func shownFolded(
        _ groups: [IssueGroup], tab: IssueTab, board: BoardRef?, searching: Bool
    ) -> Set<IssueGroupKind> {
        guard tab == .board, let board, !searching else { return [] }
        return Set(groups.map(\.kind).filter { isFolded($0, on: board) })
    }

    public init(from decoder: Decoder) throws {
        // A board whose lanes can't be read is dropped; the other boards keep theirs.
        folded = try decoder.singleValueContainer().decode([String: Readable<Set<String>>].self)
            .compactMapValues(\.value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(folded.mapValues { $0.sorted() })
    }
}
