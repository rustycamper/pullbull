import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
private let repo = "initech/gadgets"

private let todo = StatusOption(id: "t", name: "Todo")
private let inProgress = StatusOption(id: "p", name: "In progress")
private let inReview = StatusOption(id: "r", name: "In review")
private let done = StatusOption(id: "d", name: "Done")
private let notDone = StatusOption(id: "n", name: "Not done")
private let options = [todo, inProgress, inReview, done, notDone]

private func issue(_ number: Int, status: StatusOption? = nil, isOpen: Bool = true, title: String = "Issue") -> BoardIssue {
    BoardIssue(
        key: PRKey(repo: repo, number: number), title: title,
        url: URL(string: "https://github.com/\(repo)/issues/\(number)")!, isOpen: isOpen, updatedAt: t0,
        status: status.map { BoardStatusValue(optionId: $0.id, name: $0.name) })
}

private func pr(_ number: Int) -> PullRequest {
    PullRequest(
        key: PRKey(repo: repo, number: number), title: "Issue",
        url: URL(string: "https://github.com/\(repo)/pull/\(number)")!, author: "someone",
        authorAvatarURL: nil, state: .open, isDraft: false, createdAt: t0, updatedAt: t0, closedAt: nil,
        headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func snapshot(
    board: [BoardIssue] = [], assigned: [BoardIssue]? = nil, review: [PullRequest] = [],
    statusOptions: [StatusOption]? = options, boardProject: Int? = 3
) -> Snapshot {
    Snapshot(
        fetchedAt: t0,
        org: OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: ["gadgets"]),
        reviewCandidates: review, mine: [], team: [], recentlyClosed: [], boardIssues: board,
        boardProject: boardProject, boardTitle: nil, boardError: nil,
        assignedIssues: assigned, createdIssues: nil, boardStatusOptions: statusOptions)
}

/// Fails the test on any request: a `status:` search never asks GitHub.
private struct NoRequestTransport: GraphQLTransport {
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        Issue.record("unexpected request: \(String(decoding: body, as: UTF8.self))")
        throw APIError.network("no requests expected")
    }
}

private let engine = SearchEngine(api: GitHubAPI(transport: NoRequestTransport(), auth: StaticTokenSource("test-token")))

private func filter(_ name: String, exact: Bool = false) -> BoardStatusFilter {
    BoardStatusFilter(name: name, exact: exact)
}

@Suite struct StatusQueryTests {
    @Test func partAndExact() {
        #expect(SearchQuery.parse("status:prog")
            == .filtered(logins: [], labels: [], words: [], statuses: [filter("prog")]))
        #expect(SearchQuery.parse(#"status:"In progress""#).statuses == [filter("In progress", exact: true)])
        #expect(SearchQuery.parse(#"STATUS:"Done""#).statuses == [filter("Done", exact: true)])
    }

    @Test func andsWithEverythingElse() {
        #expect(SearchQuery.parse(#"@alice ~bug is:open status:"In review" login"#)
            == .filtered(
                logins: ["alice"], labels: ["bug"], words: ["login"], states: [.open],
                statuses: [filter("In review", exact: true)]))
    }

    @Test func duplicatesCollapseIgnoringCase() {
        #expect(SearchQuery.parse("status:prog STATUS:PROG").statuses == [filter("prog")])
        #expect(SearchQuery.parse(#"status:done status:"done""#).statuses
            == [filter("done"), filter("done", exact: true)])
    }

    @Test func bareOrEmptyIsDropped() {
        #expect(SearchQuery.parse("status:") == .empty)
        #expect(SearchQuery.parse(#"login status:"""#) == .text(["login"]))
    }

    @Test func insideAWordIsAWord() {
        #expect(SearchQuery.parse("mystatus:done") == .text(["mystatus:done"]))
    }

    @Test func openQuoteEndsBeforeTheNextToken() {
        #expect(SearchQuery.parse(#"status:"In prog is:open"#)
            == .filtered(logins: [], labels: [], words: [], states: [.open], statuses: [filter("In prog", exact: true)]))
        #expect(SearchQuery.parse(#"~"good first status:done"#)
            == .filtered(logins: [], labels: ["good first"], words: [], statuses: [filter("done")]))
    }

    @Test func pendingStatusExcluded() {
        let text = "login status:pr"
        #expect(SearchQuery.parse(text, excluding: text.range(of: "status:pr")) == .text(["login"]))
    }

    @Test func tokens() {
        #expect(filter("prog").token == "status:prog")
        #expect(filter("Done", exact: true).token == #"status:"Done""#)
        #expect(SearchQuery.tokenList(logins: ["a"], labels: [], states: [.open], statuses: [filter("prog")])
            == "@a, is:open and status:prog")
    }

    @Test func filterMatching() {
        #expect(filter("prog").matches("In progress"))
        #expect(filter("PROG").matches("In progress"))
        #expect(!filter("prog").matches(nil))
        #expect(filter("done", exact: true).matches("Done"))
        #expect(!filter("done", exact: true).matches("Not done"))
        #expect(filter("done").matches("Not done"))
    }

    @Test func emptyMessageAndContext() {
        let finished = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(finished.emptyMessage(org: "o", query: SearchQuery.parse(#"status:"In review""#), mode: .issues)
            == #"No issues with status:"In review""#)
        #expect(SearchContext.text(
            logins: [], statuses: [filter("prog")], words: ["fix"], org: "acme", startedOnTab: nil)
            == "status:prog · “fix” in all of acme")
        #expect(SearchContext.accessibilityLabel(
            logins: [], statuses: [filter("In review", exact: true)], words: [], org: "acme")
            == "Filtered by Status In review, in all of acme")
        #expect(SearchContext.accessibilityLabel(
            logins: [], statuses: [filter("prog"), filter("Done", exact: true)], words: [], org: "acme")
            == "Filtered by Status containing prog and Status Done, in all of acme")
        #expect(SearchContext.narrowedText(SearchQuery.parse("status:prog"), tab: "Board", matches: 2)
            == "status:prog in Board · 2 matches")
    }
}

@Suite struct StatusSearchEngineTests {
    @Test func matchesTheShownStatusOfIssuesOnly() {
        let snap = snapshot(
            board: [issue(1, status: inProgress), issue(2, status: todo), issue(3), issue(4, status: notDone)],
            review: [pr(9)])
        let results = engine.local(SearchQuery.parse("status:prog"), in: snap)
        #expect(results.issues.map(\.key.number) == [1])
        #expect(results.openPRs.isEmpty)
        #expect(engine.local(SearchQuery.parse(#"status:"done""#), in: snap).issues.map(\.key.number) == [])
        #expect(engine.local(SearchQuery.parse("status:done"), in: snap).issues.map(\.key.number) == [4])
    }

    @Test func issuesOffTheBoardNeverMatch() {
        let snap = snapshot(board: [issue(1, status: todo)], assigned: [issue(2)])
        #expect(engine.local(SearchQuery.parse("status:todo"), in: snap).issues.map(\.key.number) == [1])
    }

    @Test func aRemovedOptionNoLongerMatches() {
        let snap = snapshot(board: [issue(1, status: todo)], statusOptions: [inProgress])
        #expect(engine.local(SearchQuery.parse("status:todo"), in: snap).issues.isEmpty)
    }

    @Test func andsWithWordsAndState() {
        let snap = snapshot(board: [
            issue(1, status: todo, title: "Fix login"), issue(2, status: todo, isOpen: false, title: "Fix login"),
            issue(3, status: todo, title: "Other"),
        ])
        #expect(engine.local(SearchQuery.parse("status:todo is:open login"), in: snap).issues.map(\.key.number) == [1])
    }

    @Test func noRequestAndDoneAtOnce() async {
        let snap = snapshot(board: [issue(1, status: inProgress)])
        var all: [SearchResults] = []
        for await r in engine.results(SearchQuery.parse("status:prog fix"), snap: snap) { all.append(r) }
        #expect(all.count == 1)
        #expect(all.last?.phase == .done)
    }

    @Test func noRequestThroughTheCache() async {
        let snap = snapshot(board: [issue(1, status: inProgress)])
        let cache = SearchCache(capacity: 4, now: { t0 })
        let (first, updates) = engine.results(
            SearchQuery.parse("status:prog"), snap: snap, account: AccountRef(login: "me", source: .gh), cache: cache)
        #expect(first.phase == .done)
        #expect(first.issues.map(\.key.number) == [1])
        var more = 0
        for await _ in updates { more += 1 }
        #expect(more == 0)
    }
}

@Suite struct StatusNarrowingTests {
    /// Assigned's copy carries no Status; Board's copy of #2 still names a column the board dropped.
    private let snap = snapshot(
        board: [issue(1, status: inProgress), issue(2, status: StatusOption(id: "gone", name: "In progress"))],
        assigned: [issue(1), issue(2)])

    private var issueTabs: BuiltIssueTabs {
        BuiltIssueTabs(
            assigned: IssueTabContents(groups: [IssueGroup(kind: .all, issues: [issue(1), issue(2)], counted: true)]),
            created: IssueTabContents(groups: []),
            board: IssueTabContents(groups: [IssueGroup(kind: .all, issues: snap.boardIssues, counted: true)]),
            statusKnown: true, assignedLoaded: true, createdLoaded: true)
    }

    private func found(_ text: String, _ tab: IssueTab) throws -> [BoardIssue] {
        try #require(SearchNarrowing.results(
            .parse(text), scope: .issues(tab), tabs: nil, issueTabs: issueTabs, focus: nil, viewer: "me",
            snap: snap)).issues
    }

    @Test func aTabMatchesTheStatusTheBoardShows() throws {
        #expect(try found("status:prog", .assigned).map(\.key.number) == [1])
        #expect(try found("status:prog", .board).map(\.key.number) == [1])
    }

    /// As in a search of everything, the rows carry the board's Status, whatever the query.
    @Test func narrowedRowsShowTheBoardsStatus() throws {
        #expect(try found("status:prog", .assigned).map(\.status?.name) == ["In progress"])
        #expect(try found("issue", .assigned).map(\.status?.name) == ["In progress", nil])
    }

    @Test func countsToo() {
        let counts = SearchNarrowing.counts(
            .parse("status:prog"), prTabs: [], tabs: nil, issueTabs: issueTabs, focus: nil, viewer: "me",
            snap: snap)
        #expect(counts[.issues(.assigned)] == .current(1))
        #expect(counts[.issues(.board)] == .current(1))
    }
}

@Suite struct StatusCompletionTests {
    private let index = StatusIndex.build(snapshot(board: [
        issue(1, status: inProgress), issue(2, status: inProgress), issue(3, status: done, isOpen: false),
    ]))

    private func open(_ text: String, statuses: StatusIndex? = nil) -> StatusCompletion? {
        StatusCompletion.open(text: text, caret: text.utf16.count, dismissedStart: nil, statuses: statuses ?? index)
    }

    @Test func bareQualifierListsTheBoardInOrder() throws {
        #expect(try #require(open("status:")).candidates.map(\.name)
            == ["Todo", "In progress", "In review", "Done", "Not done"])
    }

    @Test func ranksNameThenPrefixThenWordThenContains() throws {
        #expect(try #require(open("status:do")).candidates.map(\.name) == ["Done", "Not done", "Todo"])
        #expect(try #require(open("status:in")).candidates.map(\.name) == ["In progress", "In review"])
        #expect(try #require(open("status:review")).candidates.map(\.name) == ["In review"])
        #expect(try #require(open("status:ogr")).candidates.map(\.name) == ["In progress"])
        #expect(try #require(open(#"status:"In p"#)).candidates.map(\.name) == ["In progress"])
    }

    @Test func openCountsComeFromTheBoard() throws {
        let rows = try #require(open("status:")).candidates
        #expect(rows.first { $0.name == "In progress" }?.openCount == 2)
        #expect(rows.first { $0.name == "Done" }?.openCount == 0)
    }

    @Test func noBoardNoRows() throws {
        let none = StatusIndex.build(snapshot(statusOptions: nil, boardProject: nil))
        #expect(try #require(open("status:", statuses: none)).candidates.isEmpty)
    }

    @Test func acceptInsertsTheQuotedName() throws {
        let text = "fix status:prog"
        let completion = try #require(open(text))
        let result = try #require(completion.accepted(in: text))
        #expect(result.text == #"fix status:"In progress" "#)
        #expect(result.caret == result.text.utf16.count)
    }

    @Test func closedQuoteEndsTheToken() {
        #expect(open(#"status:"Done""#) == nil)
        #expect(PendingToken.at(caret: 9, in: "status:Do") == PendingToken(start: 0, end: 9, prefix: "Do", kind: .status))
    }

    @Test func otherListsStayClosed() {
        #expect(StateCompletion.open(text: "status:", caret: 7, dismissedStart: nil) == nil)
        #expect(open("is:") == nil)
        #expect(open("~st") == nil)
    }

    @Test func fieldOpensTheListAndLeavesTheTokenOut() {
        var field = SearchFieldState()
        let query = field.edit("fix status:pr", caret: 13, people: .empty, labels: .empty, statuses: index)
        #expect(field.statusCompletion != nil)
        #expect(query == .text(["fix"]))
        #expect(field.dismiss() == .filtered(logins: [], labels: [], words: ["fix"], statuses: [filter("pr")]))
    }

    @Test func speech() throws {
        let completion = try #require(open("status:in"))
        #expect(CompletionSpeech.opened(completion, loaded: true)
            == "2 Status columns. Up and down arrows to choose, Return to complete.")
        #expect(CompletionSpeech.opened(completion, loaded: false) == "Status columns appear once PullBull has loaded")
        #expect(CompletionSpeech.label(completion.candidates[0]) == "In progress, on 2 items")
        #expect(CompletionSpeech.completed(completion.candidates[0]) == "Showing issues in In progress")
        let none = try #require(open("status:zz"))
        #expect(CompletionSpeech.opened(none, loaded: true) == "No matching Status columns. Return to search anyway.")
    }

    @Test func hint() {
        #expect(SearchHint.all.contains(.status))
        #expect(SearchHint.status.sigil == "status:")
        #expect(SearchHint.status.opensList)
        #expect(!SearchHint.status.showsWord && SearchHint.state.showsWord)
        #expect(SearchHint.status.accessibilityLabel == "status: column")
        #expect(SearchHint.status.caption(scope: nil) == "status:name filters issues by board Status")
    }
}
