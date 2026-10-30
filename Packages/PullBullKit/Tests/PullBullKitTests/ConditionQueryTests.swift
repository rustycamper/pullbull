import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_793_000_000)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, state: PRState = .open, isDraft: Bool = false, ci: CIState = .none,
    mergeable: Mergeable? = nil, reviews: [ReviewState] = []
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "someone",
        authorAvatarURL: nil, state: state, isDraft: isDraft, createdAt: now, updatedAt: now,
        closedAt: state == .open ? nil : now, headRef: "a", baseRef: "main", ci: ci, headCommitDate: nil,
        commentCount: 0, lastCommentAuthor: nil,
        latestReviews: reviews.enumerated().map { Review(author: "rev\($0.offset)", state: $0.element, submittedAt: now) },
        reviewRequests: [], mergeable: mergeable)
}

private func issue(_ number: Int) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: true, updatedAt: now, status: nil)
}

private func matches(_ raw: String, _ pr: PullRequest) -> Bool {
    SearchQuery.parse(raw).matches(pr, viewer: "me", now: now, calendar: .current)
}

private func matches(_ raw: String, _ issue: BoardIssue) -> Bool {
    SearchQuery.parse(raw).matches(issue, viewer: "me", now: now, calendar: .current)
}

private func prQuery(_ raw: String) throws -> String {
    let filter = try #require(SearchQuery.parse(raw).filter)
    return SearchEngine.remoteQuery(kind: "pr", scope: .org("initech"), filter: filter, now: now, calendar: .current)
}

/// Records every request body; issue searches (`is:issue`) get `issueReply`, the rest an empty page.
private final class RecordingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    var issueBodies: [String] { lock.withLock { sent.filter { $0.contains("is:issue") } } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let text = String(decoding: body, as: UTF8.self)
        lock.withLock { sent.append(text) }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let page = #"{"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":false},"nodes":[]}}}"#
        return (Data(page.utf8), response)
    }
}

private func snapshot() -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [])
}

private func issueSearches(_ raw: String) async -> Int {
    let transport = RecordingTransport()
    let engine = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
    for await _ in engine.results(.parse(raw), snap: snapshot()) {}
    return transport.issueBodies.count
}

private func open(_ text: String) -> SearchCompletion? {
    SearchCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil, people: .empty, labels: .empty)
}

@Suite struct ConditionQueryTests {
    @Test func conditionsMatch() {
        let ready = pr(1, ci: .success, reviews: [.approved])
        #expect(matches("is:ready", ready))
        #expect(!matches("is:ready", pr(2, ci: .failure, reviews: [.approved])))
        #expect(!matches("is:ready", pr(3, ci: .success, reviews: [.approved, .changesRequested])))
        #expect(!matches("is:ready", pr(4, isDraft: true, ci: .success, reviews: [.approved])))
        #expect(matches("is:conflict", pr(5, mergeable: .conflicting)))
        #expect(!matches("is:conflict", pr(6, mergeable: .unknown)))
        #expect(!matches("is:conflict", pr(7, mergeable: .mergeable)))
        #expect(matches("is:failing", pr(8, ci: .failure)))
        #expect(!matches("is:failing", pr(9, ci: .pending)))
        #expect(!matches("is:failing", pr(10, ci: .none)))
        #expect(matches("is:approved", pr(11, reviews: [.commented, .approved])))
        #expect(matches("is:approved", pr(12, reviews: [.approved, .changesRequested])))
        #expect(!matches("is:approved", pr(13, reviews: [.commented])))
    }

    @Test func reviewsMatch() {
        #expect(matches("review:changes", pr(1, reviews: [.approved, .changesRequested])))
        #expect(!matches("review:changes", pr(2, reviews: [.approved])))
        #expect(matches("review:none", pr(3)))
        #expect(!matches("review:none", pr(4, reviews: [.commented])))
        #expect(!matches("review:none", pr(5, reviews: [.approved])))
    }

    @Test func negatedLocalMatch() {
        #expect(!matches("-is:failing", pr(1, ci: .failure)))
        #expect(matches("-is:failing", pr(2, ci: .success)))
        #expect(matches("-review:none", pr(3, reviews: [.commented])))
        #expect(!matches("-review:none", pr(4)))
        #expect(matches("-review:changes", pr(5, reviews: [.approved])))
    }

    @Test func serverForms() throws {
        let q = try prQuery("is:failing is:approved review:changes review:none is:ready is:conflict fix")
        #expect(q.contains("status:failure"))
        #expect(q.contains("review:none"))
        #expect(!q.contains("review:approved"))
        #expect(!q.contains("changes_requested"))
        #expect(!q.contains("is:ready"))
        #expect(!q.contains("is:conflict"))
        #expect(q == #"org:initech is:pr status:failure review:none in:title "fix" sort:updated-desc"#)
    }

    /// GitHub's `status:failure` and `review:none` aren't known to match the local filter exactly, so their
    /// `-` forms could drop rows it keeps: no negated condition or review is sent.
    @Test func negatedServerForms() throws {
        let q = try prQuery("-is:failing -review:none -is:approved -review:changes -is:ready -is:conflict fix")
        #expect(q == #"org:initech is:pr in:title "fix" sort:updated-desc"#)
    }

    @Test func prOnlySkipsIssues() async {
        for raw in ["is:conflict", "-is:failing", "review:none", "is:failing", "-review:changes"] {
            #expect(matches(raw, issue(1)) == false, Comment(rawValue: raw))
            #expect(SearchQuery.parse(raw).filter?.prOnly == true, Comment(rawValue: raw))
        }
        #expect(await issueSearches("fix") == 1)
        for raw in ["is:conflict fix", "-is:failing fix", "review:none", "is:failing"] {
            #expect(await issueSearches(raw) == 0, Comment(rawValue: raw))
        }
    }

    @Test func unansweredIsNotPRsOnly() throws {
        #expect(SearchQuery.parse("is:unanswered").filter?.prOnly == false)
        #expect(try #require(SearchQuery.parse("is:unanswered").filter).include.conditions == [.unanswered])
    }

    @Test func unknownValuesAreWords() {
        #expect(SearchQuery.parse("is:readyy") == .text(["is:readyy"]))
        #expect(SearchQuery.parse("review:maybe") == .text(["review:maybe"]))
        #expect(SearchQuery.parse("-review:maybe") == .text(["-review:maybe"]))
    }

    @Test func parsesBothSides() throws {
        let filter = try #require(SearchQuery.parse("is:open is:ready review:none -is:conflict -review:changes").filter)
        #expect(filter.include.states == [.open])
        #expect(filter.include.conditions == [.ready])
        #expect(filter.include.reviews == [.none])
        #expect(filter.exclude.conditions == [.conflict])
        #expect(filter.exclude.reviews == [.changes])
        #expect(filter.tokens == ["is:open", "is:ready", "review:none", "-is:conflict", "-review:changes"])
    }

    @Test func cacheKeyTellsConditionsApart() {
        let a = SearchCache.Query(.parse("fix is:ready"), now: now, calendar: .current)
        let b = SearchCache.Query(.parse("fix is:conflict"), now: now, calendar: .current)
        let c = SearchCache.Query(.parse("fix review:none"), now: now, calendar: .current)
        #expect(a != b && a != c && b != c)
    }

    @Test func contextNamesThem() throws {
        let filter = try #require(SearchQuery.parse("is:failing review:none -is:approved").filter)
        #expect(SearchContext.filterDescription(filter)
            == "Filtered by checks failed, review: no reviews, excluding has an approval")
    }
}

@Suite struct ReviewCompletionTests {
    private func review(_ text: String) -> ReviewCompletion? {
        ReviewCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil)
    }

    @Test func isListsStatesThenConditions() throws {
        guard case .states(let list) = try #require(open("is:")) else { Issue.record("not a state list"); return }
        #expect(list.candidates.map(\.id)
            == ["open", "closed", "merged", "draft", "ready", "conflict", "failing", "approved", "unanswered"])
        #expect(list.candidates.map(\.insertText).last == "is:unanswered")
    }

    @Test func isPrefix() throws {
        guard case .states(let list) = try #require(open("is:a")) else { Issue.record("not a state list"); return }
        #expect(list.candidates.map(\.value) == [.condition(.approved)])
        guard case .states(let c) = try #require(open("is:c")) else { Issue.record("not a state list"); return }
        #expect(c.candidates.map(\.id) == ["closed", "conflict"])
    }

    @Test func reviewList() throws {
        let list = try #require(review("review:"))
        #expect(list.candidates.map(\.review) == [.changes, .none])
        #expect(list.token == PendingToken(start: 0, end: 7, prefix: "", kind: .review))
        #expect(try #require(list.accepted(in: "review:")).text == "review:changes ")
        #expect(try #require(review("fix REVIEW:N")).candidates.map(\.review) == [.none])
        #expect(try #require(review("review:x")).candidates.isEmpty)
    }

    @Test func negatedReviewCompletes() throws {
        let list = try #require(review("-review:n"))
        #expect(list.candidates.map(\.review) == [.none])
        #expect(try #require(list.accepted(in: "-review:n")).text == "-review:none ")
    }

    @Test func searchCompletionOpensReviews() throws {
        guard case .reviews = try #require(open("review:c")) else { Issue.record("not a review list"); return }
        #expect(PendingToken.startsToken(at: 4, in: "fix review:", kind: .review))
        #expect(!PendingToken.startsToken(at: 4, in: "fix review:", kind: .state))
    }

    @Test func fieldStateExposesIt() {
        var state = SearchFieldState()
        state.edit("review:", caret: 7, people: .empty)
        #expect(state.reviewCompletion?.candidates.count == 2)
        #expect(state.stateCompletion == nil)
    }

    @Test func speech() throws {
        let all = try #require(review("review:"))
        #expect(CompletionSpeech.opened(all) == "2 review filters. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.selected(all.moved(by: 1)) == "none, no reviews, 2 of 2")
        #expect(CompletionSpeech.completed(ReviewCandidate(review: .changes))
            == "Showing pull requests: changes requested")
        #expect(CompletionSpeech.completed(StateCandidate(value: .condition(.ready)))
            == "Showing pull requests: ready to merge")
        #expect(CompletionSpeech.label(StateCandidate(value: .condition(.failing))) == "failing, checks failed")
        #expect(CompletionSpeech.change(from: nil, to: open("review:"), loaded: false)
            == "2 review filters. Up and down arrows to choose, Return to complete.")
    }
}
