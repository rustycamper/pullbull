import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let key = PRKey(repo: "acme/app", number: 12)
private let up = ReactionTarget(subjectId: "S1", content: .thumbsUp)

private func group(_ content: ReactionContent, _ count: Int, mine: Bool = false) -> ReactionGroup {
    ReactionGroup(content: content, count: count, viewerHasReacted: mine, reactors: [])
}

private func reactions(_ groups: [ReactionGroup], id: String = "S1") -> Reactions {
    Reactions(subjectId: id, groups: groups, viewerCanReact: true)
}

private func overrides(add: Bool = true, answeredAt: Date? = nil) -> ReactionOverrides {
    var o = ReactionOverrides()
    o.record(up, add: add, on: key, at: t0)
    if let answeredAt { o.answered(up, at: answeredAt) }
    return o
}

@Suite struct ReactionOverridesTests {
    @Test func addingRaisesTheCountAndTints() {
        let shown = overrides().apply(to: reactions([group(.thumbsUp, 2)]), fetchedAt: nil, now: t0)
        #expect(shown?.groups == [group(.thumbsUp, 3, mine: true)])
    }

    @Test func removingYourOnlyReactionHidesTheChip() {
        let shown = overrides(add: false).apply(to: reactions([group(.thumbsUp, 1, mine: true)]), fetchedAt: nil, now: t0)
        #expect(shown?.shown.isEmpty == true)
    }

    @Test func addingAReactionNobodyGaveCreatesItInGitHubsOrder() {
        var o = ReactionOverrides()
        let hooray = ReactionTarget(subjectId: "S1", content: .hooray)
        o.record(hooray, add: true, on: key, at: t0)
        let shown = o.apply(to: reactions([group(.thumbsUp, 1), group(.heart, 2)]), fetchedAt: nil, now: t0)
        #expect(shown?.groups.map(\.content) == [.thumbsUp, .hooray, .heart])
        #expect(shown?.groups[1] == group(.hooray, 1, mine: true))
        let empty = o.apply(to: reactions([]), fetchedAt: nil, now: t0)
        #expect(empty?.groups == [group(.hooray, 1, mine: true)])
    }

    @Test func applyIsIdempotentWhenTheFetchAlreadyAgrees() {
        let agreed = reactions([group(.thumbsUp, 3, mine: true)])
        #expect(overrides().apply(to: agreed, fetchedAt: nil, now: t0) == agreed)
        let gone = reactions([group(.thumbsUp, 0)])
        #expect(overrides(add: false).apply(to: gone, fetchedAt: nil, now: t0) == gone)
    }

    @Test func aNewerClickReplacesTheOlder() {
        var o = overrides(add: true)
        o.record(up, add: false, on: key, at: t0 + 1)
        #expect(o.wanted(up) == false)
        o.record(up, add: true, on: key, at: t0 + 2)
        #expect(o.wanted(up) == true)
    }

    @Test func anUnansweredOverrideSurvivesAnyFetch() {
        let shown = overrides().apply(to: reactions([group(.thumbsUp, 0)]), fetchedAt: t0 + 60, now: t0 + 61)
        #expect(shown?.groups == [group(.thumbsUp, 1, mine: true)])
    }

    @Test func aFetchStartedBeforeTheAnswerKeepsTheOverride() {
        let shown = overrides(answeredAt: t0 + 10)
            .apply(to: reactions([group(.thumbsUp, 0)]), fetchedAt: t0 + 9, now: t0 + 12)
        #expect(shown?.groups == [group(.thumbsUp, 1, mine: true)])
    }

    @Test func aFetchStartedAfterTheAnswerShowsGitHubsState() {
        let shown = overrides(answeredAt: t0 + 10)
            .apply(to: reactions([group(.thumbsUp, 0)]), fetchedAt: t0 + 11, now: t0 + 12)
        #expect(shown?.groups == [group(.thumbsUp, 0)])
        #expect(shown?.viewerHasReacted(.thumbsUp) == false)
    }

    @Test func anOlderFetchLandingLastBringsTheOverrideBack() {
        let o = overrides(answeredAt: t0 + 10)
        let github = reactions([group(.thumbsUp, 0)])
        #expect(o.apply(to: github, fetchedAt: t0 + 11, now: t0 + 12)?.shown.isEmpty == true)
        #expect(o.apply(to: github, fetchedAt: t0 + 9, now: t0 + 12)?.groups == [group(.thumbsUp, 1, mine: true)])
    }

    @Test func aNewClickAfterAnAnswerIsInForceAgain() {
        var o = overrides(answeredAt: t0 + 1)
        o.record(up, add: false, on: key, at: t0 + 2)
        let shown = o.apply(to: reactions([group(.thumbsUp, 1, mine: true)]), fetchedAt: t0 + 2, now: t0 + 3)
        #expect(shown?.groups == [group(.thumbsUp, 0)])
    }

    @Test func aFetchStampedExactlyAtTheAnswerKeepsTheOverride() {
        let shown = overrides(answeredAt: t0 + 10)
            .apply(to: reactions([group(.thumbsUp, 0)]), fetchedAt: t0 + 10, now: t0 + 12)
        #expect(shown?.groups == [group(.thumbsUp, 1, mine: true)])
    }

    @Test func aDetailWithoutFetchedAtRetiresNothing() {
        let shown = overrides(answeredAt: t0 + 10).apply(to: reactions([group(.thumbsUp, 0)]), fetchedAt: nil, now: t0 + 12)
        #expect(shown?.groups == [group(.thumbsUp, 1, mine: true)])
    }

    @Test func anOverrideLapsesAfterTheLifetime() {
        let github = reactions([group(.thumbsUp, 0)])
        #expect(overrides().apply(to: github, fetchedAt: nil, now: t0 + EditOverrides.lifetime - 1)?.shown.count == 1)
        #expect(overrides().apply(to: github, fetchedAt: nil, now: t0 + EditOverrides.lifetime) == github)
    }

    @Test func overridesOnOtherSubjectsLeaveThisOneAlone() {
        let other = reactions([group(.thumbsUp, 4)], id: "S2")
        #expect(overrides().apply(to: other, fetchedAt: nil, now: t0) == other)
        #expect(overrides().apply(to: nil, fetchedAt: nil, now: t0) == nil)
    }

    @Test func aClickPrunesLapsedEntriesAndDropRemovesOne() {
        var o = overrides()
        let eyes = ReactionTarget(subjectId: "S1", content: .eyes)
        o.record(eyes, add: true, on: key, at: t0 + EditOverrides.lifetime)
        #expect(o.wanted(up) == nil)
        #expect(o.wanted(eyes) == true)
        o.drop(eyes)
        #expect(o.isEmpty)
    }

    @Test func replacingReactionsReachesTheDescriptionACommentAndAReview() {
        let old = { (id: String) in reactions([group(.heart, 1)], id: id) }
        let fresh = { (id: String) in reactions([group(.heart, 2, mine: true)], id: id) }
        let stamp = t0
        let pr = PRDetail(
            key: key, body: "", checks: [],
            reviews: [Review(author: "bob", state: .approved, submittedAt: nil, id: "R", reactions: old("R"))],
            comments: [
                PullBullKit.Comment(id: "C", author: "a", body: "x", createdAt: t0, reactions: old("C")),
                PullBullKit.Comment(id: "D", author: "a", body: "x", createdAt: t0, reactions: old("D")),
            ],
            files: [], reactions: old("P"), fetchedAt: stamp)
        for id in ["P", "C", "R"] {
            let out = pr.replacingReactions(fresh(id))
            #expect(out.fetchedAt == stamp)
            #expect(out.reactions == (id == "P" ? fresh(id) : old("P")))
            #expect(out.comments[0].reactions == (id == "C" ? fresh(id) : old("C")))
            #expect(out.comments[1].reactions == old("D"))
            #expect(out.reviews[0].reactions == (id == "R" ? fresh(id) : old("R")))
        }
        #expect(pr.replacingReactions(fresh("X")).comments == pr.comments)

        let base = IssueDetail(
            key: key, issue: BoardIssue(key: key, title: "i", url: URL(string: "https://x/12")!, isOpen: true), body: "", commentTotal: 1,
            lastComments: [PullBullKit.Comment(id: "C", author: "a", body: "x", createdAt: t0, reactions: old("C"))],
            linkedPRs: [], reactions: old("P"), fetchedAt: stamp)
        for id in ["P", "C"] {
            let out = base.replacingReactions(fresh(id))
            #expect(out.fetchedAt == stamp)
            #expect(out.reactions == (id == "P" ? fresh(id) : old("P")))
            #expect(out.lastComments[0].reactions == (id == "C" ? fresh(id) : old("C")))
        }
        #expect(base.replacingReactions(fresh("X")) == base)
    }

    @Test func reactionsOfFindsTheDescriptionACommentAndAReview() {
        let on = { (id: String, count: Int) in reactions([group(.heart, count)], id: id) }
        let pr = PRDetail(
            key: key, body: "", checks: [],
            reviews: [Review(author: "bob", state: .approved, submittedAt: nil, id: "R", reactions: on("R", 3))],
            comments: [
                PullBullKit.Comment(id: "N", author: "a", body: "x", createdAt: t0, reactions: nil),
                PullBullKit.Comment(id: "C", author: "a", body: "x", createdAt: t0, reactions: on("C", 2)),
            ],
            files: [], reactions: on("P", 1), fetchedAt: t0)
        #expect(pr.reactions(of: "P") == on("P", 1))
        #expect(pr.reactions(of: "C") == on("C", 2))
        #expect(pr.reactions(of: "R") == on("R", 3))
        #expect(pr.reactions(of: "X") == nil)

        let issue = IssueDetail(
            key: key, issue: BoardIssue(key: key, title: "i", url: URL(string: "https://x/12")!, isOpen: true), body: "", commentTotal: 1,
            lastComments: [PullBullKit.Comment(id: "C", author: "a", body: "x", createdAt: t0, reactions: on("C", 2))],
            linkedPRs: [], reactions: on("P", 1), fetchedAt: t0)
        #expect(issue.reactions(of: "P") == on("P", 1))
        #expect(issue.reactions(of: "C") == on("C", 2))
        #expect(issue.reactions(of: "X") == nil)
    }
}
