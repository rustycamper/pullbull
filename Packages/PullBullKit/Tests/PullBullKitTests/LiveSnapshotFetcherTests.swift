import Foundation
import Testing
@testable import PullBullKit

/// Answers each request by what it asks for, since the fetcher sends them concurrently.
private final class RoutingTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [(query: String, variables: [String: Any])] = []
    private let members: [String]
    private let searchResults: [String: [Int]]
    private let issueResults: [String: [Int]]
    private let boardFails: Bool
    /// The status a failing board answers with.
    private let boardFailStatus: Int
    private let boardScopeError: Bool
    private let boardPages: Int
    /// Issue searches containing this fail with `failingIssueStatus`.
    private let failingIssueSearch: String?
    private let failingIssueStatus: Int
    /// Issue searches containing this always report another page.
    private let endlessIssueSearch: String?
    /// How long each board page and endless issue search page takes, like a slow network.
    private let pageDelay: Duration?

    init(
        members: [String], searchResults: [String: [Int]] = [:], issueResults: [String: [Int]] = [:],
        boardFails: Bool = false, boardFailStatus: Int = 502, boardScopeError: Bool = false, boardPages: Int = 1,
        failingIssueSearch: String? = nil, failingIssueStatus: Int = 502, endlessIssueSearch: String? = nil,
        pageDelay: Duration? = nil
    ) {
        self.pageDelay = pageDelay
        self.failingIssueSearch = failingIssueSearch
        self.failingIssueStatus = failingIssueStatus
        self.endlessIssueSearch = endlessIssueSearch
        self.members = members
        self.searchResults = searchResults
        self.issueResults = issueResults
        self.boardFails = boardFails
        self.boardFailStatus = boardFailStatus
        self.boardScopeError = boardScopeError
        self.boardPages = boardPages
    }

    var searches: [String] {
        lock.withLock { log.compactMap { $0.variables["q"] as? String } }
    }

    func count(_ marker: String) -> Int {
        lock.withLock { log.filter { $0.query.contains(marker) }.count }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let root = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let query = root["query"] as! String
        let variables = root["variables"] as? [String: Any] ?? [:]
        lock.withLock { log.append((query, variables)) }

        let json: String
        if query == Queries.viewer {
            json = #"{"data":{"viewer":{"login":"devon"}}}"#
        } else if query == Queries.personalContext {
            json = """
            {"data":{"viewer":{"login":"devon",\
            "repositories":{"pageInfo":{"endCursor":"R1","hasNextPage":false},"nodes":[{"name":"dotfiles"}]}}}}
            """
        } else if query.contains("membersWithRole") {
            let nodes = members.map { #"{"login":"\#($0)"}"# }.joined(separator: ",")
            json = """
            {"data":{"organization":{"membersWithRole":{"nodes":[\(nodes)]},\
            "teams":{"nodes":[{"slug":"core"}]},"repositories":{"nodes":[{"name":"gadgets"}]}}}}
            """
        } else if query.contains("projectV2") {
            if let pageDelay { try await Task.sleep(for: pageDelay) }
            if boardFails { return (Data(), Self.response(boardFailStatus)) }
            if boardScopeError {
                json = #"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"Your token has not been granted the required scopes"}]}"#
                return (Data(json.utf8), Self.response(200))
            }
            let page = Int((variables["after"] as? String)?.dropFirst() ?? "0") ?? 0
            let number = 9 + page
            let root = query.contains("user(login:") ? "user" : "organization"
            json = """
            {"data":{"\(root)":{"projectV2":{"title":"Team Board",\
            "field":{"options":[{"id":"t","name":"Todo"},{"id":"p","name":"In progress"},{"id":"d","name":"Done"}]},\
            "items":{"pageInfo":{"endCursor":"B\(page + 1)","hasNextPage":\(page + 1 < boardPages)},\
            "nodes":[{"databaseId":\(100 + number),"fieldValueByName":{"name":"In progress","optionId":"p"},\
            "content":{"__typename":"Issue","number":\(number),"title":"Fresh","url":"https://github.com/o/r/issues/\(number)",\
            "state":"OPEN","repository":{"nameWithOwner":"o/r"}}}]}}}}}
            """
        } else if query.contains("fragment issueRowFields") {
            let q = variables["q"] as? String ?? ""
            if let failingIssueSearch, q.contains(failingIssueSearch) {
                return (Data(), Self.response(failingIssueStatus))
            }
            let numbers = issueResults.first { q.contains($0.key) }?.value ?? []
            let nodes = numbers.map(Self.issueNode).joined(separator: ",")
            let more = endlessIssueSearch.map { q.contains($0) } ?? false
            if more, let pageDelay { try await Task.sleep(for: pageDelay) }
            json = #"{"data":{"search":{"pageInfo":{"endCursor":"I","hasNextPage":\#(more)},"nodes":[\#(nodes)]}}}"#
        } else {
            let q = variables["q"] as? String ?? ""
            let numbers = searchResults.first { q.contains($0.key) }?.value ?? []
            let nodes = numbers.map(Self.prNode).joined(separator: ",")
            json = #"{"data":{"search":{"pageInfo":{"endCursor":"C","hasNextPage":false},"nodes":[\#(nodes)]}}}"#
        }
        return (Data(json.utf8), Self.response(200))
    }

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.github.com/graphql")!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private static func issueNode(_ number: Int) -> String {
        """
        {"number":\(number),"title":"Issue \(number)","url":"https://github.com/o/r/issues/\(number)",\
        "state":"OPEN","stateReason":null,"createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z",\
        "closedAt":null,"repository":{"nameWithOwner":"o/r"},"author":{"login":"alice"},"comments":{"totalCount":0},\
        "labels":{"nodes":[]},"assignees":{"nodes":[{"login":"devon","avatarUrl":null}]},"timelineItems":{"nodes":[]}}
        """
    }

    private static func prNode(_ number: Int) -> String {
        """
        {"number":\(number),"title":"PR \(number)","url":"https://github.com/o/r/pull/\(number)","isDraft":false,\
        "state":"OPEN","createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z","closedAt":null,\
        "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"o/r"},\
        "author":{"login":"alice","avatarUrl":null},"comments":{"totalCount":0,"nodes":[]},\
        "commits":{"nodes":[]},"latestReviews":{"nodes":[]},"reviewRequests":{"nodes":[]}}
        """
    }
}

/// An org with nothing but an Assigned list, whose search can be switched off and whose issues change.
private final class AssignedListTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    /// Issue number → when someone else assigned the viewer.
    private var assigned: [(number: Int, at: String)] = []

    func set(failing: Bool, assigned: [(number: Int, at: String)]) {
        lock.withLock {
            self.failing = failing
            self.assigned = assigned
        }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let root = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let query = root["query"] as! String
        let q = (root["variables"] as? [String: Any])?["q"] as? String ?? ""
        let (failing, assigned) = lock.withLock { (self.failing, self.assigned) }
        let ok = { (json: String) in
            (Data(json.utf8), HTTPURLResponse(
                url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        if query == Queries.viewer { return ok(#"{"data":{"viewer":{"login":"devon"}}}"#) }
        if query.contains("membersWithRole") {
            return ok(#"{"data":{"organization":{"membersWithRole":{"nodes":[]},"teams":{"nodes":[]},"repositories":{"nodes":[]}}}}"#)
        }
        var nodes = ""
        if q.contains("assignee:@me") {
            if failing {
                return (Data(), HTTPURLResponse(
                    url: URL(string: "https://api.github.com/graphql")!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
            }
            nodes = assigned.map { issue in
                """
                {"number":\(issue.number),"title":"Issue \(issue.number)","url":"https://github.com/o/r/issues/\(issue.number)",\
                "state":"OPEN","stateReason":null,"createdAt":"2026-10-01T09:00:00Z","updatedAt":"2026-10-26T12:00:00Z",\
                "closedAt":null,"repository":{"nameWithOwner":"o/r"},"author":{"login":"alice"},"comments":{"totalCount":0},\
                "labels":{"nodes":[]},"assignees":{"nodes":[{"login":"devon","avatarUrl":null}]},\
                "timelineItems":{"nodes":[{"createdAt":"\(issue.at)","actor":{"login":"dev-b"},\
                "assignee":{"__typename":"User","login":"devon"}}]}}
                """
            }.joined(separator: ",")
        }
        return ok(#"{"data":{"search":{"pageInfo":{"endCursor":"C","hasNextPage":false},"nodes":[\#(nodes)]}}}"#)
    }
}

/// The viewer "devon" owns dotfiles and mtbfit; every search answers one item in each of those and
/// one in someone else's public repo.
private struct OwnedReposTransport: GraphQLTransport {
    static let repos = ["devon/dotfiles", "Devon/mtbfit", "someone/else"]

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let root = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let query = root["query"] as! String
        let json: String
        if query == Queries.personalContext {
            json = """
            {"data":{"viewer":{"login":"devon","repositories":{"pageInfo":{"hasNextPage":false},\
            "nodes":[{"name":"dotfiles"},{"name":"mtbfit"}]}}}}
            """
        } else if query.contains("fragment issueRowFields") {
            let nodes = Self.repos.enumerated().map { Self.issueNode(100 + $0.offset, repo: $0.element) }
            json = #"{"data":{"search":{"pageInfo":{"hasNextPage":false},"nodes":[\#(nodes.joined(separator: ","))]}}}"#
        } else {
            let closed = (root["variables"] as? [String: Any])?["q"].map { "\($0)".contains("is:closed") } ?? false
            let nodes = Self.repos.enumerated().map { Self.prNode(10 + $0.offset, repo: $0.element, closed: closed) }
            json = #"{"data":{"search":{"pageInfo":{"hasNextPage":false},"nodes":[\#(nodes.joined(separator: ","))]}}}"#
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }

    private static func issueNode(_ number: Int, repo: String) -> String {
        """
        {"number":\(number),"title":"Issue","url":"https://github.com/\(repo)/issues/\(number)",\
        "state":"OPEN","stateReason":null,"createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z",\
        "closedAt":null,"repository":{"nameWithOwner":"\(repo)"},"author":{"login":"devon"},"comments":{"totalCount":0},\
        "labels":{"nodes":[]},"assignees":{"nodes":[]},"timelineItems":{"nodes":[]}}
        """
    }

    private static func prNode(_ number: Int, repo: String, closed: Bool) -> String {
        """
        {"number":\(number),"title":"PR","url":"https://github.com/\(repo)/pull/\(number)","isDraft":false,\
        "state":"\(closed ? "MERGED" : "OPEN")","createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z",\
        "closedAt":\(closed ? "\"2026-10-25T14:03:11Z\"" : "null"),\
        "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"\(repo)"},\
        "author":{"login":"devon","avatarUrl":null},"comments":{"totalCount":0,"nodes":[]},\
        "commits":{"nodes":[]},"latestReviews":{"nodes":[]},"reviewRequests":{"nodes":[{"requestedReviewer":{"login":"devon"}}]}}
        """
    }
}

private final class Clockwork: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

// 2026-10-26T12:00:00Z
private let noon = Date(timeIntervalSince1970: 1_793_016_000)

private func fetcher(_ transport: any GraphQLTransport, _ clock: Clockwork) -> LiveSnapshotFetcher {
    LiveSnapshotFetcher(api: GitHubAPI(transport: transport, auth: StaticTokenSource("test-token")), now: { clock.now() })
}

/// An app account whose token is rejected for good: the next 401 signs it out.
private struct SignedOutOnRejection: TokenSource {
    let account: AccountRef

    func token() async throws -> String { "ghu_1" }
    func rejected(_ token: String) async throws -> Bool { throw AuthError.signedOut(account) }
}

@Suite struct LiveSnapshotFetcherTests {
    @Test func buildsSnapshotFromSearches() async throws {
        let transport = RoutingTransport(
            members: ["alice", "Devon", "bob"],
            searchResults: [
                "review-requested:@me": [1, 2],
                "reviewed-by:@me": [2, 3],
                "is:open is:pr archived:false author:@me": [10],
                "org:o author:": [20],
                "is:closed": [30],
            ])
        let clock = Clockwork(noon)
        let snap = try await fetcher(transport, clock).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)

        #expect(snap.fetchedAt == noon)
        #expect(snap.org.viewer == "devon")
        #expect(snap.org.myTeams == ["core"])
        #expect(snap.reviewCandidates.map(\.key.number) == [1, 2, 3])
        #expect(snap.mine.map(\.key.number) == [10])
        #expect(snap.team.map(\.key.number) == [20])
        #expect(snap.recentlyClosed.map(\.key.number) == [30])
        #expect(snap.boardIssues.map(\.key.number) == [9])

        let searches = Set(transport.searches)
        #expect(searches == [
            "is:open is:pr archived:false review-requested:@me",
            "is:open is:pr archived:false reviewed-by:@me -author:@me",
            "is:open is:pr archived:false author:@me",
            "is:open is:pr archived:false org:o author:alice author:bob",
            "is:pr is:closed archived:false author:@me closed:>=2026-10-19",
            "is:open is:issue archived:false org:o assignee:@me",
            "is:open is:issue archived:false org:o author:@me",
        ])
    }

    @Test func fetchesAssignedAndCreatedIssues() async throws {
        let transport = RoutingTransport(
            members: ["alice"],
            issueResults: ["assignee:@me": [231], "is:issue archived:false org:o author:@me": [52]])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        #expect(snap.assignedIssues?.map(\.key.number) == [231])
        #expect(snap.createdIssues?.map(\.key.number) == [52])
        #expect(snap.boardStatusOptions?.map(\.name) == ["Todo", "In progress", "Done"])
        #expect(snap.boardIssues.first?.status?.name == "In progress")
        #expect(Set(transport.searches).isSuperset(of: [
            "is:open is:issue archived:false org:o assignee:@me",
            "is:open is:issue archived:false org:o author:@me"]))
        #expect(transport.count("projectV2") == 1)
        // Only the Assigned search asks who assigned the viewer.
        #expect(transport.count("ASSIGNED_EVENT") == 1)
    }

    @Test func boardScopeErrorKeepsIssueLists() async throws {
        let transport = RoutingTransport(
            members: ["alice"], issueResults: ["assignee:@me": [231], "author:@me": [52]], boardScopeError: true)
        let old = BoardIssue(key: PRKey(repo: "o/r", number: 5), title: "Old", url: URL(string: "https://x/5")!, isOpen: true)
        let previous = Snapshot(
            fetchedAt: noon.addingTimeInterval(-120),
            org: OrgContext(org: "o", viewer: "devon", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [old],
            boardProject: 3, boardTitle: "Team Board",
            boardStatusOptions: [StatusOption(id: "t", name: "Todo"), StatusOption(id: "d", name: "Done")])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: previous)
        #expect(snap.boardError == "Token is missing a required scope")
        #expect(snap.assignedIssues?.count == 1)
        #expect(snap.createdIssues?.count == 1)
        #expect(snap.boardStatusOptions == previous.boardStatusOptions)
        #expect(snap.boardIssues == [old])
    }

    @Test func boardErrorDropsAnotherProjectsStatusOptions() async throws {
        let transport = RoutingTransport(members: ["alice"], boardScopeError: true)
        let previous = Snapshot(
            fetchedAt: noon.addingTimeInterval(-120),
            org: OrgContext(org: "o", viewer: "devon", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
            boardProject: 2, boardTitle: "Other", boardStatusOptions: [StatusOption(id: "t", name: "Todo")])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: previous)
        #expect(snap.boardStatusOptions == nil)
        #expect(snap.boardError != nil)
    }

    @Test func boardErrorWithoutPreviousBoardLeavesStatusOptionsNeverFetched() async throws {
        for failure in [(fails: true, scope: false), (fails: false, scope: true)] {
            let transport = RoutingTransport(members: ["alice"], boardFails: failure.fails, boardScopeError: failure.scope)
            let snap = try await fetcher(transport, Clockwork(noon)).fetch(
                account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
            #expect(snap.boardStatusOptions == nil)
            #expect(snap.boardError != nil)
            // A previous fetch of the same board that never got its options (an older cache) stays nil too.
            let legacy = Snapshot(
                fetchedAt: noon.addingTimeInterval(-120),
                org: OrgContext(org: "o", viewer: "devon", members: [], myTeams: [], repos: []),
                reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [], boardProject: 3)
            let carried = try await fetcher(transport, Clockwork(noon)).fetch(
                account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: legacy)
            #expect(carried.boardStatusOptions == nil)
        }
    }

    private func previousWithIssues(org: String = "o", assignedError: String? = nil) -> Snapshot {
        let issue = { (n: Int) in
            BoardIssue(key: PRKey(repo: "o/r", number: n), title: "Old \(n)", url: URL(string: "https://x/\(n)")!, isOpen: true)
        }
        return Snapshot(
            fetchedAt: noon.addingTimeInterval(-120),
            org: OrgContext(org: org, viewer: "devon", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [],
            assignedIssues: [issue(7)], createdIssues: [issue(8)], assignedIssuesError: assignedError)
    }

    @Test func assignedSearchFailureKeepsPreviousListsAndPollSucceeds() async throws {
        let transport = RoutingTransport(
            members: ["alice"], searchResults: ["is:open is:pr archived:false author:@me": [10]],
            issueResults: ["author:@me": [52]], failingIssueSearch: "assignee:@me")
        let previous = previousWithIssues()
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(snap.fetchedAt == noon)
        #expect(snap.mine.map(\.key.number) == [10])
        // Kept verbatim, so a diff against the previous snapshot sees nothing new.
        #expect(snap.assignedIssues == previous.assignedIssues)
        #expect(snap.createdIssues?.map(\.key.number) == [52])
        // Only the list that failed says so.
        #expect(snap.assignedIssuesError == "GitHub server error 502")
        #expect(snap.createdIssuesError == nil)
    }

    @Test func assignedFetchedAtCarriedThroughFailures() async throws {
        let transport = RoutingTransport(members: ["alice"], failingIssueSearch: "assignee:@me")
        var previous = previousWithIssues()
        previous.assignedIssuesFetchedAt = noon.addingTimeInterval(-900)
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(snap.assignedIssuesFetchedAt == noon.addingTimeInterval(-900))
        // A cache from before it was stored: the list dates from the previous fetch.
        previous.assignedIssuesFetchedAt = nil
        let legacy = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(legacy.assignedIssuesFetchedAt == previous.fetchedAt)
        // Nothing to carry: never fetched.
        let fresh = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: nil)
        #expect(fresh.assignedIssuesFetchedAt == nil)
        let ok = try await fetcher(RoutingTransport(members: ["alice"]), Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(ok.assignedIssuesFetchedAt == noon)
    }

    @Test func createdFetchedAtCarriedThroughFailures() async throws {
        let transport = RoutingTransport(members: ["alice"], failingIssueSearch: "author:@me")
        var previous = previousWithIssues()
        previous.createdIssuesFetchedAt = noon.addingTimeInterval(-900)
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(snap.createdIssuesFetchedAt == noon.addingTimeInterval(-900))
        #expect(snap.assignedIssuesFetchedAt == noon)
        previous.createdIssuesFetchedAt = nil
        let legacy = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(legacy.createdIssuesFetchedAt == previous.fetchedAt)
        let fresh = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: nil)
        #expect(fresh.createdIssuesFetchedAt == nil)
    }

    /// The "Assigned 0" beside "Issues couldn't load": the last good Assigned list was empty, so a
    /// failed search carries `[]` forward. The list counts as loaded (it once succeeded), and before
    /// the tab count knew about the latest failure it read "0" as if current.
    @Test func failedSearchAfterEmptyListIsNotCountedAsZero() async throws {
        var previous = previousWithIssues()
        previous.assignedIssues = []
        let transport = RoutingTransport(members: ["alice"], failingIssueSearch: "assignee:@me")
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(snap.assignedIssues == [])
        #expect(snap.assignedIssuesError == "GitHub server error 502")
        var settings = AppSettings()
        settings.countAssignedIssues = true
        let tabs = IssueTabBuilder.build(snap, settings: settings, now: noon)
        #expect(tabs.isLoaded(.assigned))
        #expect(tabs.count(.assigned) == .unavailable)
        #expect(tabs.count(.created) == .current(0))
        #expect(Badge.issuesIncomplete(issues: tabs, settings: settings))
    }

    @Test func assignmentDuringAssignedOutageNotifiesOnceOnRecovery() async throws {
        let transport = AssignedListTransport()
        let clock = Clockwork(noon)
        let live = fetcher(transport, clock)
        var toggles = NotificationToggles()
        toggles.issueAssigned = true
        // Assigned a day before the last good fetch.
        transport.set(failing: false, assigned: [(100, "2026-10-25T12:00:00Z")])
        var previous = try await live.fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: nil)
        var events: [IssueEvent] = []
        func poll(after seconds: TimeInterval) async throws {
            clock.advance(seconds)
            let next = try await live.fetch(
                account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
            events += ChangeDetector.issueEvents(old: previous, new: next, me: "devon", toggles: toggles)
            previous = next
        }
        // A 20-minute outage of the Assigned search; #231 is assigned 3 minutes in.
        transport.set(failing: true, assigned: [])
        for _ in 0..<10 { try await poll(after: 120) }
        #expect(previous.assignedIssuesError != nil)
        #expect(previous.assignedIssuesFetchedAt == noon)
        // Recovery. #232's assignment predates the last good fetch by more than the lag, so it is not new.
        transport.set(failing: false, assigned: [
            (100, "2026-10-25T12:00:00Z"), (231, "2026-10-26T12:03:00Z"), (232, "2026-10-26T11:45:00Z"),
        ])
        try await poll(after: 120)
        try await poll(after: 120)
        #expect(events.map(\.issue.key.number) == [231])
        #expect(previous.assignedIssuesFetchedAt == noon.addingTimeInterval(24 * 60))
    }

    @Test func issueSearchFailureWithoutPreviousLeavesListNeverFetched() async throws {
        let transport = RoutingTransport(members: ["alice"], failingIssueSearch: "is:issue")
        for previous in [nil, previousWithIssues(org: "other")] as [Snapshot?] {
            let snap = try await fetcher(transport, Clockwork(noon)).fetch(
                account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
            #expect(snap.assignedIssues == nil)
            #expect(snap.createdIssues == nil)
            #expect(snap.assignedIssuesError == "GitHub server error 502")
            #expect(snap.createdIssuesError == "GitHub server error 502")
        }
    }

    @Test func issueSearchSuccessClearsIssuesError() async throws {
        let transport = RoutingTransport(members: ["alice"], issueResults: ["assignee:@me": [231]])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true,
            previous: previousWithIssues(assignedError: "GitHub server error 502"))
        #expect(snap.assignedIssuesError == nil)
        #expect(snap.createdIssuesError == nil)
        #expect(snap.assignedIssues?.map(\.key.number) == [231])
        #expect(snap.createdIssues == [])
    }

    @Test func issueSearchPastPageCapIsIncompleteAndKeepsLists() async throws {
        let transport = RoutingTransport(members: ["alice"], issueResults: ["author:@me": [52]], endlessIssueSearch: "author:@me")
        let previous = previousWithIssues()
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: previous)
        #expect(snap.createdIssuesError == "incomplete created issues list")
        #expect(snap.assignedIssuesError == nil)
        #expect(snap.createdIssues == previous.createdIssues)
        #expect(snap.assignedIssues == [])
        #expect(transport.searches.filter { $0.contains("is:issue") && $0.contains("author:@me") }.count == 20)
    }

    @Test func rateLimitOrRejectedTokenInIssueSearchFailsThePoll() async throws {
        for status in [429, 401] {
            let transport = RoutingTransport(
                members: ["alice"], failingIssueSearch: "assignee:@me", failingIssueStatus: status)
            let error = await #expect(throws: APIError.self) {
                try await fetcher(transport, Clockwork(noon)).fetch(
                    account: "devon", scope: .org("o"), board: nil, canReadProjects: true,
                    previous: previousWithIssues())
            }
            switch (status, error) {
            case (429, .rateLimited?), (401, .unauthorized?): break
            default: Issue.record("HTTP \(status) gave \(String(describing: error))")
            }
        }
    }

    @Test func signedOutFailsThePoll() async throws {
        let account = AccountRef(login: "octocat", source: .gitHubApp)
        let transport = RoutingTransport(
            members: ["alice"], failingIssueSearch: "assignee:@me", failingIssueStatus: 401)
        let fetcher = LiveSnapshotFetcher(
            api: GitHubAPI(transport: transport, auth: SignedOutOnRejection(account: account)),
            now: { noon })
        await #expect(throws: AuthError.signedOut(account)) {
            try await fetcher.fetch(
                account: "octocat", scope: .org("o"), board: nil, canReadProjects: true,
                previous: previousWithIssues())
        }
    }

    @Test func signedOutOnBoardFailsThePoll() async throws {
        let account = AccountRef(login: "octocat", source: .gitHubApp)
        let transport = RoutingTransport(members: ["alice"], boardFails: true, boardFailStatus: 401)
        let fetcher = LiveSnapshotFetcher(
            api: GitHubAPI(transport: transport, auth: SignedOutOnRejection(account: account)),
            now: { noon })
        await #expect(throws: AuthError.signedOut(account)) {
            try await fetcher.fetch(
                account: "octocat", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        }
        #expect(transport.count("projectV2") == 1)
    }

    @Test func rateLimitedAssignedSearchStopsBoardAndCreatedPaging() async throws {
        // Board and Created would each page 20 times; Assigned is rate limited at once.
        let transport = RoutingTransport(
            members: ["alice"], boardPages: 25, failingIssueSearch: "assignee:@me", failingIssueStatus: 429,
            endlessIssueSearch: "is:issue archived:false org:o author:@me", pageDelay: .milliseconds(200))
        let created = { transport.searches.filter { $0 == "is:open is:issue archived:false org:o author:@me" }.count }
        let error = await #expect(throws: APIError.self) {
            try await fetcher(transport, Clockwork(noon)).fetch(
                account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        }
        guard case .rateLimited? = error else {
            Issue.record("gave \(String(describing: error))")
            return
        }
        let boardAtThrow = transport.count("projectV2")
        let createdAtThrow = created()
        #expect(boardAtThrow <= 1)
        #expect(createdAtThrow <= 1)
        try await Task.sleep(for: .milliseconds(500))
        #expect(transport.count("projectV2") == boardAtThrow)
        #expect(created() == createdAtThrow)
    }

    @Test func noProjectAccessSkipsBoardButFetchesIssues() async throws {
        let transport = RoutingTransport(members: ["alice"], issueResults: ["assignee:@me": [231]])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: nil)
        #expect(transport.count("projectV2") == 0)
        #expect(snap.assignedIssues?.map(\.key.number) == [231])
        #expect(snap.createdIssues == [])
        #expect(snap.boardStatusOptions == nil)
    }

    @Test func boardFollowsAllPages() async throws {
        let transport = RoutingTransport(members: ["alice"], boardPages: 3)
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        #expect(snap.boardIssues.map(\.key.number) == [9, 10, 11])
        #expect(snap.boardError == nil)
    }

    @Test func boardPastPageCapIsAnErrorNotATruncation() async throws {
        let transport = RoutingTransport(members: ["alice"], boardPages: 25)
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        #expect(snap.boardIssues.isEmpty)
        #expect(snap.boardError == "incomplete board 3")
        #expect(snap.boardStatus == .unavailable("incomplete board 3"))
    }

    @Test func emptyTeamSkipsSearch() async throws {
        let transport = RoutingTransport(members: ["devon"])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        #expect(snap.team.isEmpty)
        #expect(!transport.searches.contains { $0.contains("is:pr") && $0.contains("org:o") })
        #expect(transport.searches.count == 6)
    }

    @Test func orgContextReusedWithinHour() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let clock = Clockwork(noon)
        let live = fetcher(transport, clock)
        let first = try await live.fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: nil)
        #expect(transport.count("membersWithRole") == 1)

        clock.advance(59 * 60)
        let second = try await live.fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: first)
        #expect(transport.count("membersWithRole") == 1)
        #expect(transport.count(Queries.viewer) == 1)
        #expect(second.org == first.org)

        clock.advance(2 * 60)
        _ = try await live.fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: second)
        #expect(transport.count("membersWithRole") == 2)
    }

    @Test func orgContextNotReusedWithoutPrevious() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let live = fetcher(transport, Clockwork(noon))
        _ = try await live.fetch(account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: nil)
        _ = try await live.fetch(account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: nil)
        #expect(transport.count("membersWithRole") == 2)
    }

    @Test func orgContextNotReusedAcrossAccounts() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let live = fetcher(transport, Clockwork(noon))
        let first = try await live.fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: nil)
        _ = try await live.fetch(account: "other", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: first)
        #expect(transport.count("membersWithRole") == 2)
    }

    @Test func boardFailureKeepsPreviousOfSameProjectAndRecordsError() async throws {
        let transport = RoutingTransport(members: ["alice"], boardFails: true)
        let old = BoardIssue(key: PRKey(repo: "o/r", number: 5), title: "Old", url: URL(string: "https://x/5")!, isOpen: true)
        let previous = Snapshot(
            fetchedAt: noon.addingTimeInterval(-120),
            org: OrgContext(org: "o", viewer: "devon", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [old],
            boardProject: 3, boardTitle: "Team Board")
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: previous)
        #expect(snap.boardIssues == [old])
        #expect(snap.boardProject == 3)
        // While the board can't be read its issues are labelled neutrally, not with its title.
        #expect(snap.boardTitle == nil)
        #expect(snap.boardError == "GitHub server error 502")
        #expect(snap.boardStatus == .unavailable("GitHub server error 502"))
        #expect(snap.fetchedAt == noon)
    }

    @Test func boardFailureDropsAnotherProjectsIssues() async throws {
        let transport = RoutingTransport(members: ["alice"], boardFails: true)
        let old = BoardIssue(key: PRKey(repo: "o/r", number: 5), title: "Old", url: URL(string: "https://x/5")!, isOpen: true)
        for project in [2, nil] as [Int?] {
            let previous = Snapshot(
                fetchedAt: noon.addingTimeInterval(-120),
                org: OrgContext(org: "o", viewer: "devon", members: [], myTeams: [], repos: []),
                reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [old],
                boardProject: project, boardTitle: "Other")
            let snap = try await fetcher(transport, Clockwork(noon)).fetch(
                account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: previous)
            #expect(snap.boardIssues.isEmpty)
            #expect(snap.boardProject == 3)
            #expect(snap.boardTitle == nil)
            #expect(snap.boardError != nil)
        }
    }

    @Test func boardSuccessRecordsProjectAndTitle() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: nil)
        #expect(snap.boardProject == 3)
        #expect(snap.boardTitle == "Team Board")
        #expect(snap.boardError == nil)
        #expect(snap.boardStatus == .available)
    }

    @Test func noBoardChosenFetchesNoBoard() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: nil, canReadProjects: true, previous: nil)
        #expect(snap.boardIssues.isEmpty)
        #expect(snap.boardStatus == .none)
        #expect(transport.count("projectV2") == 0)
    }

    @Test func noBoardWithoutProjectScope() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: false, previous: nil)
        #expect(snap.boardIssues.isEmpty)
        #expect(snap.boardProject == nil)
        #expect(snap.boardError == nil)
        #expect(snap.boardStatus == .none)
        #expect(transport.count("projectV2") == 0)
    }

    /// No org: every search keeps to `user:<login>` instead of `org:`, items in other owners' repos are
    /// dropped, Team isn't fetched, and an org's board (here the default #3) never is.
    @Test func personalScopeFetchesWithoutAnOrg() async throws {
        let transport = RoutingTransport(
            members: ["alice"],
            searchResults: ["review-requested:@me": [1], "is:open is:pr archived:false author:@me": [10]],
            issueResults: ["assignee:@me": [231], "is:issue archived:false author:@me": [52]])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .personal(login: "devon"), board: .org("o", 3), canReadProjects: true,
            previous: nil)

        #expect(Set(transport.searches) == [
            "is:open is:pr archived:false user:devon review-requested:@me",
            "is:open is:pr archived:false user:devon reviewed-by:@me -author:@me",
            "is:open is:pr archived:false user:devon author:@me",
            "is:pr is:closed archived:false user:devon author:@me closed:>=2026-10-19",
            "is:open is:issue archived:false user:devon assignee:@me",
            "is:open is:issue archived:false user:devon author:@me",
        ])
        #expect(transport.count("membersWithRole") == 0)
        #expect(transport.count("projectV2") == 0)
        #expect(snap.scope == .personal(login: "devon"))
        #expect(snap.org.viewer == "devon")
        #expect(snap.org.repos == ["dotfiles"])
        #expect(snap.org.members.isEmpty)
        #expect(snap.team.isEmpty)
        // The transport's items are all in o/r, someone else's repository.
        #expect(snap.reviewCandidates.isEmpty)
        #expect(snap.mine.isEmpty)
        #expect(snap.assignedIssues == [])
        #expect(snap.createdIssues == [])
        #expect(snap.boardProject == nil)
        #expect(snap.boardStatus == .none)
        #expect(snap.boardStatusOptions == nil)
    }

    /// The personal context is reused like an org's, and never for an org of the same name.
    @Test func personalContextIsReusedOnlyForThePersonalScope() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let clock = Clockwork(noon)
        let live = fetcher(transport, clock)
        let first = try await live.fetch(
            account: "devon", scope: .personal(login: "devon"), board: nil, canReadProjects: false,
            previous: nil)
        clock.advance(120)
        _ = try await live.fetch(
            account: "devon", scope: .personal(login: "devon"), board: nil, canReadProjects: false,
            previous: first)
        #expect(transport.count("ownerAffiliations") == 1)
        clock.advance(120)
        let org = try await live.fetch(
            account: "devon", scope: .org("devon"), board: nil, canReadProjects: false,
            previous: first)
        #expect(transport.count("membersWithRole") == 1)
        #expect(org.scope == .org("devon"))
    }

    /// An app installation limited to selected repositories: only those repos' items are kept, on every
    /// list, and number lookup covers only them.
    @Test func personalScopeKeepsOnlyTheInstalledRepos() async throws {
        let transport = OwnedReposTransport()
        let scope = FetchScope.personal(login: "devon", repos: ["devon/dotfiles"])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: scope, board: nil, canReadProjects: false, previous: nil)
        let dotfiles = "devon/dotfiles"
        #expect(snap.reviewCandidates.map(\.key.repo) == [dotfiles])
        #expect(snap.mine.map(\.key.repo) == [dotfiles])
        #expect(snap.recentlyClosed.map(\.key.repo) == [dotfiles])
        #expect(snap.assignedIssues?.map(\.key.repo) == [dotfiles])
        #expect(snap.createdIssues?.map(\.key.repo) == [dotfiles])
        #expect(snap.org.repos == ["dotfiles"])
        #expect(snap.scope == scope)
    }

    /// All repositories (or a `gh` login): the user's own repos, never someone else's.
    @Test func personalScopeWithoutASelectionKeepsOwnedRepos() async throws {
        let snap = try await fetcher(OwnedReposTransport(), Clockwork(noon)).fetch(
            account: "devon", scope: .personal(login: "devon"), board: nil, canReadProjects: false,
            previous: nil)
        #expect(Set(snap.mine.map(\.key.repo)) == ["devon/dotfiles", "Devon/mtbfit"])
        #expect(Set(snap.assignedIssues?.map(\.key.repo) ?? []) == ["devon/dotfiles", "Devon/mtbfit"])
        #expect(snap.org.repos == ["dotfiles", "mtbfit"])
    }

    /// No-org mode fetches the user's own board through `user(login:)`, keeps its items to the user's
    /// own repos like every other list, and records the owner with the number.
    @Test func personalScopeFetchesTheUsersBoard() async throws {
        let transport = RoutingTransport(members: ["alice"])
        let snap = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .personal(login: "devon"), board: .user("devon", 3),
            canReadProjects: true, previous: nil)
        #expect(transport.count("user(login:$login){\n    projectV2") == 1)
        #expect(transport.count("organization(login:$login){\n    projectV2") == 0)
        #expect(snap.board == .user("devon", 3))
        #expect(snap.boardTitle == "Team Board")
        #expect(snap.boardStatus == .available)
        #expect(snap.boardStatusOptions?.count == 3)
        // The transport's board item is in o/r, someone else's repository.
        #expect(snap.boardIssues.isEmpty)
    }

    /// Org mode never shows a personal board, and no-org mode never another user's.
    @Test func boardOfAnotherOwnerIsNotFetched() async throws {
        for (scope, board) in [
            (FetchScope.org("o"), BoardRef.user("o", 3)),
            (.personal(login: "devon"), .user("someone", 3)),
            (.personal(login: "devon"), .org("devon", 3)),
        ] {
            let transport = RoutingTransport(members: ["alice"])
            let snap = try await fetcher(transport, Clockwork(noon)).fetch(
                account: "devon", scope: scope, board: board, canReadProjects: true, previous: nil)
            #expect(transport.count("projectV2") == 0)
            #expect(snap.board == nil)
            #expect(snap.boardStatus == .none)
        }
    }

    /// The previous items are kept on a failure only for the same board: the same number of another
    /// owner is another board.
    @Test func failedBoardKeepsOnlyTheSameOwnersItems() async throws {
        let transport = RoutingTransport(members: ["alice"], boardFails: true)
        let old = BoardIssue(key: PRKey(repo: "o/r", number: 5), title: "Old", url: URL(string: "https://x/5")!, isOpen: true)
        var previous = Snapshot(
            fetchedAt: noon.addingTimeInterval(-120),
            org: OrgContext(org: "o", viewer: "devon", members: [], myTeams: [], repos: []),
            reviewCandidates: [], mine: [], team: [], recentlyClosed: [], boardIssues: [old], boardProject: 3,
            boardOwner: .user("o"))
        let other = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: previous)
        #expect(other.boardIssues.isEmpty)
        #expect(other.boardError != nil)
        previous.boardOwner = .org("o")
        let same = try await fetcher(transport, Clockwork(noon)).fetch(
            account: "devon", scope: .org("o"), board: .org("o", 3), canReadProjects: true, previous: previous)
        #expect(same.boardIssues == [old])
        #expect(same.board == .org("o", 3))
    }
}
