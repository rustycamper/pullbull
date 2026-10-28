import Foundation

public enum PREventKind: String, Sendable, CaseIterable {
    case reviewRequested, approved, changesRequested, ciFailed, newComment, merged
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
}

public struct IssueEvent: Equatable, Sendable {
    public let kind: IssueEventKind
    public let issue: BoardIssue
    public let actor: String?

    public init(kind: IssueEventKind, issue: BoardIssue, actor: String?) {
        self.kind = kind
        self.issue = issue
        self.actor = actor
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

    /// Issues someone else newly assigned to `me`. Silent when the previous snapshot never fetched
    /// assigned issues (first load, or a cache from before the Issues mode), when the assignment
    /// event is unknown, for old assignments that reappear (reopened or transferred issues), and for
    /// closed issues a lagging search still returns, which the Assigned list drops too.
    public static func issueEvents(
        old: Snapshot?, new: Snapshot, me: String, toggles: NotificationToggles
    ) -> [IssueEvent] {
        guard toggles.issueAssigned, let old, let before = old.assignedIssues, let now = new.assignedIssues
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
        return result.sorted {
            if $0.issue.key.repo != $1.issue.key.repo { return $0.issue.key.repo < $1.issue.key.repo }
            return $0.issue.key.number < $1.issue.key.number
        }
    }
}
