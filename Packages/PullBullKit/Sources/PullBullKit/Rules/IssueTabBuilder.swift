import Foundation

public enum IssueGroupKind: Hashable, Sendable {
    /// A board Status column.
    case status(StatusOption)
    /// On the board, with no Status or one whose option no longer exists.
    case noStatus
    /// Assigned issues that are not on the board.
    case notOnBoard
    /// Issues of one repository (`owner/name`).
    case repo(String)
    /// The whole list, ungrouped.
    case all
    /// The folded Done group, never counted: on Board the last 14 days of done items, on Assigned the
    /// issues still open in the board's Done column.
    case done
}

public struct IssueGroup: Identifiable, Equatable, Sendable {
    public let kind: IssueGroupKind
    public let issues: [BoardIssue]
    public let counted: Bool
    public var id: IssueGroupKind { kind }

    public var title: String {
        switch kind {
        case .status(let option): return option.name
        case .noStatus: return "No status"
        case .notOnBoard: return "Not on board"
        case .repo(let repo): return repo.split(separator: "/").last.map(String.init) ?? repo
        case .all: return ""
        case .done: return "Done"
        }
    }

    public init(kind: IssueGroupKind, issues: [BoardIssue], counted: Bool) {
        self.kind = kind
        self.issues = issues
        self.counted = counted
    }
}

public struct IssueTabContents: Equatable, Sendable {
    public let groups: [IssueGroup]
    /// The issues in counted groups; the folded Done group is never counted.
    public var count: Int { groups.filter(\.counted).reduce(0) { $0 + $1.issues.count } }
    /// Every listed issue, in display order.
    public var issues: [BoardIssue] { groups.flatMap(\.issues) }

    public init(groups: [IssueGroup]) { self.groups = groups }
}

public struct BuiltIssueTabs: Sendable {
    /// Empty when never fetched; see `assignedLoaded`.
    public let assigned: IssueTabContents
    /// Empty when never fetched; see `createdLoaded`.
    public let created: IssueTabContents
    /// Nil when the board is not available (none chosen, or its last fetch failed).
    public let board: IssueTabContents?
    /// The board is available and has Status options, so Assigned and Board group by Status.
    public let statusKnown: Bool
    /// The Assigned search has succeeded at least once for this account and org; until then
    /// `assigned` is empty without meaning there are no assigned issues.
    public let assignedLoaded: Bool
    /// The same for Created.
    public let createdLoaded: Bool
    /// Why the latest Assigned search failed; `assigned` is then the last good list, if any.
    public let assignedError: String?
    /// The same for Created.
    public let createdError: String?
    /// When the Assigned list was fetched (for a failed search, the last good one).
    public let assignedFetchedAt: Date?
    /// The same for Created.
    public let createdFetchedAt: Date?

    public init(
        assigned: IssueTabContents, created: IssueTabContents, board: IssueTabContents?, statusKnown: Bool,
        assignedLoaded: Bool = true, createdLoaded: Bool = true,
        assignedError: String? = nil, createdError: String? = nil,
        assignedFetchedAt: Date? = nil, createdFetchedAt: Date? = nil
    ) {
        self.assigned = assigned
        self.created = created
        self.board = board
        self.statusKnown = statusKnown
        self.assignedLoaded = assignedLoaded
        self.createdLoaded = createdLoaded
        self.assignedError = assignedError
        self.createdError = createdError
        self.assignedFetchedAt = assignedFetchedAt
        self.createdFetchedAt = createdFetchedAt
    }

    /// At most this many Assigned issues have their detail prefetched per refresh.
    public static let prefetchCap = 50

    /// The Assigned issues whose detail is prefetched after a refresh: the counted ones in list
    /// order, at most `prefetchCap`. None while the latest Assigned search failed or never ran.
    public var assignedToPrefetch: [BoardIssue] {
        guard assignedLoaded, assignedError == nil else { return [] }
        return Array(assigned.groups.filter(\.counted).flatMap(\.issues).prefix(Self.prefetchCap))
    }

    public func contents(_ tab: IssueTab) -> IssueTabContents? {
        switch tab {
        case .assigned: return assigned
        case .created: return created
        case .board: return board
        }
    }

    /// Whether the tab's list has loaded, so its count and an empty list are real. Board is always
    /// loaded here: while it can't be read, `board` is nil and the tab shows why.
    public func isLoaded(_ tab: IssueTab) -> Bool {
        switch tab {
        case .assigned: return assignedLoaded
        case .created: return createdLoaded
        case .board: return true
        }
    }

    /// What the tab's count shows. A list is only `.current` when its latest search succeeded: a
    /// failed one shows the last good count as `.stale`, or `.unavailable` when that list has nothing
    /// counted (empty, or only the folded Done group) or was never fetched, so a list that failed to
    /// load never reads "0". Board is `.unavailable`
    /// while it can't be read.
    public func count(_ tab: IssueTab) -> IssueTabCount {
        switch tab {
        case .board:
            return board.map { .current($0.count) } ?? .unavailable
        case .assigned:
            return Self.count(assigned, loaded: assignedLoaded, error: assignedError, since: assignedFetchedAt)
        case .created:
            return Self.count(created, loaded: createdLoaded, error: createdError, since: createdFetchedAt)
        }
    }

    private static func count(
        _ contents: IssueTabContents, loaded: Bool, error: String?, since: Date?
    ) -> IssueTabCount {
        guard loaded else { return .unavailable }
        guard let error else { return .current(contents.count) }
        return contents.count == 0 ? .unavailable : .stale(contents.count, error: error, since: since)
    }
}

/// A tab's count as the tab bar shows it.
public enum IssueTabCount: Equatable, Sendable {
    /// The list's latest fetch succeeded.
    case current(Int)
    /// The latest fetch failed; this is the count of the last good list, fetched at `since`.
    case stale(Int, error: String, since: Date?)
    /// No list to count: never loaded, failed with nothing kept, or the board can't be read. Shown as "–".
    case unavailable

    /// The number to show, nil for `.unavailable`.
    public var value: Int? {
        switch self {
        case .current(let n), .stale(let n, _, _): n
        case .unavailable: nil
        }
    }
}

/// How a tab count is written in the header, and the badge count in the menu bar.
public enum TabCountText {
    /// Counts above 99 read "99+", so the header's segments and the status item keep their width; the lists,
    /// tooltips and accessibility text keep the exact number.
    public static let cap = 99

    public static func header(_ count: Int) -> String {
        count > cap ? "\(cap)+" : "\(count)"
    }
}

public enum IssueTabBuilder {
    /// How far back the Board's Done group reaches.
    public static let doneWindow: TimeInterval = 14 * 86_400

    public static func build(_ snap: Snapshot, settings: AppSettings, now: Date) -> BuiltIssueTabs {
        let boardAvailable = snap.boardStatus == .available
        let options = boardAvailable ? snap.boardStatusOptions ?? [] : []
        let statusKnown = !options.isEmpty
        let boardItems = unique(snap.boardIssues)
        let onBoard = byKey(boardItems)

        let assignedIssues = unique(snap.assignedIssues ?? []).filter(\.isOpen)
        let assigned = groups(
            of: assignedIssues, on: .assigned, onBoard: onBoard, options: options, grouping: settings.grouping)

        let createdIssues = unique(snap.createdIssues ?? []).filter(\.isOpen)
        let created = groups(
            of: createdIssues, on: .created, onBoard: onBoard, options: options, grouping: settings.grouping)

        var board: IssueTabContents?
        if boardAvailable {
            // Every board item is its own board copy, so it takes the lane of its own Status.
            let active = boardItems.filter { !isDone($0) }
            let open = groups(of: active, on: .board, onBoard: onBoard, options: options, grouping: settings.grouping)
            let cutoff = now.addingTimeInterval(-doneWindow)
            let done = boardItems
                .filter { isDone($0) && (doneDate($0) ?? .distantPast) >= cutoff }
                .sorted { a, b in
                    let da = doneDate(a) ?? .distantPast, db = doneDate(b) ?? .distantPast
                    if da != db { return da > db }
                    return tieBreak(a, b)
                }
            board = IssueTabContents(groups: open + group(.done, done, counted: false, sort: false))
        }

        return BuiltIssueTabs(
            assigned: IssueTabContents(groups: assigned), created: IssueTabContents(groups: created),
            board: board, statusKnown: statusKnown,
            assignedLoaded: snap.assignedIssues != nil, createdLoaded: snap.createdIssues != nil,
            assignedError: snap.assignedIssuesError, createdError: snap.createdIssuesError,
            assignedFetchedAt: snap.assignedIssuesFetchedAt, createdFetchedAt: snap.createdIssuesFetchedAt)
    }

    /// Open `issues` grouped as `tab` groups its open items, each lane read from the issue's board copy
    /// in `snap`: on Assigned and Board, the Status lanes, then "Not on board", then the uncounted Done
    /// group of those in the board's Done column, or repo groups when the board has no Status options;
    /// on Created, by `settings.grouping`. Board's 14-day Done is not applied.
    public static func groups(
        of issues: [BoardIssue], on tab: IssueTab, in snap: Snapshot, settings: AppSettings
    ) -> [IssueGroup] {
        let options = snap.boardStatus == .available ? snap.boardStatusOptions ?? [] : []
        return groups(
            of: unique(issues), on: tab, onBoard: byKey(unique(snap.boardIssues)), options: options,
            grouping: settings.grouping)
    }

    /// `groups(of:on:in:settings:)` with the board copies by key and the Status options (empty when the
    /// board is unavailable or has none) already read.
    static func groups(
        of issues: [BoardIssue], on tab: IssueTab, onBoard: [PRKey: BoardIssue], options: [StatusOption],
        grouping: Grouping
    ) -> [IssueGroup] {
        if tab == .created {
            return grouping == .repository ? repoGroups(issues) : group(.all, issues, counted: true)
        }
        guard !options.isEmpty else { return repoGroups(issues) }
        // Still open but done on the board: housekeeping, not work, so folded and not counted, as on Board.
        let doneOnBoard = { (issue: BoardIssue) in onBoard[issue.key].map(isDone) ?? false }
        let active = issues.filter { !doneOnBoard($0) }
        return statusGroups(options: options, skippingDone: true, issues: active) { issue -> BoardStatusValue?? in
            guard let item = onBoard[issue.key] else { return nil }
            return .some(item.status)
        } + group(.notOnBoard, active.filter { onBoard[$0.key] == nil }, counted: true)
            + group(.done, issues.filter(doneOnBoard), counted: false)
    }

    /// The Status the lists group a board item under: its value while the board is available and the
    /// option still exists, else nil (the lists then show it under "No status" or by repo).
    public static func shownStatus(_ value: BoardStatusValue?, in snap: Snapshot) -> BoardStatusValue? {
        guard snap.boardStatus == .available, let value,
              snap.boardStatusOptions?.contains(where: { $0.id == value.optionId }) == true
        else { return nil }
        return value
    }

    /// Closed, or open in a Status column named "Done".
    public static func isDone(_ issue: BoardIssue) -> Bool {
        !issue.isOpen || (issue.status.map { isDoneName($0.name) } ?? false)
    }

    private static func isDoneName(_ name: String) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Done") == .orderedSame
    }

    private static func doneDate(_ issue: BoardIssue) -> Date? { issue.closedAt ?? issue.updatedAt }

    /// Groups by Status in board order, then No status. `status` returns nil for issues that do not
    /// belong in any of these groups, and `.some(nil)` for board items without a Status.
    private static func statusGroups(
        options: [StatusOption], skippingDone: Bool, issues: [BoardIssue],
        status: (BoardIssue) -> BoardStatusValue??
    ) -> [IssueGroup] {
        let known = Set(options.map(\.id))
        var byOption: [String: [BoardIssue]] = [:]
        var noStatus: [BoardIssue] = []
        for issue in issues {
            guard let value = status(issue) else { continue }
            if let value, known.contains(value.optionId) {
                byOption[value.optionId, default: []].append(issue)
            } else {
                noStatus.append(issue)
            }
        }
        let columns = options.filter { !(skippingDone && isDoneName($0.name)) }
        return columns.flatMap { group(.status($0), byOption[$0.id] ?? [], counted: true) }
            + group(.noStatus, noStatus, counted: true)
    }

    /// One group per repository, the repo with the most recently updated issue first.
    private static func repoGroups(_ issues: [BoardIssue]) -> [IssueGroup] {
        let repos = Dictionary(grouping: issues, by: \.key.repo).map { repo, issues in
            (repo: repo, issues: issues, newest: issues.compactMap(\.updatedAt).max() ?? .distantPast)
        }
        return repos
            .sorted { $0.newest != $1.newest ? $0.newest > $1.newest : $0.repo < $1.repo }
            .flatMap { group(.repo($0.repo), $0.issues, counted: true) }
    }

    /// A one-element array, or empty when there are no issues.
    private static func group(
        _ kind: IssueGroupKind, _ issues: [BoardIssue], counted: Bool, sort: Bool = true
    ) -> [IssueGroup] {
        guard !issues.isEmpty else { return [] }
        return [IssueGroup(kind: kind, issues: sort ? sorted(issues) : issues, counted: counted)]
    }

    private static func sorted(_ issues: [BoardIssue]) -> [BoardIssue] {
        issues.sorted { a, b in
            switch (a.updatedAt, b.updatedAt) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return tieBreak(a, b)
            }
        }
    }

    private static func tieBreak(_ a: BoardIssue, _ b: BoardIssue) -> Bool {
        if a.key.repo != b.key.repo { return a.key.repo < b.key.repo }
        return a.key.number < b.key.number
    }

    /// Board items by key, the first of a key kept.
    private static func byKey(_ items: [BoardIssue]) -> [PRKey: BoardIssue] {
        Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func unique(_ issues: [BoardIssue]) -> [BoardIssue] {
        var seen = Set<PRKey>()
        return issues.filter { seen.insert($0.key).inserted }
    }
}

/// The menu bar count.
public enum Badge {
    /// The PR count for the badge setting, plus the Assigned issues count when "Also count assigned
    /// issues" is on: the same count as the Assigned tab, so issues folded under Done are left out.
    /// PRs and issues never share keys, so the sum counts nothing twice.
    public static func count(prs: BuiltTabs, issues: BuiltIssueTabs?, settings: AppSettings) -> Int {
        prs.badgeCount(settings.badge) + (settings.countAssignedIssues ? issues?.assigned.count ?? 0 : 0)
    }

    /// The badge adds an Assigned count that is not current (its latest search failed, or it never
    /// loaded), so the menu bar icon dims as for a failed refresh.
    public static func issuesIncomplete(issues: BuiltIssueTabs?, settings: AppSettings) -> Bool {
        guard settings.countAssignedIssues, let issues else { return false }
        if case .current = issues.count(.assigned) { return false }
        return true
    }
}

/// What an issue row shows.
public enum IssueRowRules {
    public static let maxChips = 2, maxChipLength = 18

    /// The first `maxChips` labels, each cut to `maxChipLength` characters with "…", and how many more
    /// there are.
    public static func chips(_ labels: [String]) -> (shown: [String], more: Int) {
        let shown = labels.prefix(maxChips).map { label in
            label.count > maxChipLength ? String(label.prefix(maxChipLength - 1)) + "…" : label
        }
        return (shown, labels.count - shown.count)
    }

    /// The order a row shows `labels` in, as indices: those a `~label` search asks for first, so they
    /// never drop into "+N", then the rest. Otherwise GitHub's order. Case is ignored.
    public static func chipOrder(_ labels: [String], first wanted: [String]) -> [Int] {
        let isWanted = { (label: String) in
            wanted.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
        }
        let indices = Array(labels.indices)
        return indices.filter { isWanted(labels[$0]) } + indices.filter { !isWanted(labels[$0]) }
    }

    /// The avatars on the right of a row. Assigned leaves out the viewer, who is on every row there.
    public static func avatars(_ issue: BoardIssue, tab: IssueTab, me: String) -> [Assignee] {
        guard tab == .assigned else { return issue.assignees }
        return issue.assignees.filter { $0.login.caseInsensitiveCompare(me) != .orderedSame }
    }
}
