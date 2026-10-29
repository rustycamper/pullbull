import Foundation

/// A `status:` search token: the selected board's Status column, by part of its name or, quoted, the
/// whole name. Case is ignored either way.
public struct BoardStatusFilter: Hashable, Sendable {
    /// As typed, without quotes.
    public let name: String
    /// Quoted: the whole name must match.
    public let exact: Bool

    public init(name: String, exact: Bool) {
        self.name = name
        self.exact = exact
    }

    /// `status:prog`, or `status:"In progress"` for an exact name.
    public var token: String {
        QueryScanner.statusQualifier + (exact ? "\"\(name)\"" : name)
    }

    /// Whether a Status named `status` matches; no Status never does.
    func matches(_ status: String?) -> Bool {
        guard let status else { return false }
        return exact
            ? status.caseInsensitiveCompare(name) == .orderedSame
            : status.range(of: name, options: .caseInsensitive) != nil
    }

    /// The same filter, ignoring the name's case.
    func isSame(as other: BoardStatusFilter) -> Bool {
        exact == other.exact && name.caseInsensitiveCompare(other.name) == .orderedSame
    }
}

public struct StatusCandidate: CompletionCandidate {
    public let name: String
    /// Open board issues in this column.
    public let openCount: Int

    public var id: String { name.lowercased() }
    /// Always quoted: a picked column is matched whole, so `Done` never also finds `Not done`.
    public var insertText: String { BoardStatusFilter(name: name, exact: true).token }

    public init(name: String, openCount: Int) {
        self.name = name
        self.openCount = openCount
    }
}

/// The selected board's Status columns, for the `status:` completion. Derived, never stored.
public struct StatusIndex: Equatable, Sendable {
    public static let empty = StatusIndex(columns: [])

    /// Board order.
    private let columns: [StatusCandidate]

    private init(columns: [StatusCandidate]) {
        self.columns = columns
    }

    /// The board's Status options while the board is available, each with its open issues as search
    /// reads them.
    public static func build(_ snap: Snapshot) -> StatusIndex {
        guard snap.boardStatus == .available, let options = snap.boardStatusOptions else { return .empty }
        var counts: [String: Int] = [:]
        for issue in SearchEngine.cachedIssues(snap) where issue.isOpen {
            if let id = issue.status?.optionId { counts[id, default: 0] += 1 }
        }
        var seen = Set<String>()
        let columns = options.filter { seen.insert($0.name.lowercased()).inserted }
            .map { StatusCandidate(name: $0.name, openCount: counts[$0.id] ?? 0) }
        return StatusIndex(columns: columns)
    }

    public var isEmpty: Bool { columns.isEmpty }

    /// Ranked for prefix `p`, ignoring case: (1) the name, (2) a name starting with `p`, (3) a word of the
    /// name starting with `p`, (4) a name containing `p`. Within a tier, in board order.
    public func candidates(prefix: String) -> [StatusCandidate] {
        let p = prefix.lowercased()
        let ranked = columns.enumerated().compactMap { offset, column in
            LabelIndex.tier(of: column.id, for: p).map { (tier: $0, offset: offset, column: column) }
        }
        return ranked.sorted { ($0.tier, $0.offset) < ($1.tier, $1.offset) }.map(\.column)
    }
}
