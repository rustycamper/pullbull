import Foundation
import Testing
@testable import PullBullKit

/// Answers each request in turn and records the bodies.
private final class QueueTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data]
    private var sent: [Data] = []

    init(_ json: [String]) { queue = json.map { Data($0.utf8) } }
    init(data: [Data]) { queue = data }

    var bodies: [[String: Any]] {
        lock.withLock { sent.compactMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } }
    }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let data = lock.withLock {
            sent.append(body)
            return queue.removeFirst()
        }
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func api(_ transport: QueueTransport) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"))
}

/// What GitHub answers a GitHub App's token for a user-owned board (checked live on #15).
private let forbiddenError = """
{"type":"FORBIDDEN","path":["user","projectV2"],"message":"Resource not accessible by integration"}
"""

@Suite struct BoardTests {
    // MARK: Owner

    @Test func ownerKindsAndLogins() {
        #expect(BoardOwner.org("initech").login == "initech")
        #expect(BoardOwner.user("rustycamper").login == "rustycamper")
        #expect(BoardOwner.user("rustycamper").isUser)
        #expect(!BoardOwner.org("initech").isUser)
        // An org and a user can share a login and still own different boards #3.
        #expect(BoardRef.org("x", 3) != BoardRef.user("x", 3))
        #expect(!BoardRef.org("x", 3).matches(.user("x", 3)))
        #expect(BoardRef.user("RustyCamper", 3).matches(.user("rustycamper", 3)))
        #expect(!BoardRef.user("rustycamper", 3).matches(.user("rustycamper", 2)))
        #expect(!BoardRef.user("rustycamper", 3).matches(nil))
    }

    @Test func ownerCodesWithItsKind() throws {
        for owner in [BoardOwner.org("initech"), .user("rustycamper")] {
            let data = try JSONEncoder().encode(owner)
            #expect(try JSONDecoder().decode(BoardOwner.self, from: data) == owner)
        }
        let user = try JSONDecoder().decode(BoardOwner.self, from: Data(#"{"kind":"user","login":"me"}"#.utf8))
        #expect(user == .user("me"))
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(BoardOwner.self, from: Data(#"{"kind":"team","login":"me"}"#.utf8))
        }
    }

    @Test func scopeShowsOnlyItsOwnersBoards() {
        #expect(FetchScope.org("initech").boardOwner == .org("initech"))
        #expect(FetchScope.personal(login: "me").boardOwner == .user("me"))
        #expect(FetchScope.org("initech").shows(.org("initech", 3)))
        #expect(!FetchScope.org("initech").shows(.user("initech", 3)))
        #expect(FetchScope.personal(login: "me", repos: ["me/a"]).shows(.user("Me", 1)))
        #expect(!FetchScope.personal(login: "me").shows(.org("me", 1)))
        #expect(!FetchScope.personal(login: "me").shows(.user("other", 1)))
    }

    /// No-org mode picks the user's first board: the lowest number, whatever order they came in.
    @Test func firstBoardIsTheLowestNumber() {
        let boards = [
            BoardSummary(board: .user("me", 3), title: "PullBull"),
            BoardSummary(board: .user("me", 1), title: "QC App"),
            BoardSummary(board: .user("me", 2), title: "Hopwallet"),
        ]
        #expect(BoardSummary.first(of: boards)?.board == .user("me", 1))
        #expect(BoardSummary.first(of: []) == nil)
    }

    // MARK: Personal board access

    @Test func appAccountNeedsTheSameLoginFromGh() {
        let withScope = [GhAccount(login: "rustycamper", scopes: ["repo", "project"])]
        #expect(PersonalBoardAccess.of(login: "rustycamper", source: .gitHubApp, ghAccounts: withScope)
            == .useGhLogin("rustycamper"))
        let withoutScope = [GhAccount(login: "rustycamper", scopes: ["repo"])]
        #expect(PersonalBoardAccess.of(login: "rustycamper", source: .gitHubApp, ghAccounts: withoutScope)
            == .addScope(command: "gh auth switch --user rustycamper && gh auth refresh -s read:project"))
        let other = [GhAccount(login: "someone", scopes: ["project"])]
        #expect(PersonalBoardAccess.of(login: "rustycamper", source: .gitHubApp, ghAccounts: other)
            == .logIn(command: "gh auth login --web -s read:project"))
        #expect(PersonalBoardAccess.of(login: "rustycamper", source: .gitHubApp, ghAccounts: [])
            == .logIn(command: GhCommands.logIn))
    }

    @Test func ghAccountNeedsTheProjectScope() {
        let ready = [GhAccount(login: "me", scopes: ["read:project"])]
        #expect(PersonalBoardAccess.of(login: "me", source: .gh, ghAccounts: ready) == .ready)
        let missing = [GhAccount(login: "me", scopes: ["repo"], active: true)]
        #expect(PersonalBoardAccess.of(login: "me", source: .gh, ghAccounts: missing)
            == .addScope(command: "gh auth refresh -s read:project"))
        // Another login is gh's active one: switch to this one and back.
        let inactive = [GhAccount(login: "me", scopes: ["repo"]), GhAccount(login: "work", scopes: ["repo"], active: true)]
        #expect(PersonalBoardAccess.of(login: "me", source: .gh, ghAccounts: inactive)
            == .addScope(command: "gh auth switch --user me && gh auth refresh -s read:project && gh auth switch --user work"))
        // Not listed yet: assumed readable, as `canReadProjects(for:)` does.
        #expect(PersonalBoardAccess.of(login: "me", source: .gh, ghAccounts: []) == .ready)
    }

    // MARK: Queries

    @Test func queriesReadTheOwnersRootField() {
        #expect(Queries.board(.org("initech")).contains("organization(login:$login){"))
        #expect(Queries.board(.user("me")).contains("user(login:$login){"))
        #expect(!Queries.board(.user("me")).contains("organization"))
        #expect(Queries.projects(.org("initech")).contains("organization(login:$login){"))
        #expect(Queries.projects(.user("me")).contains("user(login:$login){"))
        // The item and field selection is the same for both owners.
        let org = Queries.board(.org("x")).replacingOccurrences(of: "organization(login:", with: "")
        let user = Queries.board(.user("x")).replacingOccurrences(of: "user(login:", with: "")
        #expect(org == user)
    }

    @Test func userBoardDecodes() async throws {
        let transport = QueueTransport(data: [try fixture("board_items_user")])
        let board = try await api(transport).board(.user("rustycamper", 3))
        #expect(board.title == "PullBull")
        #expect(board.statusOptions.map(\.name) == ["Idea", "Todo", "In Progress", "Done"])
        #expect(board.issues.map(\.key) == [
            PRKey(repo: "rustycamper/pullbull", number: 13), PRKey(repo: "rustycamper/pullbull", number: 15),
            PRKey(repo: "initech/widgets", number: 42),
        ])
        #expect(board.issues[1].status == BoardStatusValue(optionId: "47fc9ee4", name: "In Progress"))
        #expect(board.issues[0].boardItemId == 284822570)
        let body = try #require(transport.bodies.first)
        #expect((body["query"] as? String)?.contains("user(login:$login)") == true)
        let variables = body["variables"] as? [String: Any]
        #expect(variables?["login"] as? String == "rustycamper")
        #expect(variables?["n"] as? Int == 3)
    }

    @Test func boardReadsProjectAndStatusFieldIds() async throws {
        let transport = QueueTransport(["""
        {"data":{"organization":{"projectV2":{"id":"PVT_p1","title":"B",\
        "field":{"id":"PVTSSF_f1","options":[{"id":"o1","name":"Todo"}]},\
        "items":{"pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":[{"id":"PVTI_i1","databaseId":5,\
        "fieldValueByName":{"name":"Todo","optionId":"o1"},"content":{"__typename":"Issue","id":"I_1","number":1,\
        "title":"t","url":"https://github.com/acme/w/issues/1","state":"OPEN","repository":{"nameWithOwner":"acme/w"}}}]}}}}}
        """])
        let board = try await api(transport).board(.org("acme", 1))
        #expect(board.ids == BoardIds(projectId: "PVT_p1", statusFieldId: "PVTSSF_f1"))
        #expect(board.issues.first?.boardItemNodeId == "PVTI_i1")
        #expect(board.issues.first?.nodeId == "I_1")
        let query = try #require(transport.bodies.first?["query"] as? String)
        #expect(query.contains("projectV2(number:$n){\n      id title"))
        #expect(query.contains("ProjectV2SingleSelectField{id options"))
        #expect(query.contains("nodes{\n          id databaseId"))
    }

    @Test func boardWithoutStatusFieldHasNoFieldId() async throws {
        let transport = QueueTransport(["""
        {"data":{"organization":{"projectV2":{"id":"PVT_p1","title":"B","field":null,\
        "items":{"pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":[]}}}}}
        """])
        #expect(try await api(transport).board(.org("acme", 1)).ids == BoardIds(projectId: "PVT_p1", statusFieldId: nil))
    }

    @Test func userProjectsList() async throws {
        let json = """
        {"data":{"user":{"projectsV2":{"nodes":[{"number":1,"title":"@rustycamper's QC App"},\
        {"number":2,"title":"Hopwallet Project"},{"number":3,"title":"PullBull"}]}}}}
        """
        let transport = QueueTransport([json])
        let boards = try await api(transport).projects(owner: .user("rustycamper"))
        #expect(boards.map(\.board) == [.user("rustycamper", 1), .user("rustycamper", 2), .user("rustycamper", 3)])
        #expect(boards.last?.title == "PullBull")
        #expect((transport.bodies.first?["query"] as? String)?.contains("user(login:$login)") == true)
    }

    // MARK: FORBIDDEN

    /// A GitHub App's token on a personal board: GitHub sends a null project with FORBIDDEN, which
    /// must not read as "not found".
    @Test func forbiddenBoardIsItsOwnError() async {
        let json = #"{"data":{"user":{"projectV2":null}},"errors":[\#(forbiddenError)]}"#
        await #expect(throws: APIError.boardForbidden) {
            try await api(QueueTransport([json])).board(.user("rustycamper", 3))
        }
        let ownerNull = #"{"data":{"user":null},"errors":[\#(forbiddenError)]}"#
        await #expect(throws: APIError.boardForbidden) {
            try await api(QueueTransport([ownerNull])).board(.user("rustycamper", 3))
        }
        #expect(RefreshError(APIError.boardForbidden).message == "GitHub won't let this sign-in read the board")
    }

    @Test func missingBoardIsStillNotFound() async {
        let json = #"{"data":{"user":{"projectV2":null}},"errors":[{"type":"NOT_FOUND","message":"Could not resolve"}]}"#
        await #expect(throws: APIError.graphQL("project 9 not found")) {
            try await api(QueueTransport([json])).board(.user("rustycamper", 9))
        }
    }

    /// Items GitHub won't show (an issue in a repo the token can't read) come back null with FORBIDDEN;
    /// the readable rest of the board still loads.
    @Test func forbiddenItemsDoNotFailTheBoard() async throws {
        let json = """
        {"data":{"organization":{"projectV2":{"title":"B","field":null,"items":{\
        "pageInfo":{"endCursor":null,"hasNextPage":false},"nodes":[\
        {"databaseId":5,"fieldValueByName":null,"content":{"__typename":"Issue",\
        "number":1,"title":"T","url":"https://github.com/o/r/issues/1","state":"OPEN","repository":{"nameWithOwner":"o/r"}}},\
        {"databaseId":6,"fieldValueByName":null,"content":null}]}}}},\
        "errors":[{"type":"FORBIDDEN","path":["organization","projectV2","items","nodes",1,"content"],"message":"no"}]}
        """
        let board = try await api(QueueTransport([json])).board(.org("o", 1))
        #expect(board.issues.map(\.key.number) == [1])
    }

    @Test func forbiddenProjectsListIsItsOwnError() async throws {
        let nodes = #"{"data":{"user":{"projectsV2":{"nodes":[null,null]}}},"errors":[\#(forbiddenError)]}"#
        await #expect(throws: APIError.boardForbidden) {
            try await api(QueueTransport([nodes])).projects(owner: .user("rustycamper"))
        }
        let ownerNull = #"{"data":{"user":null},"errors":[\#(forbiddenError)]}"#
        await #expect(throws: APIError.boardForbidden) {
            try await api(QueueTransport([ownerNull])).projects(owner: .user("rustycamper"))
        }
        // Some readable: those are listed.
        let some = """
        {"data":{"user":{"projectsV2":{"nodes":[null,{"number":3,"title":"PullBull"}]}}},"errors":[\(forbiddenError)]}
        """
        let boards = try await api(QueueTransport([some])).projects(owner: .user("rustycamper"))
        #expect(boards.map(\.board) == [.user("rustycamper", 3)])
        // No boards at all is an empty list, not an error.
        let empty = #"{"data":{"user":{"projectsV2":{"nodes":[]}}}}"#
        #expect(try await api(QueueTransport([empty])).projects(owner: .user("rustycamper")).isEmpty)
    }

    /// Other queries keep returning partial data as before.
    @Test func otherQueriesStillIgnoreForbiddenAlongsideData() async throws {
        let json = #"{"data":{"viewer":{"organizations":{"nodes":[{"login":"a"}]}}},"errors":[\#(forbiddenError)]}"#
        #expect(try await api(QueueTransport([json])).organizations() == ["a"])
    }

    // MARK: Snapshot

    private func snapshot(org: OrgContext, project: Int?, owner: BoardOwner?) -> Snapshot {
        Snapshot(
            fetchedAt: Date(timeIntervalSince1970: 0), org: org, reviewCandidates: [], mine: [], team: [],
            recentlyClosed: [], boardIssues: [], boardProject: project, boardOwner: owner)
    }

    @Test func snapshotBoardCarriesItsOwner() throws {
        let orgContext = OrgContext(org: "initech", viewer: "me", members: [], myTeams: [], repos: [])
        let personal = OrgContext.personal(login: "me", repos: [], reposComplete: true)
        #expect(snapshot(org: personal, project: 3, owner: .user("me")).board == .user("me", 3))
        #expect(snapshot(org: orgContext, project: 3, owner: .org("initech")).board == .org("initech", 3))
        // Cached before the owner was stored: an org snapshot's board was the org's; a personal one
        // had none, so its number is never a personal board.
        #expect(snapshot(org: orgContext, project: 3, owner: nil).board == .org("initech", 3))
        #expect(snapshot(org: personal, project: 3, owner: nil).board == nil)
        #expect(snapshot(org: personal, project: nil, owner: .user("me")).board == nil)

        let saved = snapshot(org: personal, project: 3, owner: .user("me"))
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(saved))
        #expect(back.board == .user("me", 3))
    }

    /// No-org mode keeps board items to the user's own repos, as every other list.
    @Test func personalBoardKeepsOwnReposOnly() {
        var snap = snapshot(org: .personal(login: "me", repos: [], reposComplete: true), project: 3, owner: .user("me"))
        let issue = { (repo: String) in
            BoardIssue(key: PRKey(repo: repo, number: 1), title: "i", url: URL(string: "https://x/1")!, isOpen: true)
        }
        snap.boardIssues = [issue("me/a"), issue("initech/widgets"), issue("Me/b")]
        let limited = snap.limited(to: .personal(login: "me"))
        #expect(limited.boardIssues.map(\.key.repo) == ["me/a", "Me/b"])
        #expect(limited.board == .user("me", 3))
    }
}
