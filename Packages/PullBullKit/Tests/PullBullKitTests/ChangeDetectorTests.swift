import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func pr(
    _ n: Int, author: String = "alice", ci: CIState = .none, comments: Int = 0,
    lastCommenter: String? = nil, reviews: [Review] = [], requests: [Reviewer] = [],
    draft: Bool = false, updated: Date = now, mergeable: Mergeable? = nil
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: "r", number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: .open, isDraft: draft,
        createdAt: now, updatedAt: updated, closedAt: nil, headRef: "h", baseRef: "main", ci: ci,
        headCommitDate: nil, commentCount: comments, lastCommentAuthor: lastCommenter,
        latestReviews: reviews, reviewRequests: requests, mergeable: mergeable)
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

// MARK: - Ready to merge, comments after my review

@Suite struct ReadyAndReviewCommentTests {
    private let approval = Review(author: "bob", state: .approved, submittedAt: now)
    private let myReview = Review(author: "me", state: .commented, submittedAt: now)

    private var on: NotificationToggles {
        var t = NotificationToggles()
        t.readyToMerge = true
        t.commentAfterMyReview = true
        return t
    }

    @Test func readyToMergeFiresOnceWhenMyPRTurnsReady() {
        let waiting = snap(mine: [pr(1, author: "me", ci: .pending, reviews: [approval])])
        let ready = snap(mine: [pr(1, author: "me", ci: .success, reviews: [approval])])
        #expect(events(waiting, ready, toggles: on).map(\.kind) == [.readyToMerge])
        #expect(events(ready, ready, toggles: on).isEmpty)
        // Off by default.
        #expect(events(waiting, ready).isEmpty)
    }

    /// GitHub recomputing mergeability after a push isn't ready: it may still be conflicting.
    @Test func readyToMergeWaitsForMergeability() {
        let conflicting = snap(mine: [pr(1, author: "me", ci: .success, reviews: [approval], mergeable: .conflicting)])
        let computing = snap(mine: [pr(1, author: "me", ci: .success, reviews: [approval], mergeable: .unknown)])
        let clean = snap(mine: [pr(1, author: "me", ci: .success, reviews: [approval], mergeable: .mergeable)])
        #expect(events(conflicting, computing, toggles: on).isEmpty)
        #expect(events(computing, clean, toggles: on).isEmpty)
        #expect(events(conflicting, clean, toggles: on).map(\.kind) == [.readyToMerge])
    }

    /// A push clears the checks until they start; that gap isn't ready, so it doesn't fire a second time.
    @Test func readyToMergeIgnoresChecksNotYetStarted() {
        let passed = snap(mine: [pr(1, author: "me", ci: .success, reviews: [approval])])
        let pushed = snap(mine: [pr(1, author: "me", ci: .none, reviews: [approval])])
        let failed = snap(mine: [pr(1, author: "me", ci: .failure, reviews: [approval])])
        #expect(!events(failed, pushed, toggles: on).contains { $0.kind == .readyToMerge })
        #expect(events(passed, pushed, toggles: on).isEmpty)
        // A repo without checks is ready on approval.
        let unapproved = snap(mine: [pr(2, author: "me")])
        let approved = snap(mine: [pr(2, author: "me", reviews: [approval])])
        #expect(events(unapproved, approved, toggles: on).map(\.kind).contains(.readyToMerge))
    }

    @Test func commentAfterMyReviewFiresForOthersComments() {
        let before = snap(review: [pr(1, comments: 2, reviews: [myReview])])
        let after = snap(review: [pr(1, comments: 3, lastCommenter: "alice", reviews: [myReview])])
        let e = events(before, after, toggles: on)
        #expect(e.map(\.kind) == [.commentAfterMyReview])
        #expect(e.first?.actor == "alice")
        #expect(events(before, after).isEmpty)
    }

    @Test func commentAfterMyReviewIgnoresMineAndUnreviewed() {
        // My own comment.
        let before = snap(review: [pr(1, comments: 2, reviews: [myReview])])
        let mine = snap(review: [pr(1, comments: 3, lastCommenter: "me", reviews: [myReview])])
        #expect(events(before, mine, toggles: on).isEmpty)
        // A PR I haven't reviewed (only requested): not "after my review".
        // A draft review of mine I haven't submitted.
        let draft = Review(author: "me", state: .pending, submittedAt: now)
        let drafted = snap(review: [pr(3, comments: 0, reviews: [draft])])
        let replied = snap(review: [pr(3, comments: 1, lastCommenter: "alice", reviews: [draft])])
        #expect(events(drafted, replied, toggles: on).isEmpty)
        let requested = snap(review: [pr(2, comments: 0, requests: [.user("me")])])
        let commented = snap(review: [pr(2, comments: 1, lastCommenter: "alice", requests: [.user("me")])])
        #expect(!events(requested, commented, toggles: on).contains { $0.kind == .commentAfterMyReview })
    }
}

// MARK: - Issue comments

private func commented(_ n: Int, comments: Int, by author: String? = "dev-b") -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: "initech/gadgets", number: n), title: "Issue \(n)", url: URL(string: "https://x/i\(n)")!,
        isOpen: true, commentCount: comments, lastCommentAuthor: author)
}

private func issueSnap(_ offset: TimeInterval, assigned: [BoardIssue]?, created: [BoardIssue]?) -> Snapshot {
    Snapshot(
        fetchedAt: t0.addingTimeInterval(offset),
        org: OrgContext(org: "initech", viewer: "devon", members: [], myTeams: [], repos: []),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
        assignedIssues: assigned, createdIssues: created)
}

@Suite struct IssueCommentTests {
    private func run(_ old: Snapshot, _ new: Snapshot, _ toggles: NotificationToggles = .init()) -> [IssueEvent] {
        ChangeDetector.issueEvents(old: old, new: new, me: "devon", toggles: toggles)
    }

    @Test func commentOnAssignedIssueNotifiesByDefault() {
        let old = issueSnap(0, assigned: [commented(1, comments: 1)], created: [])
        let new = issueSnap(120, assigned: [commented(1, comments: 4, by: "dev-b")], created: [])
        let e = run(old, new)
        #expect(e.map(\.kind) == [.comment])
        #expect(e.first?.count == 3)
        #expect(e.first?.actor == "dev-b")
        #expect(e.first?.notificationTitle == "gadgets #1 · 3 new comments")
    }

    @Test func myOwnCommentIsSilent() {
        let old = issueSnap(0, assigned: [commented(1, comments: 1)], created: [])
        let new = issueSnap(120, assigned: [commented(1, comments: 2, by: "devon")], created: [])
        #expect(run(old, new).isEmpty)
    }

    @Test func createdIssueCommentsAreOffByDefault() {
        let old = issueSnap(0, assigned: [], created: [commented(2, comments: 0)])
        let new = issueSnap(120, assigned: [], created: [commented(2, comments: 1)])
        #expect(run(old, new).isEmpty)
        var t = NotificationToggles()
        t.createdIssueComment = true
        #expect(run(old, new, t).map(\.issue.key.number) == [2])
    }

    /// An issue both assigned to me and mine notifies once.
    @Test func assignedAndCreatedNotifyOnce() {
        var t = NotificationToggles()
        t.createdIssueComment = true
        let old = issueSnap(0, assigned: [commented(3, comments: 0)], created: [commented(3, comments: 0)])
        let new = issueSnap(120, assigned: [commented(3, comments: 1)], created: [commented(3, comments: 1)])
        #expect(run(old, new, t).count == 1)
    }

    @Test func searchDecodesTheNewestCommentAuthor() {
        let node: [String: Any] = [
            "number": 7, "title": "t", "url": "https://github.com/o/r/issues/7", "state": "OPEN",
            "repository": ["nameWithOwner": "o/r"], "comments": ["totalCount": 2],
            "lastComment": ["nodes": [["author": ["login": "dev-b"]]]],
        ]
        let issue = Decoding.issue(from: node)
        #expect(issue?.commentCount == 2)
        #expect(issue?.lastCommentAuthor == "dev-b")
        #expect(Queries.issueSearch(withAssignment: false, withLastComment: true).contains(Queries.lastCommentAuthor))
        #expect(!Queries.issueSearch(withAssignment: false).contains("lastComment"))
    }

    /// A failed search carries an older list (at launch, the cached one) forward; its counts aren't a baseline.
    @Test func failedPreviousSearchIsNoBaseline() {
        var old = issueSnap(0, assigned: [commented(1, comments: 1)], created: [])
        old.assignedIssuesError = "timed out"
        let new = issueSnap(120, assigned: [commented(1, comments: 6)], created: [])
        #expect(run(old, new).isEmpty)
        let next = issueSnap(240, assigned: [commented(1, comments: 7)], created: [])
        #expect(run(new, next).map(\.count) == [1])
    }

    /// A newly listed issue's comments aren't news, and neither is a list that wasn't fetched.
    @Test func newlyListedOrUnfetchedIsSilent() {
        let old = issueSnap(0, assigned: [], created: nil)
        let new = issueSnap(120, assigned: [commented(4, comments: 5)], created: [commented(5, comments: 2)])
        var t = NotificationToggles()
        t.createdIssueComment = true
        #expect(run(old, new, t).isEmpty)
    }
}
