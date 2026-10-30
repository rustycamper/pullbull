import Foundation
import Testing
@testable import PullBullKit

private let zone = TimeZone(identifier: "America/New_York")!
private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c
}()

private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Friday 2026-10-30, mid-afternoon in New York.
private let now = at(2026, 10, 30, 15)
private let repo = "initech/gadgets"

private func pr(
    _ number: Int, author: String = "someone", state: PRState = .open, isDraft: Bool = false,
    updatedAt: Date = now, labels: [String] = [], reviews: [Review] = [], lastCommentAuthor: String? = nil
) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Fix",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: author,
        authorAvatarURL: nil, state: state, isDraft: isDraft, createdAt: updatedAt, updatedAt: updatedAt,
        closedAt: state == .open ? nil : updatedAt, headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil,
        commentCount: lastCommentAuthor == nil ? 0 : 1, lastCommentAuthor: lastCommentAuthor, latestReviews: reviews,
        reviewRequests: [], labels: labels)
}

private func issue(_ number: Int, title: String = "Fix", status: String? = nil) -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: title,
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: true, updatedAt: now,
        status: status.map { BoardStatusValue(optionId: "opt-\($0)", name: $0) })
}

private func matches(_ raw: String, _ pr: PullRequest) -> Bool {
    SearchQuery.parse(raw).matches(pr, viewer: "me", now: now, calendar: calendar)
}

private func matches(_ raw: String, _ issue: BoardIssue) -> Bool {
    SearchQuery.parse(raw).matches(issue, viewer: "me", now: now, calendar: calendar)
}

private func prQuery(_ raw: String) throws -> String {
    let filter = try #require(SearchQuery.parse(raw).filter)
    return SearchEngine.remoteQuery(kind: "pr", scope: .org("initech"), filter: filter, now: now, calendar: calendar)
}

/// Records every request body; issue searches (`is:issue`) get `issueReply`, the rest an empty page.
private final class RecordingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [String] = []
    private let issueReply: String
    init(issueReply: String) { self.issueReply = issueReply }
    var issueBodies: [String] { lock.withLock { sent.filter { $0.contains("is:issue") } } }
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let text = String(decoding: body, as: UTF8.self)
        lock.withLock { sent.append(text) }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data((text.contains("is:issue") ? issueReply : searchResponse([])).utf8), response)
    }
}

private func searchResponse(_ nodes: [String]) -> String {
    """
    {"data":{"search":{"pageInfo":{"endCursor":"c","hasNextPage":false},"nodes":[\(nodes.joined(separator: ","))]}}}
    """
}

private func issueNode(_ number: Int, title: String) -> String {
    """
    {"number":\(number),"title":"\(title)","url":"https://github.com/\(repo)/issues/\(number)",\
    "state":"OPEN","updatedAt":"2026-10-25T10:00:00Z","repository":{"nameWithOwner":"\(repo)"}}
    """
}

private func snapshot() -> Snapshot {
    Snapshot(
        fetchedAt: now,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [])
}

@Suite struct NegationQueryTests {
    @Test func parsesNegatedQualifiers() throws {
        let q = SearchQuery.parse("-@bot -~wontfix -label:dup -is:draft -status:done -updated:1w fix")
        let filter = try #require(q.filter)
        #expect(filter.exclude.logins == ["bot"])
        #expect(filter.exclude.labels == ["wontfix", "dup"])
        #expect(filter.exclude.states == [.draft])
        #expect(filter.exclude.statuses == [BoardStatusFilter(name: "done", exact: false)])
        #expect(filter.exclude.updated == [.step(.week)])
        #expect(filter.words == ["fix"])
        #expect(filter.include.isEmpty)
    }

    @Test func bareDashWordStaysWord() {
        #expect(SearchQuery.parse("-flaky") == .text(["-flaky"]))
    }

    @Test func pendingNegatedTokenLeavesNoDash() throws {
        let raw = "fix -@an"
        let token = try #require(PendingToken.at(caret: 8, in: raw))
        let pending = try #require(token.range(in: raw))
        #expect(raw[pending] == "@an")
        #expect(SearchQuery.parse(raw, excluding: pending) == .text(["fix"]))
    }

    @Test func pendingTokenStartsAfterDash() throws {
        let token = try #require(PendingToken.at(caret: 8, in: "fix -@an"))
        #expect(token.start == 5)
        #expect(token.kind == .person)
        let completion = PersonCompletion(
            token: token, candidates: [PersonCandidate(login: "ann", avatarURL: nil, isMember: true, isViewer: false, openCount: 0)], selection: 0)
        #expect(completion.accepted(in: "fix -@an")?.text == "fix -@ann ")
    }

    @Test func startsTokenAfterDash() {
        #expect(PendingToken.startsToken(at: 1, in: "-@"))
        #expect(!PendingToken.startsToken(at: 4, in: "a-b@"))
        #expect(!PendingToken.startsToken(at: 2, in: "a-@"))
        #expect(PendingToken.startsToken(at: 5, in: "fix -~bu", kind: .label))
    }

    @Test func localInvertsMatch() {
        let authored = pr(1, author: "alice")
        let reviewed = pr(2, reviews: [Review(author: "Alice", state: .approved, submittedAt: now)])
        let commented = pr(3, lastCommentAuthor: "alice")
        #expect(!matches("-@alice", authored))
        #expect(!matches("-@alice", reviewed))
        #expect(matches("-@alice", commented))

        #expect(!matches("-~bug", pr(4, labels: ["BUG"])))
        #expect(matches("-~bug", pr(5, labels: ["ui"])))

        #expect(matches("-is:draft", pr(6)))
        #expect(matches("-is:draft", pr(7, state: .closed)))
        #expect(!matches("-is:draft", pr(8, isDraft: true)))

        #expect(matches("-status:done", pr(9)))
        #expect(matches("-status:done", issue(10)))
        #expect(!matches("-status:done", issue(11, status: "Done")))
        #expect(matches("-status:done", issue(12, status: "Todo")))
    }

    @Test func negatedUpdatedInverts() {
        let lateYesterday = pr(1, updatedAt: at(2026, 10, 29, 23, 59))
        let midnight = pr(2, updatedAt: at(2026, 10, 30, 0, 0))
        #expect(matches("-updated:today", lateYesterday))
        #expect(!matches("-updated:today", midnight))
    }

    @Test func negatedRawUpdatedMatchesNothingLocally() {
        #expect(!matches("-updated:soon", pr(1)))
    }

    @Test func contradictionMatchesNothing() {
        #expect(!matches("@ann -@ann", pr(1, author: "ann")))
        #expect(!matches("@ann -@ann", pr(2)))
        #expect(!matches("@ann -@ann", issue(3)))
    }

    @Test func negatedPersonSendsAuthorOnly() throws {
        let q = try prQuery("-@alice")
        #expect(q.contains("-author:alice"))
        #expect(!q.contains("involves"))
        #expect(try prQuery("-@me").contains("-author:@me"))
    }

    @Test func negatedServerForms() throws {
        let q = try prQuery(#"-~"good first" -is:draft -updated:3d"#)
        #expect(q.contains(#"-label:"good first""#))
        #expect(q.contains("-is:draft"))
        #expect(q.contains("-updated:>=2026-10-28T04:00:00Z"))
        #expect(q.hasSuffix(" sort:updated-desc"))
    }

    @Test func negationsFollowThePositiveParts() throws {
        #expect(try prQuery("@ann -@bot fix")
            == #"org:initech is:pr involves:ann in:title "fix" -author:bot sort:updated-desc"#)
    }

    @Test func negatedStatusStaysLocal() throws {
        let q = SearchQuery.parse("-status:done fix")
        let sent = try prQuery("-status:done fix")
        #expect(!sent.contains("status:"))
        #expect(!q.isLocalOnly)
        #expect(SearchQuery.parse("status:done").isLocalOnly)
    }

    @Test func negatedMergedStillSearchesIssues() async throws {
        let transport = RecordingTransport(issueReply: searchResponse([issueNode(31, title: "Fix the pool")]))
        let engine = SearchEngine(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")))
        var last: SearchResults?
        for await value in engine.results(.parse("-is:merged"), snap: snapshot()) { last = value }
        #expect(transport.issueBodies.count == 1)
        #expect(transport.issueBodies.first?.contains("-is:merged") == true)
        #expect(try #require(last).issues.map(\.key.number) == [31])
    }

    @Test func tokensOrder() {
        #expect(SearchQuery.parse("@ann ~bug -@bot -~wontfix").filter?.tokens == ["@ann", "~bug", "-@bot", "-~wontfix"])
    }

    @Test func compatConstructor() {
        #expect(SearchQuery.filtered(logins: ["a"], labels: [], words: [])
            == .filtered(SearchFilter(include: SearchTerms(logins: ["a"]), exclude: SearchTerms(), words: [])))
    }

    @Test func emptyMessageNamesTheExclusion() {
        let done = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(done.emptyMessage(org: "acme", query: .parse("-@bot"), mode: .pullRequests)
            == "No pull requests with -@bot")
    }
}
