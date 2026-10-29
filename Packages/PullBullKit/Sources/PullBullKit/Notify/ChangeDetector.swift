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
}

public struct IssueEvent: Equatable, Sendable {
    public let kind: IssueEventKind
    public let issue: BoardIssue
    public let actor: String?
    /// For `comment`: how many arrived since the previous poll.
    public let count: Int

    public init(kind: IssueEventKind, issue: BoardIssue, actor: String?, count: Int = 1) {
        self.kind = kind
        self.issue = issue
        self.actor = actor
        self.count = count
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
