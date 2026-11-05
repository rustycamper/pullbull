import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_100)
private let todo = BoardStatusValue(optionId: "o1", name: "Todo")
private let doing = BoardStatusValue(optionId: "o2", name: "Doing")
private let review = BoardStatusValue(optionId: "o3", name: "Review")
private let options = [
    StatusOption(id: "o1", name: "Todo"), StatusOption(id: "o2", name: "Doing"), StatusOption(id: "o3", name: "Review"),
]
private let bug = LabelRef(id: "LA_bug", name: "bug", color: "d73a4a")
private let docs = LabelRef(id: "LA_docs", name: "docs", color: nil)
private let triage = LabelRef(id: "LA_triage", name: "triage", color: nil)
private let me = PersonRef(id: "U_me", login: "me", avatarURL: nil)
private let alice = PersonRef(id: "U_alice", login: "alice", avatarURL: nil)
private let k412 = editKey(412)
private let k500 = editKey(500)

private func card(_ snapshot: Snapshot, _ key: PRKey) -> BoardIssue? {
    snapshot.boardIssues.first { $0.key == key }
}

private func mergeInfo(autoMerge: AutoMerge? = nil, canDisable: Bool = false) -> MergeInfo {
    MergeInfo(
        nodeID: "PR_1", status: .blocked, hasConflicts: false, usesMergeQueue: false, isStacked: false, isDraft: false,
        autoMerge: autoMerge, canEnableAutoMerge: true, canDisableAutoMerge: canDisable, canWrite: true,
        allowedMethods: [.squash], defaultMethod: .squash, base: "main", commitCount: 1, approvals: 0,
        tally: CheckTally(failing: 0, running: 1, total: 1), changesRequested: false)
}

private func mergeDetail(state: PRState? = .open, merge: MergeInfo? = nil) -> PRDetail {
    PRDetail(key: editKey(77), body: "", checks: [], reviews: [], comments: [], files: [], state: state, merge: merge)
}

@Suite struct EditOverridesTests {
    // MARK: Status

    @Test func statusMovesTheBoardCard() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: doing, placement: .already), on: k412, at: t0)
        let snap = editSnapshot(board: [editIssue(412, status: todo)])
        #expect(card(o.apply(to: snap), k412)?.status == doing)
    }

    @Test func addedToBoardInsertsFromAnotherList() {
        var o = EditOverrides()
        o.record(.status(from: nil, to: todo, placement: .added), on: k500, at: t0)
        let snap = editSnapshot(board: [editIssue(412, status: todo)], created: [editIssue(500)])
        let shown = o.apply(to: snap)
        #expect(card(shown, k500)?.status == todo)
        #expect(shown.boardIssues.count == 2)
    }

    @Test func addedWithNoCopyAnywhereIsSkipped() {
        var o = EditOverrides()
        o.record(.status(from: nil, to: todo, placement: .added), on: k500, at: t0)
        #expect(o.apply(to: editSnapshot(board: [])).boardIssues.isEmpty)
    }

    @Test func removedFromBoardDrops() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: nil, placement: .removed), on: k412, at: t0)
        #expect(card(o.apply(to: editSnapshot(board: [editIssue(412, status: todo)])), k412) == nil)
    }

    // MARK: Labels and assignees

    @Test func labelsAddWithColourAndRemove() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: [triage]), on: k412, at: t0)
        let shown = o.apply(to: editIssue(412, labels: ["triage"]))
        #expect(shown.labels == ["bug"])
        #expect(shown.labelColor(at: 0) == "d73a4a")
    }

    @Test func replaceKeepsOnlyTheAppliedHalf() {
        var o = EditOverrides()
        let id = o.record(.labels(added: [docs], removed: [bug]), on: k412, at: t0)
        o.replace(id, with: .labels(added: [docs], removed: []))
        #expect(o.apply(to: editIssue(412, labels: ["bug"])).labels == ["bug", "docs"])
    }

    @Test func replaceWithNothingDrops() {
        var o = EditOverrides()
        let id = o.record(.labels(added: [docs], removed: []), on: k412, at: t0)
        o.replace(id, with: .labels(added: [], removed: []))
        #expect(o.isEmpty)
    }

    /// The newer edit still applies last: the older one, replaced, stays ahead of it.
    @Test func replaceKeepsTheOrder() {
        var o = EditOverrides()
        let older = o.record(.labels(added: [bug], removed: [docs]), on: k412, at: t0)
        o.record(.labels(added: [], removed: [bug]), on: k412, at: t0 + 1)
        o.replace(older, with: .labels(added: [bug], removed: []))
        #expect(o.apply(to: editIssue(412)).labels.isEmpty)
    }

    @Test func addingAPresentLabelDoesNotDuplicate() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        #expect(o.apply(to: editIssue(412, labels: ["Bug"])).labels == ["Bug"])
    }

    /// Issues cached before colours were stored have none; an added label's colour still lines up.
    @Test func addingToALabelListWithoutColours() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        let old = BoardIssue(
            key: k412, title: "t", url: URL(string: "https://x/412")!, isOpen: true, labels: ["a", "b"], labelColors: [])
        let shown = o.apply(to: old)
        #expect(shown.labels == ["a", "b", "bug"])
        #expect(shown.labelColor(at: 2) == "d73a4a")
    }

    @Test func everyCopyShowsTheEdit() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        let issue = editIssue(412)
        let shown = o.apply(to: editSnapshot(board: [issue], assigned: [issue], created: [issue]))
        #expect(shown.boardIssues[0].labels == ["bug"])
        #expect(shown.assignedIssues?[0].labels == ["bug"])
        #expect(shown.createdIssues?[0].labels == ["bug"])
        let results = o.apply(to: SearchResults(openPRs: [], closedPRs: [], issues: [issue], phase: .done))
        #expect(results.issues[0].labels == ["bug"])
    }

    @Test func selfAssignPutsTheIssueOnAssigned() {
        var o = EditOverrides()
        o.record(.assignees(added: [me], removed: []), on: k500, at: t0)
        let shown = o.apply(to: editSnapshot(board: [editIssue(500, status: todo)], assigned: []))
        #expect(shown.assignedIssues?.map(\.key) == [k500])
        #expect(shown.assignedIssues?.first?.assignees.map(\.login) == ["me"])
    }

    @Test func selfAssignLeavesANeverFetchedAssignedListAlone() {
        var o = EditOverrides()
        o.record(.assignees(added: [me], removed: []), on: k500, at: t0)
        #expect(o.apply(to: editSnapshot(board: [editIssue(500)], assigned: nil)).assignedIssues == nil)
    }

    @Test func selfUnassignTakesItOffAssigned() {
        var o = EditOverrides()
        o.record(.assignees(added: [], removed: [me]), on: k412, at: t0)
        let issue = editIssue(412, assignees: ["me"])
        let shown = o.apply(to: editSnapshot(board: [issue], assigned: [issue]))
        #expect(shown.assignedIssues?.isEmpty == true)
        #expect(shown.boardIssues[0].assignees.isEmpty)
    }

    @Test func assigningSomeoneElseLeavesAssignedAlone() {
        var o = EditOverrides()
        o.record(.assignees(added: [alice], removed: []), on: k500, at: t0)
        #expect(o.apply(to: editSnapshot(board: [editIssue(500)], assigned: [])).assignedIssues?.isEmpty == true)
    }

    @Test func prLabelsAndAssigneesOverlay() {
        var o = EditOverrides()
        let k77 = editKey(77)
        o.record(.labels(added: [bug], removed: []), on: k77, at: t0)
        o.record(.assignees(added: [alice], removed: []), on: k77, at: t0)
        let pr = editPR(77, assignees: ["bo"])
        #expect(o.apply(to: pr).labels == ["bug"])
        #expect(o.apply(to: pr).assignees.map(\.login) == ["bo", "alice"])
        #expect(o.apply(to: editSnapshot(mine: [pr])).mine[0].assignees.map(\.login) == ["bo", "alice"])
        o.record(.assignees(added: [], removed: [PersonRef(id: "U_bo", login: "BO", avatarURL: nil)]), on: k77, at: t0 + 1)
        #expect(o.apply(to: pr).assignees.map(\.login) == ["alice"])
    }

    @Test func prEditShowsInSearchResults() {
        var o = EditOverrides()
        o.record(.assignees(added: [alice], removed: []), on: editKey(77), at: t0)
        let results = SearchResults(openPRs: [editPR(77)], closedPRs: [editPR(78)], issues: [], phase: .done)
        #expect(o.apply(to: results).openPRs[0].assignees.map(\.login) == ["alice"])
        #expect(o.apply(to: results).closedPRs[0].assignees.isEmpty)
    }

    @Test func selfAssignOnAPRLeavesAssignedIssuesAlone() {
        var o = EditOverrides()
        o.record(.assignees(added: [me], removed: []), on: editKey(77), at: t0)
        let shown = o.apply(to: editSnapshot(assigned: [], mine: [editPR(77)]))
        #expect(shown.assignedIssues?.isEmpty == true)
        #expect(shown.mine[0].assignees.map(\.login) == ["me"])
    }

    @Test func prAssigneesAgreeInPRLists() {
        var o = EditOverrides()
        o.record(.assignees(added: [alice], removed: []), on: editKey(77), at: t0)
        o.reconcile(with: editSnapshot(mine: [editPR(77)]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(mine: [editPR(77, assignees: ["Alice"])]), now: t0 + 60)
        #expect(o.isEmpty)
    }

    // MARK: Reviewers

    @Test func reviewersOverlayRequestsNotReviews() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("alice")], removed: [.user("Bob")]), on: editKey(77), at: t0)
        let bobReview = Review(author: "bob", state: .approved, submittedAt: t0)
        let pr = editPR(77, reviews: [bobReview], requests: [.user("bob"), .team(slug: "core", name: "Core")])
        let shown = o.apply(to: editSnapshot(mine: [pr], review: [pr], team: [pr]))
        for copy in [shown.mine[0], shown.reviewCandidates[0], shown.team[0]] {
            #expect(copy.reviewRequests == [.team(slug: "core", name: "Core"), .user("alice")])
            #expect(copy.latestReviews == [bobReview])
        }
        let results = SearchResults(openPRs: [pr], closedPRs: [], issues: [], phase: .done)
        #expect(o.apply(to: results).openPRs[0].reviewRequests.map(\.key) == ["team:core", "alice"])
    }

    @Test func requestedReviewerGetsTheEditTimeAsRequestTime() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("Dana")], removed: []), on: editKey(77), at: t0)
        #expect(o.apply(to: editPR(77)).reviewRequestTimes["dana"] == t0)
    }

    @Test func alreadyPendingReviewerKeepsGitHubsTime() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("dana")], removed: []), on: editKey(77), at: t0)
        let pr = editPR(77, requests: [.user("Dana")], requestTimes: ["dana": t0 - 3600])
        #expect(o.apply(to: pr).reviewRequestTimes["dana"] == t0 - 3600)
    }

    @Test func reviewersAgreeOnFirstSnapshotCopy() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("alice")], removed: []), on: editKey(77), at: t0)
        let old = editPR(77, requests: [.user("me")]), new = editPR(77, requests: [.user("me"), .user("Alice")])
        o.reconcile(with: editSnapshot(review: [old], team: [new]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(review: [new], team: [new]), now: t0 + 60)
        #expect(o.isEmpty)
    }

    // MARK: Reviews

    @Test func reviewShowsAtOnce() {
        var o = EditOverrides()
        let pr = editPR(77, requests: [.user("pb")])
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        let approved = o.apply(to: editSnapshot(viewer: "pb", review: [pr])).reviewCandidates[0]
        #expect(ReviewRules.status(of: approved, me: "pb", myTeams: []) == .approvedByMe)
        var c = EditOverrides()
        c.record(.review(state: .changesRequested, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        let changes = c.apply(to: editSnapshot(viewer: "pb", review: [pr])).reviewCandidates[0]
        #expect(ReviewRules.status(of: changes, me: "pb", myTeams: []) == .reviewedByMe)
    }

    @Test func reviewReplacesEarlierReview() {
        var o = EditOverrides()
        let earlier = Review(author: "pb", state: .changesRequested, submittedAt: t0 - 60, commitOid: "abc")
        o.record(.review(state: .approved, commit: "abc", viewer: "PB"), on: editKey(77), at: t0)
        let shown = o.apply(to: editPR(77, reviews: [earlier]))
        #expect(shown.latestReviews.count == 1)
        #expect(shown.latestReviews[0].author == "PB")
        #expect(shown.latestReviews[0].state == .approved)
        #expect(shown.latestReviews[0].submittedAt == t0)
        #expect(shown.latestReviews[0].commitOid == "abc")
    }

    @Test func reviewLeavesTeamRequestAlone() {
        var o = EditOverrides()
        let team = Reviewer.team(slug: "core", name: "Core")
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        let shown = o.apply(to: editPR(77, requests: [.user("PB"), team]))
        #expect(shown.reviewRequests == [team])
        #expect(ReviewRules.status(of: shown, me: "pb", myTeams: ["core"]) == .approvedByMe)
    }

    @Test func reviewKeepsOthersReviews() {
        var o = EditOverrides()
        let bob = Review(author: "bob", state: .changesRequested, submittedAt: t0 - 60, commitOid: "abc")
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        let shown = o.apply(to: editPR(77, reviews: [bob]))
        #expect(shown.latestReviews.map(\.author) == ["bob", "pb"])
    }

    @Test func reviewAppliesToDetailReviewsAndRequests() {
        var o = EditOverrides()
        o.record(.review(state: .changesRequested, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        let bob = Review(author: "bob", state: .approved, submittedAt: t0 - 60)
        let reviews = o.apply(toReviews: [bob], on: editKey(77))
        #expect(reviews.map(\.author) == ["bob", "pb"])
        #expect(reviews[1].state == .changesRequested)
        #expect(o.apply(toRequests: [.user("PB"), .user("bob")], on: editKey(77)) == [.user("bob")])
        #expect(o.apply(toReviews: [bob], on: editKey(78)) == [bob])
    }

    @Test func reviewCarriesItsTextToTheDetailReviews() {
        var o = EditOverrides()
        let earlier = Review(author: "pb", state: .changesRequested, submittedAt: t0 - 60, commitOid: "abc", body: "Old words")
        o.record(
            .review(state: .approved, commit: "abc", viewer: "pb", body: "Looks good"), on: editKey(77), at: t0)
        let reviews = o.apply(toReviews: [earlier], on: editKey(77))
        #expect(reviews.count == 1)
        #expect(reviews[0].state == .approved)
        #expect(reviews[0].body == "Looks good")
    }

    @Test func reviewWithoutTextShowsNoText() {
        var o = EditOverrides()
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        #expect(o.apply(toReviews: [], on: editKey(77))[0].body == "")
    }

    @Test func reviewAgreesWhenEveryCopyHasIt() {
        let mine = Review(author: "PB", state: .approved, submittedAt: t0, commitOid: "abc")
        let lagging = editPR(77, requests: [.user("pb")])
        let there = editPR(77, reviews: [mine])
        func overrides() -> EditOverrides {
            var o = EditOverrides()
            o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
            return o
        }
        var o = overrides()
        o.reconcile(with: editSnapshot(mine: [there], review: [lagging]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(mine: [there], review: [there]), now: t0 + 60)
        #expect(o.isEmpty)
        var other = overrides()
        let elsewhere = editPR(77, reviews: [Review(author: "pb", state: .approved, submittedAt: t0, commitOid: "def")])
        other.reconcile(with: editSnapshot(review: [elsewhere]), now: t0 + 30)
        #expect(!other.isEmpty)
        var wrongState = overrides()
        let changes = editPR(77, reviews: [Review(author: "pb", state: .changesRequested, submittedAt: t0, commitOid: "abc")])
        wrongState.reconcile(with: editSnapshot(review: [changes]), now: t0 + 30)
        #expect(!wrongState.isEmpty)
        var absent = overrides()
        absent.reconcile(with: editSnapshot(), now: t0 + 30)
        #expect(!absent.isEmpty)
    }

    // GitHub answers the write before its reads catch up, so the detail fetched straight after a review can
    // miss it. The list agreeing must not uncover that read.
    @Test func reviewHeldWhileTheDetailIsBehind() {
        let mine = Review(author: "PB", state: .approved, submittedAt: t0, commitOid: "abc")
        let there = editSnapshot(review: [editPR(77, reviews: [mine])])
        var o = EditOverrides()
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)

        let behind = PRDetail(key: editKey(77), body: "", checks: [], reviews: [], comments: [], files: [], requests: [.user("pb")])
        let held = o.reviewsAhead(of: [editKey(77): behind])
        #expect(held == [editKey(77)])
        o.reconcile(with: there, now: t0 + 30, holdingReviews: held)
        #expect(!o.isEmpty)
        #expect(o.apply(toRequests: [.user("pb")], on: editKey(77)) == [])

        let caughtUp = PRDetail(key: editKey(77), body: "", checks: [], reviews: [mine], comments: [], files: [], requests: [])
        let none = o.reviewsAhead(of: [editKey(77): caughtUp])
        #expect(none.isEmpty)
        o.reconcile(with: there, now: t0 + 60, holdingReviews: none)
        #expect(o.isEmpty)
    }

    // No list can agree on a pull request found by search or a link, so the detail is what must catch up.
    @Test func reviewOnAPullRequestInNoListIsStillBehind() {
        let detail = PRDetail(key: editKey(77), body: "", checks: [], reviews: [], comments: [], files: [])
        var o = EditOverrides()
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        o.reconcile(with: editSnapshot(), now: t0 + 30, holdingReviews: [editKey(77)])
        #expect(!o.isEmpty)
        #expect(o.reviewsAhead(of: [editKey(77): detail]) == [editKey(77)])
    }

    @Test func heldReviewStillExpiresAtLifetime() {
        let mine = Review(author: "pb", state: .approved, submittedAt: t0, commitOid: "abc")
        var o = EditOverrides()
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        o.reconcile(
            with: editSnapshot(review: [editPR(77, reviews: [mine])]), now: t0 + EditOverrides.lifetime,
            holdingReviews: [editKey(77)])
        #expect(o.isEmpty)
    }

    @Test func reviewsAheadReadsOnlyTheNewestReviewOfALoadedDetail() {
        let approved = Review(author: "pb", state: .approved, submittedAt: t0, commitOid: "abc")
        let detail = PRDetail(key: editKey(77), body: "", checks: [], reviews: [approved], comments: [], files: [])
        var o = EditOverrides()
        o.record(.review(state: .changesRequested, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0 + 10)
        #expect(o.reviewsAhead(of: [editKey(77): detail]).isEmpty)
        // Nothing is on screen to uncover without a detail, and other edits never hold.
        #expect(o.reviewsAhead(of: [:]).isEmpty)
        var labels = EditOverrides()
        labels.record(.labels(added: [bug], removed: []), on: editKey(77), at: t0)
        #expect(labels.reviewsAhead(of: [editKey(77): detail]).isEmpty)
    }

    @Test func reviewExpiresAtLifetime() {
        var o = EditOverrides()
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        o.reconcile(with: editSnapshot(review: [editPR(77)]), now: t0 + EditOverrides.lifetime - 1)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(review: [editPR(77)]), now: t0 + EditOverrides.lifetime)
        #expect(o.isEmpty)
    }

    @Test func newerReviewRetiresOlder() {
        var o = EditOverrides()
        o.record(.review(state: .changesRequested, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0 + 10)
        let approved = editPR(77, reviews: [Review(author: "pb", state: .approved, submittedAt: t0 + 10, commitOid: "abc")])
        o.reconcile(with: editSnapshot(review: [approved]), now: t0 + 30)
        #expect(o.isEmpty)
    }

    // Retiring the whole edit would take another reviewer's request off the screen with it.
    @Test func reviewKeepsAnOlderEditThatAlsoAddsSomeoneElse() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("pb"), .user("bob")], removed: []), on: editKey(77), at: t0)
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0 + 10)
        let approved = editPR(77, reviews: [Review(author: "pb", state: .approved, submittedAt: t0 + 10, commitOid: "abc")])
        o.reconcile(with: editSnapshot(review: [approved]), now: t0 + 30)
        #expect(!o.isEmpty)
        #expect(o.apply(toRequests: [], on: editKey(77)).contains(.user("bob")))
    }

    @Test func reviewPastPushNeedsReviewAgain() {
        var o = EditOverrides()
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        let shown = o.apply(to: editPR(77, headOid: "def"))
        #expect(ReviewRules.status(of: shown, me: "pb", myTeams: []) == .needsReview(.newCommitsSinceReview))
    }

    // GitHub drops the viewer's own request when they review, so a self-add made just before never agrees
    // and would put the viewer back as re-requested once the review retires.
    @Test func newerReviewRetiresAnOlderSelfRequest() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("PB")], removed: []), on: editKey(77), at: t0)
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0 + 10)
        let approved = editPR(77, reviews: [Review(author: "pb", state: .approved, submittedAt: t0 + 10, commitOid: "abc")])
        o.reconcile(with: editSnapshot(review: [approved], team: [approved]), now: t0 + 30)
        #expect(o.isEmpty)
        #expect(o.apply(toRequests: [], on: editKey(77)).isEmpty)
    }

    @Test func newerReviewLeavesAnOlderRequestOfSomeoneElse() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("bob")], removed: []), on: editKey(77), at: t0)
        o.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0 + 10)
        let approved = editPR(77, reviews: [Review(author: "pb", state: .approved, submittedAt: t0 + 10, commitOid: "abc")])
        o.reconcile(with: editSnapshot(review: [approved], team: [approved]), now: t0 + 30)
        #expect(!o.isEmpty)
    }

    @Test func selfAddWaitsForReviewCandidates() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("me")], removed: []), on: editKey(77), at: t0)
        let requested = editPR(77, requests: [.user("me")])
        o.reconcile(with: editSnapshot(team: [requested]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(review: [requested], team: [requested]), now: t0 + 60)
        #expect(o.isEmpty)
    }

    @Test func selfAddInsertsCarriedCopyIntoReview() {
        var o = EditOverrides()
        let pr = editPR(77)
        o.record(.reviewers(added: [.user("me")], removed: []), on: editKey(77), at: t0, carrying: pr)
        let shown = o.apply(to: editSnapshot(team: [pr]))
        #expect(shown.reviewCandidates.map(\.key) == [editKey(77)])
        #expect(shown.reviewCandidates[0].reviewRequests == [.user("me")])
        #expect(ReviewRules.status(of: shown.reviewCandidates[0], me: "me", myTeams: []) == .needsReview(.requested))
    }

    @Test func selfAddDoesNotDuplicateAListedPR() {
        var o = EditOverrides()
        let pr = editPR(77)
        o.record(.reviewers(added: [.user("me")], removed: []), on: editKey(77), at: t0, carrying: pr)
        #expect(o.apply(to: editSnapshot(review: [pr])).reviewCandidates.count == 1)
    }

    @Test func closedCopyNeverEntersReview() {
        var o = EditOverrides()
        let pr = editPR(77, state: .closed)
        o.record(.reviewers(added: [.user("me")], removed: []), on: editKey(77), at: t0, carrying: pr)
        #expect(o.apply(to: editSnapshot(team: [pr])).reviewCandidates.isEmpty)
    }

    @Test func selfRemovalLeavesReviewUnlessTeamKeepsIt() {
        var o = EditOverrides()
        o.record(.reviewers(added: [], removed: [.user("me")]), on: editKey(77), at: t0)
        let direct = editPR(77, requests: [.user("me")])
        let shown = o.apply(to: editSnapshot(review: [direct]))
        #expect(ReviewRules.status(of: shown.reviewCandidates[0], me: "me", myTeams: []) == .notRequested)
        let viaTeam = editPR(77, requests: [.user("me"), .team(slug: "core", name: "Core")])
        let kept = o.apply(to: editSnapshot(review: [viaTeam], myTeams: ["core"]))
        #expect(ReviewRules.status(of: kept.reviewCandidates[0], me: "me", myTeams: ["core"])
            == .needsReview(.teamRequested("core")))
    }

    @Test func selfRemovalAgreesWhenDirectRequestGone() {
        var o = EditOverrides()
        o.record(.reviewers(added: [], removed: [.user("me")]), on: editKey(77), at: t0)
        o.reconcile(with: editSnapshot(review: [editPR(77, requests: [.user("me")])]), now: t0 + 30)
        #expect(!o.isEmpty)
        let viaTeam = editPR(77, requests: [.team(slug: "core", name: "Core")])
        o.reconcile(with: editSnapshot(review: [viaTeam], myTeams: ["core"]), now: t0 + 60)
        #expect(o.isEmpty)
    }

    @Test func selfRemovalAgreesWhenReviewDropsIt() {
        var o = EditOverrides()
        o.record(.reviewers(added: [], removed: [.user("me")]), on: editKey(77), at: t0)
        o.reconcile(with: editSnapshot(team: [editPR(77)]), now: t0 + 30)
        #expect(o.isEmpty)
    }

    @Test func ownTeamAddInsertsCarriedCopyIntoReview() {
        var o = EditOverrides()
        let pr = editPR(77)
        let core = Reviewer.team(slug: "Core", name: "Core")
        o.record(.reviewers(added: [core], removed: []), on: editKey(77), at: t0, carrying: pr)
        let shown = o.apply(to: editSnapshot(team: [pr], myTeams: ["core"]))
        #expect(shown.reviewCandidates.map(\.key) == [editKey(77)])
        #expect(ReviewRules.status(of: shown.reviewCandidates[0], me: "me", myTeams: ["core"]).reviewReason != nil)
        #expect(o.apply(to: editSnapshot(team: [pr], myTeams: ["other"])).reviewCandidates.isEmpty)
    }

    @Test func ownTeamAddWaitsForReviewCandidates() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.team(slug: "core", name: "Core")], removed: []), on: editKey(77), at: t0)
        let requested = editPR(77, requests: [.team(slug: "core", name: "Core")])
        o.reconcile(with: editSnapshot(team: [requested], myTeams: ["core"]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(review: [requested], team: [requested], myTeams: ["core"]), now: t0 + 60)
        #expect(o.isEmpty)
    }

    @Test func ownTeamRemovalWaitsForReviewCandidates() {
        var o = EditOverrides()
        o.record(.reviewers(added: [], removed: [.team(slug: "core", name: "Core")]), on: editKey(77), at: t0)
        let requested = editPR(77, requests: [.team(slug: "core", name: "Core")])
        o.reconcile(with: editSnapshot(review: [requested], team: [editPR(77)], myTeams: ["core"]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(team: [editPR(77)], myTeams: ["core"]), now: t0 + 60)
        #expect(o.isEmpty)
    }

    @Test func newerReviewersEditReplacesOverlapping() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("alice")], removed: []), on: editKey(77), at: t0)
        o.record(.reviewers(added: [], removed: [.user("ALICE")]), on: editKey(77), at: t0 + 1)
        o.reconcile(with: editSnapshot(review: [editPR(77)]), now: t0 + 30)
        #expect(o.isEmpty)
    }

    @Test func detailRequestsReadThroughOverride() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("alice")], removed: [.user("bob")]), on: editKey(77), at: t0)
        #expect(o.apply(toRequests: [.user("bob")], on: editKey(77)) == [.user("alice")])
        #expect(o.apply(toRequests: [.user("bob")], on: editKey(78)) == [.user("bob")])
    }

    @Test func replacingAReviewersEditKeepsItsCopy() {
        var o = EditOverrides()
        let pr = editPR(77)
        let id = o.record(.reviewers(added: [.user("me"), .user("x")], removed: []), on: editKey(77), at: t0, carrying: pr)
        o.replace(id, with: .reviewers(added: [.user("me")], removed: []))
        #expect(o.apply(to: editSnapshot(team: [pr])).reviewCandidates.count == 1)
    }

    @Test func editsApplyOldestFirst() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        o.record(.labels(added: [], removed: [bug]), on: k412, at: t0 + 1)
        #expect(o.apply(to: editIssue(412)).labels.isEmpty)
    }

    // MARK: Reconcile

    @Test func agreementDropsOnlyThatOverride() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        o.record(.labels(added: [], removed: [bug]), on: k412, at: t0 + 1)
        let fetched = editSnapshot(board: [editIssue(412, labels: ["bug"])])
        o.reconcile(with: fetched, now: t0 + 30)
        #expect(card(o.apply(to: fetched), k412)?.labels.contains("bug") == false)
        #expect(!o.isEmpty)
    }

    @Test func statusAgreementIsByOptionId() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: doing, placement: .already), on: k412, at: t0)
        let renamed = BoardStatusValue(optionId: "o2", name: "In progress")
        o.reconcile(with: editSnapshot(board: [editIssue(412, status: renamed)], options: options), now: t0 + 10)
        #expect(o.isEmpty)
    }

    @Test func overrideWinsWithinFiveMinutesThenGitHubDoes() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: doing, placement: .already), on: k412, at: t0)
        let fetched = editSnapshot(board: [editIssue(412, status: review)], options: options)
        o.reconcile(with: fetched, now: t0 + 299)
        #expect(card(o.apply(to: fetched), k412)?.status == doing)
        o.reconcile(with: fetched, now: t0 + 300)
        #expect(card(o.apply(to: fetched), k412)?.status == review)
    }

    @Test func deletedOptionDropsTheOverride() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: doing, placement: .already), on: k412, at: t0)
        let withoutDoing = [StatusOption(id: "o1", name: "Todo"), StatusOption(id: "o3", name: "Review")]
        o.reconcile(with: editSnapshot(board: [editIssue(412, status: todo)], options: withoutDoing), now: t0 + 10)
        #expect(o.isEmpty)
    }

    @Test func removedAgreesOnceTheCardIsGone() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: nil, placement: .removed), on: k412, at: t0)
        o.reconcile(with: editSnapshot(board: [editIssue(412, status: todo)], options: options), now: t0 + 10)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(board: [], options: options), now: t0 + 20)
        #expect(o.isEmpty)
    }

    @Test func assigneesAgreeCaseInsensitively() {
        var o = EditOverrides()
        o.record(.assignees(added: [alice], removed: [me]), on: k412, at: t0)
        o.reconcile(with: editSnapshot(board: [editIssue(412, assignees: ["Alice"])]), now: t0 + 10)
        #expect(o.isEmpty)
    }

    @Test func itemMissingFromEveryListKeepsTheOverride() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        o.reconcile(with: editSnapshot(), now: t0 + 60)
        #expect(!o.isEmpty)
    }

    @Test func dropRemovesOne() {
        var o = EditOverrides()
        let first = o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        o.record(.labels(added: [triage], removed: []), on: k412, at: t0 + 1)
        o.drop(first)
        #expect(o.apply(to: editIssue(412)).labels == ["triage"])
    }

    // MARK: Changes

    @Test func inverseRoundTrips() {
        let change = EditChange.status(from: todo, to: doing, placement: .added)
        #expect(change.inverse == .status(from: doing, to: todo, placement: .removed))
        #expect(change.inverse.inverse == change)
        #expect(EditChange.labels(added: [bug], removed: [triage]).inverse == .labels(added: [triage], removed: [bug]))
        #expect(EditChange.assignees(added: [me], removed: []).inverse == .assignees(added: [], removed: [me]))
    }

    @Test func emptyChanges() {
        #expect(EditChange.labels(added: [], removed: []).isEmpty)
        #expect(EditChange.assignees(added: [], removed: []).isEmpty)
        #expect(EditChange.status(from: todo, to: BoardStatusValue(optionId: "o1", name: "x"), placement: .already).isEmpty)
        #expect(!EditChange.status(from: todo, to: todo, placement: .added).isEmpty)
        #expect(!EditChange.labels(added: [bug], removed: []).isEmpty)
    }

    @Test func applyLeavesStoredFieldsAlone() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        let snap = editSnapshot(board: [editIssue(412)])
        let shown = o.apply(to: snap)
        #expect(snap.boardIssues[0].labels.isEmpty)
        #expect(shown.fetchedAt == snap.fetchedAt)
        #expect(shown.boardIssues[0].title == snap.boardIssues[0].title)
    }

    // MARK: Several edits on one item

    /// A fetch that agrees with the last edit retires the edits it replaced.
    @Test func threeStatusesThenAFetchAfterAllLanded() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: doing, placement: .already), on: k412, at: t0)
        o.record(.status(from: doing, to: review, placement: .already), on: k412, at: t0 + 2)
        let fetched = editSnapshot(board: [editIssue(412, status: review)], options: options)
        o.reconcile(with: fetched, now: t0 + 30)
        #expect(card(o.apply(to: fetched), k412)?.status == review)
        #expect(o.isEmpty)
    }

    @Test func statusThereAndBack() {
        var o = EditOverrides()
        o.record(.status(from: todo, to: doing, placement: .already), on: k412, at: t0)
        o.record(.status(from: doing, to: todo, placement: .already), on: k412, at: t0 + 2)
        let fetched = editSnapshot(board: [editIssue(412, status: todo)], options: options)
        o.reconcile(with: fetched, now: t0 + 30)
        #expect(card(o.apply(to: fetched), k412)?.status == todo)
    }

    @Test func labelAddedThenRemoved() {
        var o = EditOverrides()
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0)
        o.record(.labels(added: [], removed: [bug]), on: k412, at: t0 + 2)
        let fetched = editSnapshot(board: [editIssue(412)])
        o.reconcile(with: fetched, now: t0 + 30)
        #expect(card(o.apply(to: fetched), k412)?.labels.isEmpty == true)
    }

    /// Retiring is by label: an older edit to another label stays until GitHub shows it.
    @Test func agreementLeavesOlderEditsToOtherLabels() {
        var o = EditOverrides()
        o.record(.labels(added: [triage], removed: []), on: k412, at: t0)
        o.record(.labels(added: [bug], removed: []), on: k412, at: t0 + 2)
        let fetched = editSnapshot(board: [editIssue(412, labels: ["bug"])])
        o.reconcile(with: fetched, now: t0 + 30)
        #expect(card(o.apply(to: fetched), k412)?.labels == ["bug", "triage"])
    }

    /// Adding to the board and undoing it, then a fetch from before the add: the card stays off.
    @Test func addToBoardThenUndo() {
        var o = EditOverrides()
        o.record(.status(from: nil, to: todo, placement: .added), on: k500, at: t0)
        o.record(.status(from: todo, to: nil, placement: .removed), on: k500, at: t0 + 3)
        let fetched = editSnapshot(board: [], created: [editIssue(500)], options: options)
        o.reconcile(with: fetched, now: t0 + 30)
        #expect(card(o.apply(to: fetched), k500) == nil)
    }

    // MARK: Assigned lags

    /// The board shows the new assignee at once; Assigned waits for search. The override holds until both do.
    @Test func selfAssignHoldsUntilAssignedCatchesUp() {
        var o = EditOverrides()
        o.record(.assignees(added: [me], removed: []), on: k500, at: t0)
        let lagging = editSnapshot(board: [editIssue(500, assignees: ["me"])], assigned: [])
        o.reconcile(with: lagging, now: t0 + 30)
        #expect(o.apply(to: lagging).assignedIssues?.map(\.key) == [k500])
        let caughtUp = editSnapshot(
            board: [editIssue(500, assignees: ["me"])], assigned: [editIssue(500, assignees: ["me"])])
        o.reconcile(with: caughtUp, now: t0 + 60)
        #expect(o.isEmpty)
    }

    @Test func selfUnassignHoldsUntilAssignedCatchesUp() {
        var o = EditOverrides()
        o.record(.assignees(added: [], removed: [me]), on: k412, at: t0)
        let lagging = editSnapshot(board: [editIssue(412)], assigned: [editIssue(412)])
        o.reconcile(with: lagging, now: t0 + 30)
        #expect(o.apply(to: lagging).assignedIssues?.isEmpty == true)
        o.reconcile(with: editSnapshot(board: [editIssue(412)], assigned: []), now: t0 + 60)
        #expect(o.isEmpty)
    }

    /// A closed issue never shows on Assigned, so the board copy alone settles it.
    @Test func selfAssignOnAClosedIssueAgreesWithoutAssigned() {
        var o = EditOverrides()
        o.record(.assignees(added: [me], removed: []), on: k500, at: t0)
        o.reconcile(with: editSnapshot(board: [editIssue(500, assignees: ["me"], isOpen: false)], assigned: []), now: t0 + 30)
        #expect(o.isEmpty)
    }

    // MARK: Merging

    @Test func mergedShowsAtOnce() {
        var o = EditOverrides()
        o.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        let shown = o.apply(to: editPR(77))
        #expect(shown.state == .merged)
        #expect(shown.mergedBy == "pb")
        #expect(o.apply(to: editPR(78)).state == .open)
        #expect(o.apply(to: editSnapshot(mine: [editPR(77)])).mine.first?.state == .merged)
        #expect(o.apply(toState: .open, on: editKey(77)) == .merged)
        #expect(o.apply(toState: nil, on: editKey(77)) == .merged)
        #expect(o.apply(toState: .open, on: editKey(78)) == .open)
        #expect(o.apply(to: editIssue(77)) == editIssue(77))
    }

    @Test func mergedAgreesWhenTheListSaysSo() {
        var o = EditOverrides()
        o.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        o.reconcile(with: editSnapshot(mine: [editPR(77)]), now: t0 + 30)
        #expect(!o.isEmpty)
        // One list can trail another: every copy has to have moved on.
        o.reconcile(with: editSnapshot(mine: [editPR(77, state: .merged)], review: [editPR(77)]), now: t0 + 60)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(mine: [editPR(77, state: .merged)]), now: t0 + 90)
        #expect(o.isEmpty)
    }

    @Test func aMergedPRLeavingTheListsAgrees() {
        var gone = EditOverrides()
        gone.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        gone.reconcile(with: editSnapshot(mine: [editPR(78)]), now: t0 + 30)
        #expect(gone.isEmpty)

        var closed = EditOverrides()
        closed.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        closed.reconcile(with: editSnapshot(closed: [editPR(77, state: .merged)]), now: t0 + 30)
        #expect(closed.isEmpty)
    }

    // The list agreeing must not uncover a detail still reading open, or Merge would come back.
    @Test func mergeHeldWhileTheDetailShowsOpen() {
        let there = editSnapshot(closed: [editPR(77, state: .merged)])
        var o = EditOverrides()
        o.record(.merged(viewer: "pb"), on: editKey(77), at: t0)

        let held = o.mergesAhead(of: [editKey(77): mergeDetail(state: .open)])
        #expect(held == [editKey(77)])
        o.reconcile(with: there, now: t0 + 30, holdingMerges: held)
        #expect(!o.isEmpty)
        #expect(o.apply(toState: .open, on: editKey(77)) == .merged)

        // A detail cached before `state` was stored shows no merge either.
        #expect(o.mergesAhead(of: [editKey(77): mergeDetail(state: nil)]) == [editKey(77)])

        let none = o.mergesAhead(of: [editKey(77): mergeDetail(state: .merged)])
        #expect(none.isEmpty)
        o.reconcile(with: there, now: t0 + 60, holdingMerges: none)
        #expect(o.isEmpty)
    }

    @Test func holdingReviewsAndHoldingMergesAreSeparate() {
        let mine = Review(author: "pb", state: .approved, submittedAt: t0, commitOid: "abc")
        let there = editSnapshot(closed: [editPR(77, state: .merged, reviews: [mine])])

        var merge = EditOverrides()
        merge.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        merge.reconcile(with: there, now: t0 + 30, holdingReviews: [editKey(77)])
        #expect(merge.isEmpty)

        var review = EditOverrides()
        review.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        review.reconcile(with: there, now: t0 + 30, holdingMerges: [editKey(77)])
        #expect(review.isEmpty)
    }

    @Test func heldMergeStillEndsAtLifetime() {
        var o = EditOverrides()
        o.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        o.reconcile(
            with: editSnapshot(closed: [editPR(77, state: .merged)]), now: t0 + EditOverrides.lifetime,
            holdingMerges: [editKey(77)])
        #expect(o.isEmpty)
    }

    @Test func directMergesAreTheLiveMergedEdits() {
        var o = EditOverrides()
        #expect(o.directMerges.isEmpty)
        let merged = o.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        o.record(.autoMerge(enabled: true, viewer: "pb"), on: editKey(78), at: t0)
        o.record(.labels(added: [], removed: []), on: editKey(79), at: t0)
        #expect(o.directMerges == [editKey(77)])
        o.drop(merged)
        #expect(o.directMerges.isEmpty)
    }

    @Test func autoMergeShowsOnTheDetail() {
        var on = EditOverrides()
        on.record(.autoMerge(enabled: true, viewer: "pb"), on: editKey(77), at: t0)
        let enabled = on.apply(toMerge: mergeInfo(), on: editKey(77))
        #expect(enabled?.autoMerge == AutoMerge(enabledBy: "pb"))
        #expect(enabled?.canDisableAutoMerge == true)
        #expect(enabled?.status == .blocked)
        #expect(on.apply(toMerge: mergeInfo(), on: editKey(78)) == mergeInfo())
        #expect(on.apply(toMerge: nil, on: editKey(77)) == nil)

        var off = EditOverrides()
        off.record(.autoMerge(enabled: false, viewer: "pb"), on: editKey(77), at: t0)
        let set = mergeInfo(autoMerge: AutoMerge(enabledBy: "pb"), canDisable: true)
        #expect(off.apply(toMerge: set, on: editKey(77)) == mergeInfo())

        // List pull requests carry no auto-merge data.
        #expect(on.apply(to: editPR(77)) == editPR(77))
        #expect(on.apply(toState: .open, on: editKey(77)) == .open)
    }

    @Test func autoMergeHeldUntilTheDetailShowsIt() {
        let there = editSnapshot(mine: [editPR(77)])
        var o = EditOverrides()
        o.record(.autoMerge(enabled: true, viewer: "pb"), on: editKey(77), at: t0)

        let held = o.mergesAhead(of: [editKey(77): mergeDetail(merge: mergeInfo())])
        #expect(held == [editKey(77)])
        o.reconcile(with: there, now: t0 + 30, holdingMerges: held)
        #expect(!o.isEmpty)

        let shows = mergeInfo(autoMerge: AutoMerge(enabledBy: "pb"), canDisable: true)
        let none = o.mergesAhead(of: [editKey(77): mergeDetail(merge: shows)])
        #expect(none.isEmpty)
        o.reconcile(with: there, now: t0 + 60, holdingMerges: none)
        #expect(o.isEmpty)
    }

    // A Merge when ready can land inside the lifetime, and a detail that isn't open has no auto-merge to show.
    @Test func autoMergeSettlesOnceTheDetailIsNoLongerOpen() {
        let there = editSnapshot(closed: [editPR(77, state: .merged)])
        var o = EditOverrides()
        o.record(.autoMerge(enabled: true, viewer: "pb"), on: editKey(77), at: t0)

        // A detail cached before `state` was stored might still be open, so it's read again.
        #expect(o.mergesAhead(of: [editKey(77): mergeDetail(state: nil, merge: mergeInfo())]) == [editKey(77)])
        #expect(o.mergesAhead(of: [editKey(77): mergeDetail(state: .closed, merge: mergeInfo())]).isEmpty)

        let none = o.mergesAhead(of: [editKey(77): mergeDetail(state: .merged, merge: mergeInfo())])
        #expect(none.isEmpty)
        o.reconcile(with: there, now: t0 + 30, holdingMerges: none)
        #expect(o.isEmpty)

        // Some PRs keep their auto-merge request after merging, which a cancel would otherwise wait out.
        var cancel = EditOverrides()
        cancel.record(.autoMerge(enabled: false, viewer: "pb"), on: editKey(77), at: t0)
        let kept = mergeInfo(autoMerge: AutoMerge(enabledBy: "pb"))
        #expect(cancel.mergesAhead(of: [editKey(77): mergeDetail(state: .merged, merge: kept)]).isEmpty)
    }

    @Test func aCancelIsHeldWhileTheDetailStillShowsAutoMerge() {
        var o = EditOverrides()
        o.record(.autoMerge(enabled: false, viewer: "pb"), on: editKey(77), at: t0)
        let set = mergeInfo(autoMerge: AutoMerge(enabledBy: "pb"), canDisable: true)
        #expect(o.mergesAhead(of: [editKey(77): mergeDetail(merge: set)]) == [editKey(77)])
        #expect(o.mergesAhead(of: [editKey(77): mergeDetail(merge: mergeInfo())]).isEmpty)
    }

    @Test func mergesAheadNeedsALoadedDetailAndAMerge() {
        var o = EditOverrides()
        o.record(.merged(viewer: "pb"), on: editKey(77), at: t0)
        #expect(o.mergesAhead(of: [:]).isEmpty)
        var review = EditOverrides()
        review.record(.review(state: .approved, commit: "abc", viewer: "pb"), on: editKey(77), at: t0)
        #expect(review.mergesAhead(of: [editKey(77): mergeDetail()]).isEmpty)
    }

    @Test func mergeNeverUndoes() {
        let changes: [EditChange] = [.merged(viewer: "pb"), .autoMerge(enabled: true, viewer: "pb")]
        for change in changes {
            #expect(change.inverse == change)
            #expect(change.keeping(SetChangeResult(addApplied: false, removeApplied: false, refusal: nil)) == change)
            #expect(!change.isEmpty)
        }
    }

    @Test func enablingThenCancellingAutoMergeSettles() {
        let there = editSnapshot(mine: [editPR(77)])
        let set = mergeInfo(autoMerge: AutoMerge(enabledBy: "pb"), canDisable: true)
        var o = EditOverrides()
        o.record(.autoMerge(enabled: true, viewer: "pb"), on: editKey(77), at: t0)
        o.record(.autoMerge(enabled: false, viewer: "pb"), on: editKey(77), at: t0 + 10)

        // The detail read between the two shows the enable: the cancel is what it's behind.
        let behind = o.mergesAhead(of: [editKey(77): mergeDetail(merge: set)])
        #expect(behind == [editKey(77)])
        o.reconcile(with: there, now: t0 + 20, holdingMerges: behind)
        #expect(!o.isEmpty)
        #expect(o.apply(toMerge: set, on: editKey(77)) == mergeInfo())

        // Only the newest counts: the enable no longer asks for an auto-merge the detail won't show.
        let none = o.mergesAhead(of: [editKey(77): mergeDetail(merge: mergeInfo())])
        #expect(none.isEmpty)
        o.reconcile(with: there, now: t0 + 30, holdingMerges: none)
        #expect(o.isEmpty)
    }
}
