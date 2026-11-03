import Foundation

/// A section of the Issues All list, declared in display order. Raw values are the fold keys in
/// `settings.sectionFolds`, so none may equal a `PRSection`'s.
public enum IssueSection: String, CaseIterable, Sendable {
    case assignedToYou, youOpened, restOfBoard
    case otherResults = "issueOtherResults"
    case doneStillOpen = "issueDoneStillOpen"

    public var title: String {
        switch self {
        case .assignedToYou: "Assigned to you"
        case .youOpened: "You opened"
        case .restOfBoard: "Rest of the board"
        case .otherResults: "Other results"
        case .doneStillOpen: "Done"
        }
    }

    /// The fetched list whose row rules (avatars, `past`) apply to this section's rows.
    public var rowTab: IssueTab {
        switch self {
        case .assignedToYou: .assigned
        case .youOpened: .created
        case .restOfBoard, .otherResults, .doneStillOpen: .board
        }
    }
}

/// What a section shows in place of, or beside, its rows.
public enum IssueSectionState: Equatable, Sendable {
    case rows
    /// The list has not loaded yet.
    case loading
    /// The latest search failed and nothing was kept.
    case failed(String)
    /// The latest search failed; the rows are the last good list, fetched at `since`.
    case stale(String, since: Date?)
}

public struct IssueListSection: Identifiable, Equatable, Sendable {
    public let section: IssueSection
    public let issues: [BoardIssue]
    public let state: IssueSectionState
    public var id: IssueSection { section }

    public init(section: IssueSection, issues: [BoardIssue], state: IssueSectionState) {
        self.section = section
        self.issues = issues
        self.state = state
    }
}

/// The sections Issues All shows, each issue once.
public struct IssueList: Equatable, Sendable {
    public let sections: [IssueListSection]
    /// The shown Status of each listed issue that has one, for the row chip.
    public let status: [PRKey: BoardStatusValue]
    /// Assigned is loaded without error and holds nothing for All, while other sections have rows.
    public let nothingAssigned: Bool
    /// No sections, with Assigned and Created both loaded without error: the all-empty copy shows.
    public let isEmpty: Bool

    public var rowCount: Int { sections.reduce(0) { $0 + $1.issues.count } }

    init(sections: [IssueListSection], status: [PRKey: BoardStatusValue], nothingAssigned: Bool, isEmpty: Bool) {
        self.sections = sections
        self.status = status
        self.nothingAssigned = nothingAssigned
        self.isEmpty = isEmpty
    }

    /// The keys whose board copy is done; empty unless the board is readable.
    public static func doneKeys(in snap: Snapshot) -> Set<PRKey> {
        guard snap.boardStatus == .available else { return [] }
        return Set(snap.boardIssues.filter(IssueTabBuilder.isDone).map(\.key))
    }

    /// Each issue's shown Status, read from its board copy; nil without one.
    static func shownStatus(in snap: Snapshot) -> (BoardIssue) -> BoardStatusValue? {
        var copies: [PRKey: BoardIssue] = [:]
        for item in snap.boardIssues where copies[item.key] == nil { copies[item.key] = item }
        return { issue in copies[issue.key].flatMap { IssueTabBuilder.shownStatus($0.status, in: snap) } }
    }

    /// All's order for a list of issues under `sort`, Board status included.
    static func ordering(_ sort: ListSort, snap: Snapshot) -> ([BoardIssue]) -> [BoardIssue] {
        let shown = shownStatus(in: snap)
        let options = snap.boardStatusOptions ?? []
        return { issues in
            sort == .boardStatus
                ? statusSorted(issues, options: options, shown: shown)
                : IssueTabBuilder.sorted(issues, by: sort)
        }
    }

    public static func build(_ tabs: BuiltIssueTabs, snap: Snapshot, settings: AppSettings) -> IssueList {
        let done = doneKeys(in: snap)
        let sort = settings.sort(for: .all, boardAvailable: tabs.board != nil)
        let shown = shownStatus(in: snap)
        let ordered = ordering(sort, snap: snap)

        var seen = done
        var sections: [IssueListSection] = []
        func add(_ section: IssueSection, _ issues: [BoardIssue], loaded: Bool, error: String?, since: Date?) {
            let kept = issues.filter { seen.insert($0.key).inserted }
            let state: IssueSectionState
            if !loaded {
                state = .loading
            } else if let error {
                state = issues.isEmpty ? .failed(error) : .stale(error, since: since)
            } else {
                state = .rows
            }
            if kept.isEmpty, state == .rows || state.isStale { return }
            sections.append(IssueListSection(section: section, issues: ordered(kept), state: state))
        }

        let assigned = tabs.assigned.groups.filter { $0.kind != .done }.flatMap(\.issues)
        add(.assignedToYou, assigned, loaded: tabs.assignedLoaded, error: tabs.assignedError, since: tabs.assignedFetchedAt)
        add(.youOpened, tabs.created.issues, loaded: tabs.createdLoaded, error: tabs.createdError, since: tabs.createdFetchedAt)
        if let board = tabs.board {
            add(.restOfBoard, board.groups.filter { $0.kind != .done }.flatMap(\.issues), loaded: true, error: nil, since: nil)
        }

        var status: [PRKey: BoardStatusValue] = [:]
        for issue in sections.flatMap(\.issues) { status[issue.key] = shown(issue) }

        let assignedClean = tabs.assignedLoaded && tabs.assignedError == nil
        let createdClean = tabs.createdLoaded && tabs.createdError == nil
        let hasAssigned = sections.contains { $0.section == .assignedToYou }
        return IssueList(
            sections: sections, status: status,
            nothingAssigned: assignedClean && !hasAssigned && !sections.isEmpty,
            isEmpty: sections.isEmpty && assignedClean && createdClean)
    }

    /// By the index of the shown Status in the board's columns, issues without one after the rest, then
    /// newest update, repo and number.
    private static func statusSorted(
        _ issues: [BoardIssue], options: [StatusOption], shown: (BoardIssue) -> BoardStatusValue?
    ) -> [BoardIssue] {
        func index(_ issue: BoardIssue) -> Int {
            shown(issue).flatMap { value in options.firstIndex { $0.id == value.optionId } } ?? Int.max
        }
        let byUpdate = IssueTabBuilder.sorted(issues, by: .recentlyUpdated)
        let rank = Dictionary(uniqueKeysWithValues: byUpdate.enumerated().map { ($1.key, $0) })
        return issues.sorted { a, b in
            let (x, y) = (index(a), index(b))
            return x != y ? x < y : rank[a.key]! < rank[b.key]!
        }
    }
}

private extension IssueSectionState {
    var isStale: Bool {
        if case .stale = self { return true }
        return false
    }
}

extension BuiltIssueTabs {
    /// The chip's count; nil for All.
    public func count(of scope: IssueScope) -> IssueTabCount? {
        scope.tab.map(count)
    }

    /// Assigned and Created, in that order, whose latest search failed with a list kept.
    public var staleTabs: [IssueTab] {
        [IssueTab.assigned, .created].filter {
            if case .stale = count($0) { return true }
            return false
        }
    }
}

public struct ScopedIssueList: Equatable, Sendable {
    public let list: IssueList
    /// Every issue the focus hides.
    public let hiddenCount: Int

    public init(unscoped list: IssueList) {
        self.list = list
        hiddenCount = 0
    }

    init(list: IssueList, hiddenCount: Int) {
        self.list = list
        self.hiddenCount = hiddenCount
    }
}
