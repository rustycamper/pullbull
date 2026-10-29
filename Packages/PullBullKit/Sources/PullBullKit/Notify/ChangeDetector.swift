import Foundation

public enum PREventKind: String, Sendable, CaseIterable {
    case reviewRequested, approved, changesRequested, ciFailed, newComment, readyToMerge, merged
    /// Someone else commented on a PR I reviewed.
    case commentAfterMyReview
}

public struct PREvent: Equatable, Sendable {
    public let kind: PREventKind
    public let pr: PullRequest
    public let actor: String?

    public init(kind: PREventKind, pr: PullRequest, actor: String?) {
        self.kind = kind
        self.pr = pr
        self.actor = actor
    }
}

public enum IssueEventKind: String, Sendable, CaseIterable {
    case assigned
    /// New comments on an issue assigned to me or that I created.
    case comment
    /// The issue's card moved to another Status on the board.
    case statusChanged
    case closed
    case reopened
}

public struct IssueEvent: Equatable, Sendable {
    public let kind: IssueEventKind
    public let issue: BoardIssue
    public let actor: String?
    /// For `comment`: how many arrived since the previous poll.
    public let count: Int
    /// For `statusChanged`: the move.
    public let move: StatusMove?

    public init(kind: IssueEventKind, issue: BoardIssue, actor: String?, count: Int = 1, move: StatusMove? = nil) {
        self.kind = kind
        self.issue = issue
        self.actor = actor
        self.count = count
        self.move = move
    }
}

public enum ChangeDetector {
    /// `filters` are the Review tab's: a review request on a PR the tab hides doesn't notify.
    public static func events(
        old: Snapshot?, new: Snapshot, me: String, myTeams: Set<String>, toggles: NotificationToggles,
        filters: ReviewFilters = .none, now: Date = Date()
    ) -> [PREvent] {
        guard let old else { return [] }
        var result: [PREvent] = []

        if toggles.reviewRequested {
            let before = Dictionary(old.reviewCandidates.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            for pr in new.reviewCandidates
            where filters.keeps(pr, now: now) && ReviewRules.status(of: pr, me: me, myTeams: myTeams).reviewReason != nil {
                if let prev = before[pr.key],
                    ReviewRules.status(of: prev, me: me, myTeams: myTeams).reviewReason != nil
                {
                    continue
                }
                result.append(PREvent(kind: .reviewRequested, pr: pr, actor: pr.author))
            }
        }

        let oldMine = Dictionary(old.mine.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for pr in new.mine where same(pr.author, me) {
            guard let prev = oldMine[pr.key] else { continue }

            for review in pr.latestReviews where !same(review.author, me) && !prev.latestReviews.contains(review) {
                if review.state == .approved, toggles.approved {
                    result.append(PREvent(kind: .approved, pr: pr, actor: review.author))
                } else if review.state == .changesRequested, toggles.changesRequested {
                    result.append(PREvent(kind: .changesRequested, pr: pr, actor: review.author))
                }
            }
            if toggles.ciFailed, pr.ci == .failure, prev.ci != .failure {
                result.append(PREvent(kind: .ciFailed, pr: pr, actor: nil))
            }
            if toggles.newComment, pr.commentCount > prev.commentCount,
                !same(pr.lastCommentAuthor ?? "", me)
            {
                result.append(PREvent(kind: .newComment, pr: pr, actor: pr.lastCommentAuthor))
            }
            if toggles.readyToMerge, settledReady(pr, prev: prev), !ReviewRules.isReadyToMerge(prev) {
                result.append(PREvent(kind: .readyToMerge, pr: pr, actor: nil))
            }
        }

        // Others' PRs I reviewed: a comment after my review (a reply, a question) is for me.
        if toggles.commentAfterMyReview {
            let before = Dictionary(old.reviewCandidates.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            var seen = Set<PRKey>()
            for pr in new.reviewCandidates
            where !same(pr.author, me)
                && pr.latestReviews.contains(where: { same($0.author, me) && $0.state != .pending })
                && seen.insert(pr.key).inserted
            {
                guard let prev = before[pr.key], pr.commentCount > prev.commentCount,
                      !same(pr.lastCommentAuthor ?? "", me)
                else { continue }
                result.append(PREvent(kind: .commentAfterMyReview, pr: pr, actor: pr.lastCommentAuthor))
            }
        }

        if toggles.merged {
            result += mergedEvents(old: old, new: new, me: me)
        }

        let order = Dictionary(uniqueKeysWithValues: PREventKind.allCases.enumerated().map { ($1, $0) })
        return result.sorted {
            if $0.kind != $1.kind { return order[$0.kind]! < order[$1.kind]! }
            if $0.pr.key.repo != $1.pr.key.repo { return $0.pr.key.repo < $1.pr.key.repo }
            if $0.pr.key.number != $1.pr.key.number { return $0.pr.key.number < $1.pr.key.number }
            return ($0.actor ?? "") < ($1.actor ?? "")
        }
    }

    /// Ready to merge, and not only on the way somewhere else: GitHub has finished computing
    /// mergeability (an UNKNOWN after a push may still turn out CONFLICTING), and no checks means none
    /// were ever set up rather than a new head commit's checks that haven't started.
    private static func settledReady(_ pr: PullRequest, prev: PullRequest) -> Bool {
        ReviewRules.isReadyToMerge(pr) && pr.mergeable != .unknown && (pr.ci != .none || prev.ci == .none)
    }

    /// How far before the previous poll a merge may be and still count as new when that poll never
    /// listed the PR as open: the open search can drop a PR a poll before the closed search returns it.
    public static let mergeLag: TimeInterval = 600

    /// My PRs someone else merged since the previous poll: open in it (or merged within `mergeLag`
    /// of it when it listed the PR nowhere) and not yet among its recently closed. Silent for a merge
    /// of my own, and for older merges a closed search or a wider scope brings back.
    private static func mergedEvents(old: Snapshot, new: Snapshot, me: String) -> [PREvent] {
        let wasOpen = Set(old.mine.map(\.key))
        let wasClosed = Set(old.recentlyClosed.map(\.key))
        let since = old.fetchedAt.addingTimeInterval(-mergeLag)
        var seen = Set<PRKey>()
        var result: [PREvent] = []
        for pr in new.recentlyClosed
        where pr.state == .merged && same(pr.author, me) && !wasClosed.contains(pr.key)
            && seen.insert(pr.key).inserted
        {
            guard wasOpen.contains(pr.key) || (pr.closedAt ?? .distantPast) >= since else { continue }
            if let by = pr.mergedBy, same(by, me) { continue }
            result.append(PREvent(kind: .merged, pr: pr, actor: pr.mergedBy))
        }
        return result
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// How far before the previous Assigned fetch an assignment may be and still count as new: the issue
    /// search can return a fresh assignment a poll or two late.
    public static let assignmentLag: TimeInterval = 600

    /// The issue events between two polls: new assignments, then new comments.
    public static func issueEvents(
        old: Snapshot?, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        guard let old else { return [] }
        let events = assignedEvents(old: old, new: new, me: me, toggles: toggles)
            + commentEvents(old: old, new: new, me: me, toggles: toggles)
            + statusEvents(old: old, new: new, me: me, toggles: toggles)
            + closedEvents(old: old, new: new, me: me, toggles: toggles)
            + reopenedEvents(old: old, new: new, me: me, toggles: toggles)
        let order = Dictionary(uniqueKeysWithValues: IssueEventKind.allCases.enumerated().map { ($1, $0) })
        return events.sorted {
            if $0.kind != $1.kind { return order[$0.kind]! < order[$1.kind]! }
            if $0.issue.key.repo != $1.issue.key.repo { return $0.issue.key.repo < $1.issue.key.repo }
            return $0.issue.key.number < $1.issue.key.number
        }
    }

    /// New comments by someone else on open issues assigned to me or that I created, one event per issue
    /// with the count. Only issues both polls listed: a newly listed issue's comments aren't news (its
    /// assignment is), and only when the previous poll's search succeeded: a failed one carries an older
    /// list forward (at launch, the cached one), whose counts would turn every comment since into news.
    /// An issue both assigned to me and mine notifies once, when either toggle is on.
    private static func commentEvents(
        old: Snapshot, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        var lists: [(before: [BoardIssue]?, now: [BoardIssue]?)] = []
        if toggles.assignedIssueComment, old.assignedIssuesError == nil {
            lists.append((old.assignedIssues, new.assignedIssues))
        }
        if toggles.createdIssueComment, old.createdIssuesError == nil {
            lists.append((old.createdIssues, new.createdIssues))
        }
        var seen = Set<PRKey>()
        var result: [IssueEvent] = []
        for (before, now) in lists {
            guard let before, let now else { continue }
            let previous = Dictionary(before.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            for issue in now where issue.isOpen {
                guard let prev = previous[issue.key], issue.commentCount > prev.commentCount,
                      !same(issue.lastCommentAuthor ?? "", me), seen.insert(issue.key).inserted
                else { continue }
                result.append(IssueEvent(
                    kind: .comment, issue: issue, actor: issue.lastCommentAuthor,
                    count: issue.commentCount - prev.commentCount))
            }
        }
        return result
    }

    /// The Assigned and Created lists whose `on` toggle is set, each before and now, with the time
    /// the previous one was fetched (a failed search carries it forward with its list).
    private static func lists(
        old: Snapshot, new: Snapshot, assigned: Bool, created: Bool
    ) -> [(before: [BoardIssue], now: [BoardIssue], since: Date)] {
        var result: [(before: [BoardIssue], now: [BoardIssue], since: Date)] = []
        if assigned, let before = old.assignedIssues, let now = new.assignedIssues {
            result.append((before, now, (old.assignedIssuesFetchedAt ?? old.fetchedAt).addingTimeInterval(-assignmentLag)))
        }
        if created, let before = old.createdIssues, let now = new.createdIssues {
            result.append((before, now, (old.createdIssuesFetchedAt ?? old.fetchedAt).addingTimeInterval(-assignmentLag)))
        }
        return result
    }

    /// Someone other than me, and not automation, moved the card of an open issue assigned to me or
    /// that I created to another Status on the board PullBull shows, since the previous poll. One
    /// event per issue, for its latest move there. Silent without a board, for a card just added to
    /// it, for an issue the previous poll didn't list, and for a move the previous poll already had.
    private static func statusEvents(
        old: Snapshot, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        guard let project = new.boardProject else { return [] }
        let owner = new.boardOwner?.login ?? new.org.org
        let latest = { (issue: BoardIssue) in issue.statusMoves.last { $0.isOn(project: project, owner: owner) } }
        var seen = Set<PRKey>()
        var result: [IssueEvent] = []
        for (before, now, since) in lists(
            old: old, new: new, assigned: toggles.assignedIssueStatus, created: toggles.createdIssueStatus)
        {
            let previous = Dictionary(before.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            for issue in now where issue.isOpen {
                guard let prev = previous[issue.key], let move = latest(issue),
                      move.from != nil, move.to != nil, move.at >= since, latest(prev) != move,
                      !isAutomation(move.actor), !same(move.actor ?? "", me), seen.insert(issue.key).inserted
                else { continue }
                result.append(IssueEvent(kind: .statusChanged, issue: issue, actor: move.actor, move: move))
            }
        }
        return result
    }

    /// Issues assigned to me or that I created which someone else closed since the previous poll (the
    /// snapshot's `closedIssues`, looked up when they left the lists).
    private static func closedEvents(
        old: Snapshot, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        let assigned = toggles.assignedIssueClosed ? Set((old.assignedIssues ?? []).map(\.key)) : []
        let created = toggles.createdIssueClosed ? Set((old.createdIssues ?? []).map(\.key)) : []
        var seen = Set<PRKey>()
        var result: [IssueEvent] = []
        for issue in new.closedIssues ?? []
        where (assigned.contains(issue.key) || created.contains(issue.key)) && seen.insert(issue.key).inserted {
            let actor = issue.lastClose?.actor
            if let actor, same(actor, me) { continue }
            result.append(IssueEvent(kind: .closed, issue: issue, actor: actor))
        }
        return result
    }

    /// Issues assigned to me or that I created which someone else reopened since the previous poll:
    /// back in the list with a reopening after the previous fetch.
    private static func reopenedEvents(
        old: Snapshot, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        var seen = Set<PRKey>()
        var result: [IssueEvent] = []
        for (before, now, since) in lists(
            old: old, new: new, assigned: toggles.assignedIssueClosed, created: toggles.createdIssueClosed)
        {
            let known = Set(before.map(\.key))
            for issue in now where issue.isOpen && !known.contains(issue.key) {
                guard let reopen = issue.lastReopen, reopen.at >= since, !same(reopen.actor ?? "", me),
                      seen.insert(issue.key).inserted
                else { continue }
                result.append(IssueEvent(kind: .reopened, issue: issue, actor: reopen.actor))
            }
        }
        return result
    }

    /// A board's own workflows (`github-project-automation`) and apps: their moves follow a close or
    /// a merge that notifies on its own.
    private static func isAutomation(_ actor: String?) -> Bool {
        guard let actor else { return false }
        return same(actor, "github-project-automation") || actor.hasSuffix("[bot]")
    }

    /// Issues someone else newly assigned to `me`. Silent when the previous snapshot never fetched
    /// assigned issues (first load, or a cache from before the Issues mode), when the assignment
    /// event is unknown, for old assignments that reappear (reopened or transferred issues), and for
    /// closed issues a lagging search still returns, which the Assigned list drops too.
    private static func assignedEvents(
        old: Snapshot, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        guard toggles.issueAssigned, let before = old.assignedIssues, let now = new.assignedIssues
        else { return [] }
        let known = Set(before.map(\.key))
        // A failed Assigned search carries the list forward under a newer `fetchedAt`; measure from
        // the search that produced it, so assignments made during an outage still count.
        let since = (old.assignedIssuesFetchedAt ?? old.fetchedAt).addingTimeInterval(-assignmentLag)
        var seen = Set<PRKey>()
        var result: [IssueEvent] = []
        for issue in now where issue.isOpen && !known.contains(issue.key) && seen.insert(issue.key).inserted {
            guard let assignment = issue.myAssignment, assignment.at >= since else { continue }
            if let actor = assignment.actor, same(actor, me) { continue }
            result.append(IssueEvent(kind: .assigned, issue: issue, actor: assignment.actor))
        }
        return result
    }
}
