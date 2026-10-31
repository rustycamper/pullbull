import Foundation

public struct Snapshot: Codable, Sendable, Equatable {
    public var fetchedAt: Date
    public var org: OrgContext
    public var reviewCandidates: [PullRequest]
    public var mine: [PullRequest]
    public var team: [PullRequest]
    public var recentlyClosed: [PullRequest]
    public var boardIssues: [BoardIssue]
    /// The project number `boardIssues` belong to; nil when no board was fetched (none chosen, no
    /// project scope) and in snapshots cached before it was stored.
    public var boardProject: Int?
    /// Who owns board `boardProject`; nil in snapshots cached before personal boards, whose board
    /// was the snapshot org's (see `board`).
    public var boardOwner: BoardOwner?
    public var boardTitle: String?
    /// Why the last board fetch failed; `boardIssues` then holds the previous items of the same board.
    public var boardError: String?
    /// Open org issues assigned to the viewer; nil when never fetched (also every pre-Issues cache).
    public var assignedIssues: [BoardIssue]?
    /// Open org issues the viewer opened; nil when never fetched.
    public var createdIssues: [BoardIssue]?
    /// The board's Status options in board order; nil when never fetched, empty when it has no Status field.
    public var boardStatusOptions: [StatusOption]?
    /// Why the last Assigned search failed or came back incomplete; `assignedIssues` then holds the
    /// previous snapshot's list (nil when there was none). It never fails the poll. Nil in caches from
    /// before it was stored per list.
    public var assignedIssuesError: String?
    /// The same for the Created search and `createdIssues`.
    public var createdIssuesError: String?
    /// When the Assigned search that produced `assignedIssues` ran; a failed search carries it
    /// forward with the list. Nil when never fetched and in caches from before it was stored.
    public var assignedIssuesFetchedAt: Date?
    /// The same for the Created search and `createdIssues`.
    public var createdIssuesFetchedAt: Date?
    /// Issues that left Assigned or Created since the previous snapshot because they were closed, each
    /// with who closed it; nil when not looked up (no previous snapshot of this org) and in caches from
    /// before it was stored.
    public var closedIssues: [BoardIssue]?
    /// Issues that left Assigned or Created whose lookup failed or didn't fit this poll, as last
    /// listed; the next poll looks them up again. Nil when there are none.
    public var pendingClosedLookups: [BoardIssue]?
    /// The node IDs board mutations take for `boardProject`; nil without a board, when the board query
    /// returned none, and in caches from before they were stored.
    public var boardIds: BoardIds?

    public init(
        fetchedAt: Date, org: OrgContext, reviewCandidates: [PullRequest], mine: [PullRequest],
        team: [PullRequest], recentlyClosed: [PullRequest], boardIssues: [BoardIssue],
        boardProject: Int? = nil, boardTitle: String? = nil, boardError: String? = nil,
        assignedIssues: [BoardIssue]? = nil, createdIssues: [BoardIssue]? = nil,
        boardStatusOptions: [StatusOption]? = nil, assignedIssuesError: String? = nil,
        createdIssuesError: String? = nil, assignedIssuesFetchedAt: Date? = nil,
        createdIssuesFetchedAt: Date? = nil, boardOwner: BoardOwner? = nil, closedIssues: [BoardIssue]? = nil,
        pendingClosedLookups: [BoardIssue]? = nil, boardIds: BoardIds? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.org = org
        self.reviewCandidates = reviewCandidates
        self.mine = mine
        self.team = team
        self.recentlyClosed = recentlyClosed
        self.boardIssues = boardIssues
        self.boardProject = boardProject
        self.boardOwner = boardOwner
        self.boardTitle = boardTitle
        self.boardError = boardError
        self.assignedIssues = assignedIssues
        self.createdIssues = createdIssues
        self.boardStatusOptions = boardStatusOptions
        self.assignedIssuesError = assignedIssuesError
        self.createdIssuesError = createdIssuesError
        self.assignedIssuesFetchedAt = assignedIssuesFetchedAt
        self.createdIssuesFetchedAt = createdIssuesFetchedAt
        self.closedIssues = closedIssues
        self.pendingClosedLookups = pendingClosedLookups
        self.boardIds = boardIds
    }

    /// Why the Assigned or Created list on screen did not update; nil for Board, which has `boardError`.
    public func issuesError(for tab: IssueTab) -> String? {
        switch tab {
        case .assigned: assignedIssuesError
        case .created: createdIssuesError
        case .board: nil
        }
    }

    /// When the Assigned or Created list on screen was fetched; nil for Board.
    public func issuesFetchedAt(for tab: IssueTab) -> Date? {
        switch tab {
        case .assigned: assignedIssuesFetchedAt
        case .created: createdIssuesFetchedAt
        case .board: nil
        }
    }

    /// The org this snapshot is of, or the personal scope.
    public var scope: FetchScope { org.scope }

    /// This snapshot with only the items `scope` covers (see `FetchScope.covers`), on every list, and
    /// its context limited to the scope's repositories. An org snapshot is unchanged.
    public func limited(to scope: FetchScope) -> Snapshot {
        guard scope.org == nil else { return self }
        var snapshot = self
        snapshot.org = org.limited(to: scope)
        let prs = { (list: [PullRequest]) in list.filter { scope.covers($0.key.repo) } }
        let issues = { (list: [BoardIssue]) in list.filter { scope.covers($0.key.repo) } }
        snapshot.reviewCandidates = prs(reviewCandidates)
        snapshot.mine = prs(mine)
        snapshot.team = prs(team)
        snapshot.recentlyClosed = prs(recentlyClosed)
        snapshot.boardIssues = issues(boardIssues)
        snapshot.assignedIssues = assignedIssues.map(issues)
        snapshot.createdIssues = createdIssues.map(issues)
        snapshot.closedIssues = closedIssues.map(issues)
        snapshot.pendingClosedLookups = pendingClosedLookups.map(issues)
        return snapshot
    }

    /// This snapshot with each of `followed` that is still open replacing the pull request of the same key in
    /// Mine, Review and Team. A merged or closed one keeps its old row until the next full refresh, since Mine
    /// lists open PRs only and the row would vanish. Keys it doesn't hold are ignored; `fetchedAt` and every
    /// other list are unchanged.
    public func merging(followed: [PullRequest]) -> Snapshot {
        let open = followed.filter { $0.state == .open }
        guard !open.isEmpty else { return self }
        let byKey = Dictionary(open.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let replace = { (list: [PullRequest]) in list.map { byKey[$0.key] ?? $0 } }
        var snapshot = self
        snapshot.mine = replace(mine)
        snapshot.reviewCandidates = replace(reviewCandidates)
        snapshot.team = replace(team)
        return snapshot
    }

    /// The board `boardIssues` belong to. A snapshot cached before the owner was stored had an org's
    /// board; a personal one had none, so its number is never read as a personal board.
    public var board: BoardRef? {
        guard let boardProject else { return nil }
        if let boardOwner { return BoardRef(owner: boardOwner, number: boardProject) }
        return org.isPersonal ? nil : .org(org.org, boardProject)
    }

    public var boardStatus: BoardStatus {
        if let boardError { return .unavailable(boardError) }
        if boardProject == nil && boardIssues.isEmpty { return .none }
        return .available
    }
}

/// Whether search can say a board issue does not exist.
public enum BoardStatus: Equatable, Sendable {
    /// The board's items were fetched.
    case available
    /// The board fetch failed for this reason.
    case unavailable(String)
    /// No board is chosen or readable, so there are no board issues to search.
    case none
}

public struct Row: Identifiable, Sendable {
    public let pr: PullRequest
    public let dimmed: Bool
    public let counted: Bool
    /// On Review, why the PR needs my review; nil on other tabs and for PRs I already approved.
    public let reviewReason: ReviewReason?
    public var id: PRKey { pr.key }

    public init(pr: PullRequest, dimmed: Bool, counted: Bool, reviewReason: ReviewReason? = nil) {
        self.pr = pr
        self.dimmed = dimmed
        self.counted = counted
        self.reviewReason = reviewReason
    }
}

public struct TabContents: Sendable {
    public let rows: [Row]
    public var count: Int { rows.filter(\.counted).count }

    public init(rows: [Row]) { self.rows = rows }
}

public struct BuiltTabs: Sendable {
    public let review: TabContents
    public let mine: TabContents
    public let team: TabContents
    public let recentlyClosed: [PullRequest]
    /// Review PRs left out because "hide PRs I've approved" is on.
    public let hiddenApprovedCount: Int

    public func badgeCount(_ source: BadgeSource) -> Int {
        let tabs: [TabContents]
        switch source {
        case .review: tabs = [review]
        case .mine: tabs = [mine]
        case .reviewAndMine: tabs = [review, mine]
        case .all: tabs = [review, mine, team]
        }
        var keys = Set<PRKey>()
        for tab in tabs {
            for row in tab.rows where row.counted { keys.insert(row.id) }
        }
        return keys.count
    }
}

/// The Review and Team filters from Settings (Mine is never filtered). Open PRs only: the search
/// index can lag a merge or close, but each node's state is live.
public struct ReviewFilters: Equatable, Sendable {
    public var hideDrafts: Bool
    public var hideOlderThanTwoMonths: Bool

    /// Keeps every open PR.
    public static let none = ReviewFilters(hideDrafts: false, hideOlderThanTwoMonths: false)

    public init(hideDrafts: Bool, hideOlderThanTwoMonths: Bool) {
        self.hideDrafts = hideDrafts
        self.hideOlderThanTwoMonths = hideOlderThanTwoMonths
    }

    public init(_ settings: AppSettings) {
        self.init(hideDrafts: settings.hideDrafts, hideOlderThanTwoMonths: settings.hideOlderThanTwoMonths)
    }

    public func keeps(_ pr: PullRequest, now: Date) -> Bool {
        guard pr.state == .open else { return false }
        if hideDrafts && pr.isDraft { return false }
        if hideOlderThanTwoMonths && pr.updatedAt < now.addingTimeInterval(-60 * 86_400) { return false }
        return true
    }
}

public enum TabBuilder {
    private static let day: TimeInterval = 86_400

    public static func build(_ snap: Snapshot, settings: AppSettings, now: Date) -> BuiltTabs {
        let me = snap.org.viewer
        let myTeams = snap.org.myTeams
        let filters = ReviewFilters(settings)

        var hiddenApproved = Set<PRKey>()
        let review: [Row] = snap.reviewCandidates.filter { filters.keeps($0, now: now) }.compactMap { pr in
            switch ReviewRules.status(of: pr, me: me, myTeams: myTeams) {
            case .needsReview: break
            case .approvedByMe:
                if settings.hideApprovedByMe {
                    hiddenApproved.insert(pr.key)
                    return nil
                }
            case .reviewedByMe, .notRequested: return nil
            }
            return row(for: pr, on: .review, me: me, myTeams: myTeams)
        }
        let mine = snap.mine.filter { $0.state == .open }.map { Row(pr: $0, dimmed: false, counted: true) }
        let team = snap.team
            .filter { pr in
                pr.author.caseInsensitiveCompare(me) != .orderedSame && filters.keeps(pr, now: now)
            }
            .map { Row(pr: $0, dimmed: false, counted: true) }

        let closedCutoff = now.addingTimeInterval(-7 * day)
        let closed = snap.recentlyClosed
            .filter { ($0.closedAt ?? .distantPast) >= closedCutoff }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }

        return BuiltTabs(
            review: contents(review, oldestFirst: settings.reviewOldestFirst), mine: contents(mine), team: contents(team),
            recentlyClosed: closed, hiddenApprovedCount: hiddenApproved.count
        )
    }

    /// `pr` as `tab` shows it. On Review: counted, with its reason, while it needs my review; dimmed and
    /// not counted once I approved it; neither when I reviewed it or wasn't asked. On Mine and Team: counted.
    public static func row(for pr: PullRequest, on tab: PRTab, me: String, myTeams: Set<String>) -> Row {
        guard tab == .review else { return Row(pr: pr, dimmed: false, counted: true) }
        switch ReviewRules.status(of: pr, me: me, myTeams: myTeams) {
        case .needsReview(let reason): return Row(pr: pr, dimmed: false, counted: true, reviewReason: reason)
        case .approvedByMe: return Row(pr: pr, dimmed: true, counted: false)
        case .reviewedByMe, .notRequested: return Row(pr: pr, dimmed: false, counted: false)
        }
    }

    /// Rows by latest activity, or with `oldestFirst` by when the PR was opened, the oldest first.
    static func contents(_ rows: [Row], oldestFirst: Bool = false) -> TabContents {
        var seen = Set<PRKey>()
        let sorted = rows.sorted {
            if oldestFirst {
                if $0.pr.createdAt != $1.pr.createdAt { return $0.pr.createdAt < $1.pr.createdAt }
            } else if $0.pr.updatedAt != $1.pr.updatedAt {
                return $0.pr.updatedAt > $1.pr.updatedAt
            }
            if $0.id.repo != $1.id.repo { return $0.id.repo < $1.id.repo }
            return $0.id.number < $1.id.number
        }
        return TabContents(rows: sorted.filter { seen.insert($0.id).inserted })
    }
}
