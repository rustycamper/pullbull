import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
private let org = OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: [])

private func pr(
    _ n: Int, author: String = "alice", repo: String = "o/a", draft: Bool = false, ci: CIState = .success,
    reviews: [(String, ReviewState)] = [], requests: [Reviewer] = [], mergeable: Mergeable? = nil,
    created: Double = 10, updated: Double = 1, state: PRState = .open, closed: Double? = nil
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: n), title: "t\(n)", url: URL(string: "https://x/\(n)")!,
        author: author, authorAvatarURL: nil, state: state, isDraft: draft,
        createdAt: ago(created), updatedAt: ago(updated), closedAt: closed.map(ago),
        headRef: "h", baseRef: "main", ci: ci, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
        latestReviews: reviews.map { Review(author: $0.0, state: $0.1, submittedAt: ago(2)) },
        reviewRequests: requests, mergeable: mergeable)
}
private func requested(_ n: Int, author: String = "bob", repo: String = "o/a") -> PullRequest {
    pr(n, author: author, repo: repo, requests: [.user("me")])
}
private func approvedByMe(_ n: Int) -> PullRequest { pr(n, author: "bob", reviews: [("me", .approved)]) }

private func built(
    review: [PullRequest] = [], mine: [PullRequest] = [], team: [PullRequest] = [], closed: [PullRequest] = [],
    settings: AppSettings = AppSettings()
) -> BuiltTabs {
    TabBuilder.build(
        Snapshot(fetchedAt: now, org: org, reviewCandidates: review, mine: mine, team: team,
                 recentlyClosed: closed, boardIssues: []),
        settings: settings, now: now)
}
private func list(
    _ tabs: BuiltTabs, _ scope: PRScope, teamShown: Bool = true, settings: AppSettings = AppSettings()
) -> PRList {
    PRList.build(tabs, scope: scope, teamShown: teamShown, settings: settings, org: org, now: now)
}
/// "needsReview [1, 2]" per section, in display order.
private func shape(_ list: PRList) -> [String] {
    list.sections.map { "\($0.section.rawValue) \($0.contents.rows.map(\.id.number))" }
}

@Suite struct PRListTests {
    @Test func mineSplitsIntoYourPRsAndWaitingOnOthers() {
        #expect(PRSection.mine(pr(1, author: "me", reviews: [("bob", .approved)])) == .yourPRs)
        #expect(PRSection.mine(pr(2, author: "me", ci: .pending, reviews: [("bob", .changesRequested)])) == .yourPRs)
        #expect(PRSection.mine(pr(3, author: "me", ci: .failure)) == .yourPRs)
        #expect(PRSection.mine(pr(4, author: "me", mergeable: .conflicting)) == .yourPRs)
        #expect(PRSection.mine(pr(5, author: "me", draft: true, ci: .pending)) == .yourPRs)
        #expect(PRSection.mine(pr(6, author: "me", requests: [.user("bob")])) == .waiting)
        #expect(PRSection.mine(pr(7, author: "me", ci: .pending, reviews: [("bob", .approved)])) == .waiting)
    }

    @Test func aCancelledOnlyRunLandsInYourPRs() {
        // GitHub's rollup reads a PR whose only problem is a cancelled run as FAILURE.
        let tabs = built(mine: [pr(8, author: "me", ci: .failure, reviews: [("bob", .approved)])])
        #expect(shape(list(tabs, .all)) == ["yourPRs [8]"])
    }

    @Test func theSplitHasNoOverlapAndKeepsMinesOrder() {
        let tabs = built(mine: [
            pr(1, author: "me", ci: .failure, updated: 3), pr(2, author: "me", updated: 1),
            pr(3, author: "me", draft: true, updated: 2),
        ])
        #expect(tabs.yourPRs.rows.map(\.id.number) == [3, 1])
        #expect(tabs.waitingOnOthers.rows.map(\.id.number) == [2])
    }

    @Test func aTeammatesPRRequestingMyReviewShowsOnceInNeedsYourReview() {
        let both = requested(1)
        let tabs = built(review: [both], team: [both, pr(2, author: "carol")])
        #expect(shape(list(tabs, .all)) == ["needsReview [1]", "team [2]"])
        #expect(tabs.count(of: .team) == 1)
        #expect(tabs.team.count == 2)
        #expect(tabs.badgeCount(.all) == 2)
    }

    @Test func aDimmedApprovedRowLeavesTeamAndShowsWithACountOfZero() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        let tabs = built(review: [approvedByMe(1)], team: [approvedByMe(1)], settings: s)
        let all = list(tabs, .all, settings: s)
        #expect(shape(all) == ["needsReview [1]"])
        #expect(all.sections.first?.count == 0)
        #expect(tabs.count(of: .review) == 0 && tabs.count(of: .team) == 0)
        #expect(tabs.badgeCount(.all) == 1)
    }

    @Test func withHideApprovedOnAnApprovedPRStaysInTeam() {
        let tabs = built(review: [approvedByMe(1)], team: [approvedByMe(1)])
        #expect(shape(list(tabs, .all)) == ["team [1]"])
    }

    @Test func eachScopeShowsItsSections() {
        let tabs = built(
            review: [requested(1)], mine: [pr(2, author: "me", ci: .failure), pr(3, author: "me")],
            team: [pr(4, author: "carol")], closed: [pr(5, author: "me", state: .merged, closed: 1)])
        #expect(list(tabs, .all).sections.map(\.section) == [.needsReview, .yourPRs, .waiting, .recentlyClosed, .team])
        #expect(list(tabs, .review).sections.map(\.section) == [.needsReview])
        #expect(list(tabs, .mine).sections.map(\.section) == [.yourPRs, .waiting, .recentlyClosed])
        #expect(list(tabs, .team).sections.map(\.section) == [.team])
        #expect(PRScope.allCases.filter(\.showsSectionHeaders) == [.all, .mine])
    }

    @Test func teamIsLeftOutWithoutAnOrg() {
        let tabs = built(mine: [pr(2, author: "me")], team: [pr(4)])
        #expect(shape(list(tabs, .all, teamShown: false)) == ["waiting [2]"])
    }

    @Test func nothingNeedsYouWhenNoCountedReviewAndNoYourPRs() {
        var s = AppSettings()
        s.hideApprovedByMe = false
        #expect(list(built(review: [approvedByMe(1)], mine: [pr(2, author: "me")], settings: s), .all, settings: s).nothingNeedsYou)
        #expect(list(built(team: [pr(4)]), .all).nothingNeedsYou)
        #expect(!list(built(review: [requested(1)], mine: [pr(2, author: "me")]), .all).nothingNeedsYou)
        #expect(!list(built(mine: [pr(2, author: "me", draft: true)]), .all).nothingNeedsYou)
        #expect(!list(built(), .all).nothingNeedsYou)
        #expect(!list(built(mine: [pr(2, author: "me")]), .mine).nothingNeedsYou)
    }

    @Test func chipCountsIgnoreTheFocusAndMineSumsItsSections() {
        let tabs = built(
            review: [requested(1), requested(2, repo: "o/b")],
            mine: [pr(3, author: "me", ci: .failure), pr(4, author: "me"), pr(5, author: "me", repo: "o/b")],
            team: [pr(6, repo: "o/b")])
        #expect(tabs.count(of: .all) == nil)
        #expect(tabs.count(of: .review) == 2)
        #expect(tabs.count(of: .mine) == 3)
        #expect(tabs.count(of: .mine) == tabs.yourPRs.count + tabs.waitingOnOthers.count)
        #expect(tabs.count(of: .team) == 1)
        let focused = ListFocus(repo: RepoFocus(repo: "o/a"), time: nil).scope(list(tabs, .all))
        #expect(shape(focused.list) == ["needsReview [1]", "yourPRs [3]", "waiting [4]"])
        #expect(focused.hiddenCount == 3)
        #expect(tabs.count(of: .review) == 2)
    }

    @Test func allSortsWithinSectionsByItsOwnSort() {
        var s = AppSettings()
        s.setSort(.oldestFirst, for: PRScope.all)
        let tabs = built(
            mine: [pr(1, author: "me", created: 1, updated: 1), pr(2, author: "me", created: 9, updated: 5)],
            settings: s)
        #expect(shape(list(tabs, .all, settings: s)) == ["waiting [2, 1]"])
        #expect(shape(list(tabs, .mine, settings: s)) == ["waiting [1, 2]"])
    }
}
