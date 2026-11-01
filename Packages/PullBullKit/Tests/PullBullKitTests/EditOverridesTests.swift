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

    @Test func reviewersAgreeOnFirstSnapshotCopy() {
        var o = EditOverrides()
        o.record(.reviewers(added: [.user("alice")], removed: []), on: editKey(77), at: t0)
        let old = editPR(77, requests: [.user("me")]), new = editPR(77, requests: [.user("me"), .user("Alice")])
        o.reconcile(with: editSnapshot(review: [old], team: [new]), now: t0 + 30)
        #expect(!o.isEmpty)
        o.reconcile(with: editSnapshot(review: [new], team: [new]), now: t0 + 60)
        #expect(o.isEmpty)
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
}
