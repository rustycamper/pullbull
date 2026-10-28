import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func pr(
    _ n: Int, author: String = "alice", ci: CIState = .none, comments: Int = 0,
    lastCommenter: String? = nil, reviews: [Review] = [], requests: [Reviewer] = [],
    draft: Bool = false, updated: Date = now
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "r", number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: .open, isDraft: draft,
        createdAt: now, updatedAt: updated, closedAt: nil, headRef: "h", baseRef: "main", ci: ci,
        headCommitDate: nil, commentCount: comments, lastCommentAuthor: lastCommenter,
        latestReviews: reviews, reviewRequests: requests)
}

private func snap(review: [PullRequest] = [], mine: [PullRequest] = []) -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: review, mine: mine, team: [], recentlyClosed: [], boardIssues: [])
}

private func events(_ old: Snapshot?, _ new: Snapshot, toggles: NotificationToggles = .init()) -> [PREvent] {
    ChangeDetector.events(old: old, new: new, me: "me", myTeams: [], toggles: toggles)
}

@Suite struct ChangeDetectorTests {
    @Test func firstLoadSilent() {
        let s = snap(review: [pr(1, requests: [.user("me")])], mine: [pr(2, author: "me", ci: .failure)])
        #expect(events(nil, s).isEmpty)
    }

    @Test func reviewRequestedOnce() {
        let empty = snap()
        let s = snap(review: [pr(1, requests: [.user("me")])])
        let first = events(empty, s)
        #expect(first.map(\.kind) == [.reviewRequested])
        #expect(first.first?.actor == "alice")
        #expect(events(s, s).isEmpty)
    }

    @Test func aNewReasonForAPRStillNeedingReviewDoesNotNotifyAgain() {
        let commented = Review(author: "me", state: .commented, submittedAt: now.addingTimeInterval(-60))
        let teamRequested = snap(review: [pr(1, requests: [.team("core")])])
        let reRequested = snap(review: [pr(1, reviews: [commented], requests: [.user("me"), .team("core")])])
        let e = ChangeDetector.events(
            old: teamRequested, new: reRequested, me: "me", myTeams: ["core"], toggles: .init())
        #expect(e.isEmpty)
    }

    @Test func approvalFires() {
        let old = snap(mine: [pr(1, author: "me")])
        let review = Review(author: "bob", state: .approved, submittedAt: now)
        let new = snap(mine: [pr(1, author: "me", reviews: [review])])
        let e = events(old, new)
        #expect(e.map(\.kind) == [.approved])
        #expect(e.first?.actor == "bob")
        #expect(events(new, new).isEmpty)
    }

    @Test func changesRequestedFires() {
        let old = snap(mine: [pr(1, author: "me")])
        let review = Review(author: "bob", state: .changesRequested, submittedAt: now)
        let e = events(old, snap(mine: [pr(1, author: "me", reviews: [review])]))
        #expect(e.map(\.kind) == [.changesRequested])
    }

    @Test func ownCommentSilent() {
        let old = snap(mine: [pr(1, author: "me", comments: 1)])
        let own = snap(mine: [pr(1, author: "me", comments: 2, lastCommenter: "ME")])
        #expect(events(old, own).isEmpty)
        let other = snap(mine: [pr(1, author: "me", comments: 2, lastCommenter: "bob")])
        let e = events(old, other)
        #expect(e.map(\.kind) == [.newComment])
        #expect(e.first?.actor == "bob")
    }

    @Test func ciFailureTransitionOnly() {
        let passing = snap(mine: [pr(1, author: "me", ci: .success)])
        let failing = snap(mine: [pr(1, author: "me", ci: .failure)])
        let e = events(passing, failing)
        #expect(e.map(\.kind) == [.ciFailed])
        #expect(e.first?.actor == nil)
        #expect(events(failing, failing).isEmpty)
    }

    @Test func newPRInMineIsSilent() {
        let review = Review(author: "bob", state: .approved, submittedAt: now)
        let new = snap(mine: [pr(1, author: "me", ci: .failure, comments: 3, lastCommenter: "bob", reviews: [review])])
        #expect(events(snap(), new).isEmpty)
    }

    @Test func toggleOffSuppresses() {
        let old = snap(mine: [pr(1, author: "me", ci: .success)])
        let new = snap(review: [pr(2, requests: [.user("me")])], mine: [pr(1, author: "me", ci: .failure)])
        #expect(events(old, new).map(\.kind) == [.reviewRequested, .ciFailed])
        var t = NotificationToggles()
        t.ciFailed = false
        #expect(events(old, new, toggles: t).map(\.kind) == [.reviewRequested])
        t.reviewRequested = false
        #expect(events(old, new, toggles: t).isEmpty)
    }

    @Test func reviewRequestRespectsReviewFilters() {
        let old = now.addingTimeInterval(-90 * 86_400)
        let s = snap(review: [
            pr(1, requests: [.user("me")], draft: true),
            pr(2, requests: [.user("me")], updated: old),
            pr(3, requests: [.user("me")]),
        ])
        var settings = AppSettings()
        settings.hideDrafts = true
        settings.hideOlderThanTwoMonths = true
        let filtered = ChangeDetector.events(
            old: snap(), new: s, me: "me", myTeams: [], toggles: .init(),
            filters: ReviewFilters(settings), now: now)
        #expect(filtered.map(\.pr.key.number) == [3])
        #expect(events(snap(), s).map(\.pr.key.number) == [1, 2, 3])
    }
}

private func merged(
    _ n: Int, author: String = "me", by: String? = "anna", state: PRState = .merged, closed: Date = now
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "r", number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: false,
        createdAt: now, updatedAt: closed, closedAt: closed, headRef: "h", baseRef: "main", ci: .success,
        headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
        latestReviews: [], reviewRequests: [], mergedBy: by)
}

private func poll(
    _ offset: TimeInterval, mine: [PullRequest] = [], closed: [PullRequest] = []
) -> Snapshot {
    Snapshot(
        fetchedAt: now.addingTimeInterval(offset),
        org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: [], mine: mine, team: [], recentlyClosed: closed, boardIssues: [])
}

@Suite struct MergedChangeDetectorTests {
    @Test func openThenMergedNotifiesOnce() {
        let open = poll(0, mine: [pr(1, author: "me")])
        let done = poll(120, closed: [merged(1, closed: now.addingTimeInterval(60))])
        let e = events(open, done)
        #expect(e.map(\.kind) == [.merged])
        #expect(e.first?.actor == "anna")
        #expect(e.first?.pr.state == .merged)
        #expect(events(done, poll(240, closed: done.recentlyClosed)).isEmpty)
    }

    @Test func firstLoadIsSilent() {
        #expect(events(nil, poll(120, closed: [merged(1, closed: now.addingTimeInterval(60))])).isEmpty)
    }

    @Test func alreadyMergedInTheBaselineIsSilent() {
        let pr = merged(1, closed: now.addingTimeInterval(-60))
        #expect(events(poll(0, closed: [pr]), poll(120, closed: [pr])).isEmpty)
    }

    @Test func mergeOfMyOwnHandIsSilent() {
        let open = poll(0, mine: [pr(1, author: "me")])
        #expect(events(open, poll(120, closed: [merged(1, by: "ME", closed: now.addingTimeInterval(60))])).isEmpty)
    }

    @Test func unknownMergerStillNotifies() {
        let open = poll(0, mine: [pr(1, author: "me")])
        let e = events(open, poll(120, closed: [merged(1, by: nil, closed: now.addingTimeInterval(60))]))
        #expect(e.map(\.kind) == [.merged])
        #expect(e.first?.actor == nil)
    }

    @Test func closedWithoutMergeIsSilent() {
        let open = poll(0, mine: [pr(1, author: "me")])
        #expect(events(open, poll(120, closed: [merged(1, by: nil, state: .closed)])).isEmpty)
    }

    @Test func someoneElsesPRIsSilent() {
        let open = poll(0, mine: [pr(1, author: "bob")])
        #expect(events(open, poll(120, closed: [merged(1, author: "bob", closed: now.addingTimeInterval(60))])).isEmpty)
    }

    @Test func toggleOffSuppresses() {
        var t = NotificationToggles()
        t.merged = false
        let open = poll(0, mine: [pr(1, author: "me")])
        #expect(events(open, poll(120, closed: [merged(1, closed: now.addingTimeInterval(60))]), toggles: t).isEmpty)
    }

    /// The open search can drop a PR a poll before the closed search returns it.
    @Test func lateClosedSearchStillNotifiesARecentMerge() {
        let gap = poll(0)
        let e = events(gap, poll(120, closed: [merged(1, closed: now.addingTimeInterval(-ChangeDetector.mergeLag))]))
        #expect(e.map(\.kind) == [.merged])
    }

    /// A merge older than the previous poll that reappears (a closed search that briefly dropped it,
    /// or a scope that now includes its repo) was never seen happen.
    @Test func oldMergeReappearingIsSilent() {
        let old = merged(1, closed: now.addingTimeInterval(-ChangeDetector.mergeLag - 1))
        #expect(events(poll(0), poll(120, closed: [old])).isEmpty)
    }

    @Test func duplicateNodesNotifyOnce() {
        let open = poll(0, mine: [pr(1, author: "me")])
        let pr = merged(1, closed: now.addingTimeInterval(60))
        #expect(events(open, poll(120, closed: [pr, pr])).map(\.kind) == [.merged])
    }

    @Test func sortsAfterOtherKinds() {
        let open = poll(0, mine: [pr(1, author: "me"), pr(2, author: "me", ci: .success)])
        let next = poll(120, mine: [pr(2, author: "me", ci: .failure)], closed: [merged(1, closed: now.addingTimeInterval(60))])
        #expect(events(open, next).map(\.kind) == [.ciFailed, .merged])
    }
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func issue(
    _ n: Int, repo: String = "initech/gadgets", open: Bool = true, assignment: Assignment?
) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: n), title: "Issue \(n)", url: URL(string: "https://x/i\(n)")!,
        isOpen: open, myAssignment: assignment)
}

private func issueSnap(_ offset: TimeInterval, assigned: [BoardIssue]?) -> Snapshot {
    Snapshot(
        fetchedAt: t0.addingTimeInterval(offset),
        org: OrgContext(org: "initech", viewer: "devon", members: [], myTeams: [], repos: []),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
        assignedIssues: assigned)
}

private var issuesOn: NotificationToggles {
    var t = NotificationToggles()
    t.issueAssigned = true
    return t
}

@Suite struct IssueChangeDetectorTests {
    private let old = issueSnap(0, assigned: [issue(100, assignment: Assignment(actor: "dev-a", at: t0))])
    private func new(_ extra: BoardIssue...) -> Snapshot {
        issueSnap(120, assigned: old.assignedIssues! + extra)
    }
    private func run(_ old: Snapshot?, _ new: Snapshot, toggles: NotificationToggles = issuesOn) -> [IssueEvent] {
        ChangeDetector.issueEvents(old: old, new: new, me: "devon", toggles: toggles)
    }

    @Test func newAssignmentBySomeoneElseNotifies() {
        let next = new(issue(231, assignment: Assignment(actor: "dev-b", at: t0.addingTimeInterval(60))))
        let e = run(old, next)
        #expect(e.map(\.issue.key.number) == [231])
        #expect(e.first?.kind == .assigned)
        #expect(e.first?.actor == "dev-b")
    }

    @Test func offByDefault() {
        let next = new(issue(231, assignment: Assignment(actor: "dev-b", at: t0.addingTimeInterval(60))))
        #expect(run(old, next, toggles: NotificationToggles()).isEmpty)
    }

    @Test func firstLoadPostsNothing() {
        let next = new(issue(231, assignment: Assignment(actor: "dev-b", at: t0.addingTimeInterval(60))))
        #expect(run(nil, next).isEmpty)
    }

    @Test func noEventsWhenOldAssignedNeverFetched() {
        let legacy = issueSnap(0, assigned: nil)
        let next = new(issue(231, assignment: Assignment(actor: "dev-b", at: t0.addingTimeInterval(60))))
        #expect(run(legacy, next).isEmpty)
    }

    @Test func selfAssignDoesNotNotify() {
        let next = new(issue(231, assignment: Assignment(actor: "Devon", at: t0.addingTimeInterval(60))))
        #expect(run(old, next).isEmpty)
    }

    @Test func oldAssignmentDoesNotNotify() {
        let next = new(issue(231, assignment: Assignment(actor: "dev-b", at: t0.addingTimeInterval(-30 * 86_400))))
        #expect(run(old, next).isEmpty)
    }

    @Test func alreadyAssignedDoesNotRepeat() {
        let a = issue(231, assignment: Assignment(actor: "dev-b", at: t0.addingTimeInterval(60)))
        let both = issueSnap(0, assigned: [a])
        #expect(run(both, issueSnap(120, assigned: [a])).isEmpty)
    }

    @Test func unknownAssignmentDoesNotNotify() {
        #expect(run(old, new(issue(231, assignment: nil))).isEmpty)
    }

    @Test func nilActorNotifiesAndLagIsAllowed() {
        let lagged = Assignment(actor: nil, at: t0.addingTimeInterval(-ChangeDetector.assignmentLag))
        let e = run(old, new(issue(231, assignment: lagged)))
        #expect(e.map(\.issue.key.number) == [231])
        #expect(e.first?.actor == nil)
        let tooOld = Assignment(actor: "dev-b", at: t0.addingTimeInterval(-ChangeDetector.assignmentLag - 1))
        #expect(run(old, new(issue(232, assignment: tooOld))).isEmpty)
    }

    @Test func closedNodeFromLaggingSearchDoesNotNotify() {
        // Assigned and closed between polls; the lagging is:open search still returns the node, which
        // the Assigned list and badge drop.
        let at = Assignment(actor: "dev-b", at: t0.addingTimeInterval(60))
        #expect(run(old, new(issue(231, open: false, assignment: at), issue(232, assignment: at)))
            .map(\.issue.key.number) == [232])
    }

    @Test func sortsByRepoThenNumber() {
        let at = Assignment(actor: "dev-b", at: t0.addingTimeInterval(60))
        let next = new(
            issue(9, repo: "initech/widgets", assignment: at),
            issue(300, assignment: at),
            issue(231, assignment: at))
        #expect(run(old, next).map { "\($0.issue.key.repo)#\($0.issue.key.number)" } == [
            "initech/gadgets#231", "initech/gadgets#300", "initech/widgets#9",
        ])
    }
}
