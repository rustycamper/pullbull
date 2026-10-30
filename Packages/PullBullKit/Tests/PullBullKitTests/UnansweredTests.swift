import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, author: String = "me", state: PRState = .open, last: String? = nil, bot: Bool? = nil,
    reviews: [Review] = []
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author,
        authorAvatarURL: nil, state: state, isDraft: false, createdAt: t0, updatedAt: t0,
        closedAt: state == .open ? nil : t0, headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil,
        commentCount: last == nil ? 0 : 1, lastCommentAuthor: last, latestReviews: reviews, reviewRequests: [],
        lastCommentByBot: bot)
}

private func issue(
    _ number: Int, author: String? = "frank", assignees: [String] = [], isOpen: Bool = true,
    last: String? = nil, bot: Bool? = nil, updatedAt: Date = t0, status: String? = nil
) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: isOpen, author: author,
        updatedAt: updatedAt, lastCommentAuthor: last, lastCommentByBot: bot,
        assignees: assignees.map { Assignee(login: $0, avatarURL: nil) },
        status: status.map { BoardStatusValue(optionId: $0, name: $0) })
}

private func matches(_ raw: String, _ pr: PullRequest) -> Bool {
    SearchQuery.parse(raw).matches(pr, viewer: "me", now: t0, calendar: .current)
}

private func matches(_ raw: String, _ issue: BoardIssue) -> Bool {
    SearchQuery.parse(raw).matches(issue, viewer: "me", now: t0, calendar: .current)
}

@Suite struct UnansweredTests {
    @Test func botRule() {
        #expect(LastComment.isBot(login: "dependabot", byBot: true))
        #expect(LastComment.isBot(login: "renovate[bot]", byBot: nil))
        #expect(!LastComment.isBot(login: "frank", byBot: false))
        #expect(!LastComment.isBot(login: nil, byBot: nil))
    }

    @Test func unansweredPR() {
        #expect(matches("is:unanswered", pr(1, last: "frank")))
        #expect(!matches("is:unanswered", pr(2, last: "ME")))
        #expect(!matches("is:unanswered", pr(3, last: "dependabot", bot: true)))
        #expect(!matches("is:unanswered", pr(4, last: "renovate[bot]")))
        #expect(!matches("is:unanswered", pr(5)))
        #expect(!matches("is:unanswered", pr(6, state: .merged, last: "frank")))
        let mine = Review(author: "me", state: .approved, submittedAt: t0)
        #expect(!matches("is:unanswered", pr(7, author: "frank", last: "grace", reviews: [mine])))
        #expect(matches("is:unanswered", pr(8, author: "Me", last: "frank")))
    }

    @Test func negatedPR() {
        #expect(!matches("-is:unanswered", pr(1, last: "frank")))
        #expect(matches("-is:unanswered", pr(2, last: "me")))
        #expect(matches("-is:unanswered", pr(3)))
    }

    @Test func unansweredIssue() {
        #expect(matches("is:unanswered", issue(1, author: "frank", assignees: ["me"], last: "frank")))
        #expect(matches("is:unanswered", issue(2, author: "me", last: "frank")))
        #expect(!matches("is:unanswered", issue(3, author: "me", isOpen: false, last: "frank")))
        #expect(!matches("is:unanswered", issue(4, author: "frank", last: "grace")))
        #expect(!matches("is:unanswered", issue(5, author: "me", last: "me")))
        #expect(!matches("is:unanswered", issue(6, author: "me", last: "renovate[bot]")))
        #expect(!matches("is:unanswered", issue(7, author: "me", last: "x", bot: true)))
        #expect(!matches("is:unanswered", issue(8, author: "me")))
    }

    @Test func negatedIssue() {
        #expect(!matches("-is:unanswered", issue(1, author: "me", last: "frank")))
        #expect(matches("-is:unanswered", issue(2, author: "frank", last: "grace")))
        #expect(matches("-is:unanswered", issue(3, author: "me", last: "me")))
    }

    @Test func otherPROnlyConditionsStillSkipIssues() {
        let i = issue(1, author: "me", last: "frank")
        #expect(!matches("is:ready", i))
        #expect(!matches("-is:ready", i))
        #expect(!matches("is:unanswered is:ready", i))
        #expect(!matches("review:none", i))
    }

    @Test func unansweredIsNotPROnly() throws {
        #expect(try #require(SearchQuery.parse("is:unanswered").filter).prOnly == false)
    }

    @Test func localOnly() {
        #expect(SearchQuery.parse("is:unanswered").isLocalOnly)
        #expect(SearchQuery.parse("-is:unanswered fix").isLocalOnly)
        #expect(!SearchQuery.parse("is:ready").isLocalOnly)
        #expect(!SearchQuery.parse("fix").isLocalOnly)
    }
}

/// Fails the test on any request.
private struct NoRequestTransport: GraphQLTransport {
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        Issue.record("unexpected request: \(String(decoding: body, as: UTF8.self))")
        throw APIError.network("no requests expected")
    }
}

private let engine = SearchEngine(api: GitHubAPI(transport: NoRequestTransport(), auth: StaticTokenSource("test-token")))

private func snapshot(board: [BoardIssue] = [], assigned: [BoardIssue]? = nil, mine: [PullRequest] = []) -> Snapshot {
    Snapshot(
        fetchedAt: t0,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: [], mine: mine, team: [], recentlyClosed: [], boardIssues: board,
        boardProject: 3, boardTitle: nil, boardError: nil,
        assignedIssues: assigned, createdIssues: nil, boardStatusOptions: [StatusOption(id: "Todo", name: "Todo")])
}

@Suite struct UnansweredEngineTests {
    @Test func boardCopyKeepsComment() throws {
        let board = issue(1, author: "me", updatedAt: t0, status: "Todo")
        let assigned = issue(1, author: "me", last: "frank", updatedAt: t0)
        let snap = snapshot(board: [board], assigned: [assigned])
        let kept = try #require(SearchEngine.cachedIssues(snap).first)
        #expect(kept.status?.name == "Todo")
        #expect(kept.lastCommentAuthor == "frank")
        #expect(engine.local(SearchQuery.parse("is:unanswered"), in: snap).issues.map(\.key.number) == [1])
    }

    @Test func boardOnlyIssueOfMineIsNotAnswered() {
        let snap = snapshot(board: [issue(2, author: "frank", last: "grace")])
        #expect(engine.local(SearchQuery.parse("is:unanswered"), in: snap).issues.isEmpty)
    }

    @Test func finishesWithoutARequest() async {
        let snap = snapshot(assigned: [issue(1, author: "me", last: "frank")], mine: [pr(2, last: "frank")])
        for text in ["is:unanswered", "-is:unanswered fix"] {
            var all: [SearchResults] = []
            for await r in engine.results(SearchQuery.parse(text), snap: snap) { all.append(r) }
            #expect(all.count == 1)
            #expect(all.last?.phase == .done)
        }
    }
}
