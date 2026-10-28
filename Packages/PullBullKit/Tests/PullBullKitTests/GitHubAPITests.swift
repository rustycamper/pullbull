import Foundation
import Testing
@testable import PullBullKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com/graphql")!, statusCode: status,
        httpVersion: nil, headerFields: headers)!
}

private final class StubTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(Data, HTTPURLResponse)]
    private var sent: [Data] = []
    private var sentTokens: [String] = []

    init(_ responses: [(Data, HTTPURLResponse)]) { queue = responses }

    convenience init(json: [String]) {
        self.init(json.map { (Data($0.utf8), response(200)) })
    }

    var bodies: [String] {
        lock.withLock { sent.map { String(decoding: $0, as: UTF8.self) } }
    }

    /// The token each request carried, in order.
    var tokens: [String] { lock.withLock { sentTokens } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock {
            sent.append(body)
            sentTokens.append(token)
            return queue.removeFirst()
        }
    }
}

private struct FailingTransport: GraphQLTransport {
    let error: URLError

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

private func api(_ transport: StubTransport, now: Date = Date()) -> GitHubAPI {
    GitHubAPI(transport: transport, auth: StaticTokenSource("test-token"), now: { now })
}

private let clockNow = Date(timeIntervalSince1970: 1_793_000_000)

private func prNode(_ number: Int, includeNumber: Bool = true) -> String {
    let n = includeNumber ? "\"number\":\(number)," : ""
    return """
    {\(n)"title":"PR \(number)","url":"https://github.com/initech/gadgets/pull/\(number)","isDraft":false,\
    "state":"OPEN","createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z","closedAt":null,\
    "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"initech/gadgets"},\
    "author":{"login":"alice","avatarUrl":null},"comments":{"totalCount":0,"nodes":[]},\
    "commits":{"nodes":[]},"latestReviews":{"nodes":[]},"reviewRequests":{"nodes":[]}}
    """
}

private func page(_ nodes: [String], cursor: String, next: Bool) -> String {
    """
    {"data":{"search":{"pageInfo":{"endCursor":"\(cursor)","hasNextPage":\(next)},"nodes":[\(nodes.joined(separator: ","))]}}}
    """
}

@Suite struct GitHubAPITests {
    @Test func orgContextParses() async throws {
        let stub = StubTransport([
            (try fixture("viewer"), response(200)),
            (try fixture("org_context"), response(200)),
        ])
        let ctx = try await api(stub).orgContext(org: "initech")
        #expect(ctx.org == "initech")
        #expect(ctx.viewer == "devon")
        #expect(ctx.members.count == 4)
        #expect(ctx.myTeams.isEmpty)
        #expect(ctx.repos.count == 11)
        #expect(ctx.repos.contains("chat-assistant-old"))
        #expect(stub.bodies[1].contains("\"logins\":[\"devon\"]"))
    }

    @Test func organizationsParses() async throws {
        let stub = StubTransport([(try fixture("organizations"), response(200))])
        let orgs = try await api(stub).organizations()
        #expect(orgs == ["initech", "sozora"])
        #expect(stub.bodies[0].contains("organizations(first:100)"))
    }

    @Test func organizationsEmptyForNoOrgs() async throws {
        let stub = StubTransport(json: [#"{"data":{"viewer":{"organizations":{"nodes":[]}}}}"#])
        #expect(try await api(stub).organizations().isEmpty)
    }

    @Test func projectsParses() async throws {
        let stub = StubTransport([(try fixture("projects"), response(200))])
        let projects = try await api(stub).projects(owner: .org("initech"))
        #expect(projects.count == 3)
        #expect(projects.contains { $0.board == .org("initech", 3) && $0.title == "Team Board" })
        #expect(stub.bodies[0].contains("projectsV2(first:100"))
        #expect(stub.bodies[0].contains("organization(login:$login)"))
        #expect(stub.bodies[0].contains("\"login\":\"initech\""))
    }

    @Test func projectsThrowsForUnknownOrg() async {
        let stub = StubTransport(json: [#"{"data":{"organization":null}}"#])
        await #expect(throws: APIError.self) { try await api(stub).projects(owner: .org("nope")) }
    }

    @Test func searchFollowsPages() async throws {
        let stub = StubTransport(json: [
            page([prNode(1), prNode(2)], cursor: "CUR1", next: true),
            page([prNode(3)], cursor: "CUR2", next: false),
        ])
        let prs = try await api(stub).searchPRs("is:pr is:open org:initech")
        #expect(prs.map(\.key.number) == [1, 2, 3])
        #expect(stub.bodies.count == 2)
        #expect(!stub.bodies[0].contains("\"after\""))
        #expect(stub.bodies[1].contains("\"after\":\"CUR1\""))
    }

    @Test func searchSkipsBadNode() async throws {
        let stub = StubTransport(json: [
            page([prNode(1), prNode(2, includeNumber: false), "{}", prNode(3)], cursor: "C", next: false)
        ])
        let prs = try await api(stub).searchPRs("q")
        #expect(prs.map(\.key.number) == [1, 3])
    }

    @Test func lookupPartialErrors() async throws {
        let stub = StubTransport([(try fixture("number_lookup_partial"), response(200))])
        let result = try await api(stub).lookup(
            number: 42, org: "initech", repos: ["gadgets", "widgets", "docs"])
        #expect(result.prs.count == 1)
        #expect(result.prs[0].key == PRKey(repo: "initech/gadgets", number: 42))
        #expect(result.issues.count == 1)
        #expect(result.issues[0].key == PRKey(repo: "initech/widgets", number: 42))
        #expect(result.issues[0].isOpen)
        let body = stub.bodies[0]
        #expect(body.contains("r2: repository"))
        #expect(body.contains("\"n\":42"))
        #expect(body.contains("... on Issue{...issueRowFields}"))
        #expect(body.contains("fragment issueRowFields on Issue"))
    }

    @Test func lookupSkipsInvalidRepoNames() async throws {
        let stub = StubTransport(json: [#"{"data":{"r0":null}}"#])
        _ = try await api(stub).lookup(number: 1, org: "initech", repos: ["ok-repo", "bad\"name){x"])
        let body = stub.bodies[0]
        #expect(body.contains("ok-repo"))
        #expect(!body.contains("bad"))
        #expect(!body.contains("r1:"))
    }

    @Test func boardIssuesKeepsIssuesOnly() async throws {
        let stub = StubTransport([(try fixture("board_items"), response(200))])
        let issues = try await api(stub).boardIssues(.org("initech", 3))
        #expect(issues.map(\.key.number) == [42, 43])
        #expect(issues[0].isOpen)
        #expect(!issues[1].isOpen)
    }

    @Test func unauthorizedMaps() async {
        let stub = StubTransport([(Data("{}".utf8), response(401))])
        await #expect(throws: APIError.unauthorized) { try await api(stub).searchPRs("q") }
    }

    @Test func rateLimitMaps() async {
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1793050000"]
        let stub = StubTransport([(Data("{}".utf8), response(403, headers: headers))])
        await #expect(throws: APIError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_793_050_000))) {
            try await api(stub).searchPRs("q")
        }
    }

    @Test func secondaryRateLimitWithoutRetryAfterWaitsAMinute() async {
        let body = Data(#"{"message":"You have exceeded a secondary rate limit."}"#.utf8)
        let stub = StubTransport([(body, response(403))])
        await #expect(throws: APIError.rateLimited(resetAt: clockNow.addingTimeInterval(60))) {
            try await api(stub, now: clockNow).searchPRs("q")
        }
    }

    @Test func secondaryRateLimitHonorsRetryAfter() async {
        let body = Data(#"{"message":"You have exceeded a secondary rate limit."}"#.utf8)
        // The primary reset is an hour away; a secondary limit must not wait for it.
        let headers = ["retry-after": "30", "x-ratelimit-remaining": "4000", "x-ratelimit-reset": "1793003600"]
        let stub = StubTransport([(body, response(403, headers: headers))])
        await #expect(throws: APIError.rateLimited(resetAt: clockNow.addingTimeInterval(30))) {
            try await api(stub, now: clockNow).searchPRs("q")
        }
    }

    @Test func tooManyRequestsHonorsRetryAfter() async {
        let stub = StubTransport([(Data("{}".utf8), response(429, headers: ["Retry-After": "45"]))])
        await #expect(throws: APIError.rateLimited(resetAt: clockNow.addingTimeInterval(45))) {
            try await api(stub, now: clockNow).searchPRs("q")
        }
    }

    @Test func graphQLRateLimitedReadsResetHeader() async {
        let body = Data(#"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#.utf8)
        let headers = ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1793001200"]
        let stub = StubTransport([(body, response(200, headers: headers))])
        await #expect(throws: APIError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_793_001_200))) {
            try await api(stub, now: clockNow).searchPRs("q")
        }
    }

    @Test func graphQLRateLimitedReadsRetryAfter() async {
        let body = Data(#"{"errors":[{"type":"RATE_LIMITED","message":"slow down"}]}"#.utf8)
        let stub = StubTransport([(body, response(200, headers: ["retry-after": "20"]))])
        await #expect(throws: APIError.rateLimited(resetAt: clockNow.addingTimeInterval(20))) {
            try await api(stub, now: clockNow).searchPRs("q")
        }
    }

    @Test func graphQLRateLimitedWithoutHeadersWaitsAMinute() async {
        let body = Data(#"{"errors":[{"type":"RATE_LIMITED","message":"slow down"}]}"#.utf8)
        let stub = StubTransport([(body, response(200))])
        await #expect(throws: APIError.rateLimited(resetAt: clockNow.addingTimeInterval(60))) {
            try await api(stub, now: clockNow).searchPRs("q")
        }
    }

    // MARK: Paging

    @Test func orgContextPagesMembersAndRepos() async throws {
        let stub = StubTransport(json: [
            #"{"data":{"viewer":{"login":"me"}}}"#,
            """
            {"data":{"organization":{\
            "membersWithRole":{"pageInfo":{"endCursor":"M1","hasNextPage":true},"nodes":[{"login":"a"}]},\
            "teams":{"nodes":[{"slug":"core"}]},\
            "repositories":{"pageInfo":{"endCursor":"R1","hasNextPage":true},"nodes":[{"name":"r1"}]}}}}
            """,
            #"{"data":{"organization":{"membersWithRole":{"pageInfo":{"endCursor":"M2","hasNextPage":false},"nodes":[{"login":"b"}]}}}}"#,
            #"{"data":{"organization":{"repositories":{"pageInfo":{"endCursor":"R2","hasNextPage":true},"nodes":[{"name":"r2"}]}}}}"#,
            #"{"data":{"organization":{"repositories":{"pageInfo":{"endCursor":"R3","hasNextPage":false},"nodes":[{"name":"r3"}]}}}}"#,
        ])
        let ctx = try await api(stub).orgContext(org: "o")
        #expect(ctx.members == ["a", "b"])
        #expect(ctx.repos == ["r1", "r2", "r3"])
        #expect(ctx.reposComplete)
        #expect(ctx.myTeams == ["core"])
        let bodies = stub.bodies
        #expect(bodies.count == 5)
        #expect(bodies[2].contains("\"after\":\"M1\""))
        #expect(bodies[3].contains("\"after\":\"R1\""))
        #expect(bodies[4].contains("\"after\":\"R2\""))
    }

    @Test func orgRepoListAtPageCapIsIncomplete() async throws {
        func repoPage(_ n: Int, next: Bool) -> String {
            #"{"data":{"organization":{"repositories":{"pageInfo":{"endCursor":"R\#(n)","hasNextPage":\#(next)},"nodes":[{"name":"r\#(n)"}]}}}}"#
        }
        func first(next: Bool) -> String {
            """
            {"data":{"organization":{\
            "membersWithRole":{"pageInfo":{"endCursor":"M1","hasNextPage":false},"nodes":[{"login":"a"}]},\
            "teams":{"nodes":[]},\
            "repositories":{"pageInfo":{"endCursor":"R1","hasNextPage":\(next)},"nodes":[{"name":"r1"}]}}}}
            """
        }
        let viewer = #"{"data":{"viewer":{"login":"me"}}}"#
        let capped = StubTransport(json: [viewer, first(next: true)] + (2...10).map { repoPage($0, next: true) })
        let truncated = try await api(capped).orgContext(org: "o")
        #expect(truncated.repos.count == 10)
        #expect(!truncated.reposComplete)

        let below = StubTransport(json: [viewer, first(next: true)] + (2...9).map { repoPage($0, next: $0 < 9) })
        let full = try await api(below).orgContext(org: "o")
        #expect(full.repos.count == 9)
        #expect(full.reposComplete)

        let lastAtCap = StubTransport(json: [viewer, first(next: true)] + (2...10).map { repoPage($0, next: $0 < 10) })
        let exact = try await api(lastAtCap).orgContext(org: "o")
        #expect(exact.repos.count == 10)
        #expect(exact.reposComplete)
    }

    @Test func orgContextFromOldCacheIsIncomplete() throws {
        let old = #"{"org":"o","viewer":"me","members":["a"],"myTeams":["core"],"repos":["r1"]}"#
        let ctx = try JSONDecoder().decode(OrgContext.self, from: Data(old.utf8))
        #expect(ctx.repos == ["r1"])
        #expect(!ctx.reposComplete)
        let roundTrip = try JSONDecoder().decode(OrgContext.self, from: JSONEncoder().encode(
            OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: ["r1"], reposComplete: true)))
        #expect(roundTrip.reposComplete)
    }

    @Test func personalContextPagesTheViewersRepos() async throws {
        let stub = StubTransport(json: [
            #"{"data":{"viewer":{"login":"me","repositories":{"pageInfo":{"endCursor":"R1","hasNextPage":true},"nodes":[{"name":"r1"}]}}}}"#,
            #"{"data":{"viewer":{"repositories":{"pageInfo":{"endCursor":"R2","hasNextPage":false},"nodes":[{"name":"r2"}]}}}}"#,
        ])
        let ctx = try await api(stub).personalContext()
        #expect(ctx.scope == .personal(login: "me"))
        #expect(ctx.org == "me")
        #expect(ctx.viewer == "me")
        #expect(ctx.repos == ["r1", "r2"])
        #expect(ctx.reposComplete)
        #expect(ctx.members.isEmpty)
        #expect(ctx.myTeams.isEmpty)
        let bodies = stub.bodies
        #expect(bodies.count == 2)
        #expect(bodies[0].contains("ownerAffiliations:OWNER"))
        #expect(bodies[1].contains("\"after\":\"R1\""))
    }

    @Test func personalContextRoundTripsAndOldContextsAreOrgs() throws {
        let old = #"{"org":"o","viewer":"me","members":["a"],"myTeams":["core"],"repos":["r1"]}"#
        #expect(try JSONDecoder().decode(OrgContext.self, from: Data(old.utf8)).scope == .org("o"))
        let personal = OrgContext.personal(login: "me", repos: ["r1"], reposComplete: true)
        let decoded = try JSONDecoder().decode(OrgContext.self, from: JSONEncoder().encode(personal))
        #expect(decoded == personal)
        #expect(decoded.scope == .personal(login: "me"))
    }

    @Test func orgPageWithoutConnectionThrows() async throws {
        let stub = StubTransport(json: [
            #"{"data":{"viewer":{"login":"me"}}}"#,
            """
            {"data":{"organization":{\
            "membersWithRole":{"pageInfo":{"endCursor":"M1","hasNextPage":true},"nodes":[{"login":"a"}]},\
            "teams":{"nodes":[]},"repositories":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}
            """,
            #"{"data":{"organization":null},"errors":[{"message":"timeout"}]}"#,
        ])
        await #expect(throws: APIError.self) { try await api(stub).orgContext(org: "o") }
    }

    @Test func detailTotalsIgnoreUndecodableNodes() async throws {
        let body = """
        {"data":{"repository":{"pullRequest":{"body":"","updatedAt":"2026-10-25T14:03:11Z",\
        "changedFiles":2,"additions":3,"deletions":1,\
        "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS","contexts":{"totalCount":3,"nodes":[\
        {"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SUCCESS"},\
        {"__typename":"StatusContext","context":"b","state":"SUCCESS"},\
        {"__typename":"SomethingNew"}]}}}}]},\
        "latestReviews":{"nodes":[]},"comments":{"nodes":[]},\
        "files":{"totalCount":2,"nodes":[{"path":"x","additions":3,"deletions":1},{"additions":0}]}}}}}
        """
        let detail = try await api(StubTransport(json: [body])).detail(PRKey(repo: "o/r", number: 1))
        #expect(detail.checks.count == 2)
        #expect(!detail.checksTruncated)
        #expect(detail.files.count == 1)
        #expect(!detail.filesTruncated)
    }

    @Test func detailMapsSkippedAndNeutralRunsToSkipped() async throws {
        let body = """
        {"data":{"repository":{"pullRequest":{"body":"","updatedAt":"2026-10-25T14:03:11Z",\
        "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS","contexts":{"totalCount":3,\
        "checkRunCount":3,"statusContextCount":0,\
        "checkRunCountsByState":[{"state":"SKIPPED","count":2},{"state":"NEUTRAL","count":1}],"nodes":[\
        {"__typename":"CheckRun","name":"a","status":"COMPLETED","conclusion":"SKIPPED"},\
        {"__typename":"CheckRun","name":"b","status":"COMPLETED","conclusion":"NEUTRAL"},\
        {"__typename":"CheckRun","name":"c","status":"COMPLETED","conclusion":"SKIPPED"}]}}}}]},\
        "latestReviews":{"nodes":[]},"comments":{"nodes":[]},"files":{"totalCount":0,"nodes":[]}}}}}
        """
        let stub = StubTransport(json: [body])
        let detail = try await api(stub).detail(PRKey(repo: "o/r", number: 1))
        #expect(detail.checks.map(\.state) == [.skipped, .skipped, .skipped])
        // The rollup reads the same counts as the list, so the detail still matches its row.
        #expect(detail.ci == .skipped)
        #expect(stub.bodies[0].contains(Queries.rollupCounts))
    }

    @Test func searchPageCapReportsMore() async throws {
        let stub = StubTransport(json: [
            page([prNode(1)], cursor: "C1", next: true),
            page([prNode(2)], cursor: "C2", next: true),
            page([prNode(3)], cursor: "C3", next: false),
        ])
        let result = try await api(stub).searchPRs("q", maxPages: 2)
        #expect(result.prs.map(\.key.number) == [1, 2])
        #expect(result.hasMore)
        #expect(stub.bodies.count == 2)
    }

    @Test func cancelledRequestRethrowsCancellation() async {
        let api = GitHubAPI(transport: FailingTransport(error: URLError(.cancelled)), auth: StaticTokenSource("test-token"))
        await #expect(throws: CancellationError.self) { try await api.searchPRs("q") }
    }

    @Test func urlErrorMapsToNetwork() async {
        let api = GitHubAPI(transport: FailingTransport(error: URLError(.notConnectedToInternet)), auth: StaticTokenSource("test-token"))
        await #expect {
            try await api.searchPRs("q")
        } throws: { error in
            if case .network = error as? APIError { return true }
            return false
        }
    }

    @Test func serverErrorMaps() async {
        let stub = StubTransport([(Data(), response(502))])
        await #expect(throws: APIError.server(502)) { try await api(stub).searchPRs("q") }
    }

    /// The codes that mean no connectivity are offline; every other transport failure is unreachable.
    @Test(arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .callIsActive,
    ])
    func offlineURLErrorsMapToOffline(code: URLError.Code) async {
        let api = GitHubAPI(transport: FailingTransport(error: URLError(code)), auth: StaticTokenSource("test-token"))
        let error = await #expect(throws: APIError.self) { try await api.searchPRs("q") }
        guard case .network? = error else {
            Issue.record("\(code.rawValue) gave \(String(describing: error))")
            return
        }
        #expect(error.map(RefreshError.init) == .offline)
    }

    @Test(arguments: [
        (URLError.Code.secureConnectionFailed, "Couldn't reach GitHub (secure connection failed)"),
        (.serverCertificateUntrusted, "Couldn't reach GitHub (secure connection failed)"),
        (.serverCertificateHasBadDate, "Couldn't reach GitHub (secure connection failed)"),
        (.clientCertificateRequired, "Couldn't reach GitHub (secure connection failed)"),
        (.badServerResponse, "Couldn't reach GitHub (bad response)"),
        (.cannotParseResponse, "Couldn't reach GitHub (bad response)"),
        (.cannotDecodeContentData, "Couldn't reach GitHub (error -1016)"),
        (.httpTooManyRedirects, "Couldn't reach GitHub (error -1007)"),
        (.unknown, "Couldn't reach GitHub (error -1)"),
    ])
    func otherURLErrorsMapToUnreachable(code: URLError.Code, message: String) async {
        let api = GitHubAPI(transport: FailingTransport(error: URLError(code)), auth: StaticTokenSource("test-token"))
        await #expect(throws: APIError.unreachable(code)) { try await api.searchPRs("q") }
        #expect(RefreshError(APIError.unreachable(code)) == .unreachable(code))
        #expect(RefreshError(APIError.unreachable(code)).message == message)
    }

    /// A 403 that is neither single sign-on nor a rate limit is its own kind; the others keep theirs.
    @Test func plain403IsForbidden() async {
        let stub = StubTransport([(Data(#"{"message":"Resource not accessible by integration"}"#.utf8), response(403))])
        await #expect(throws: APIError.forbidden) { try await api(stub).searchPRs("q") }
        #expect(RefreshError(APIError.forbidden) == .forbidden)
        #expect(RefreshError.forbidden.message == "GitHub refused access (403)")
        let sso = StubTransport([(Data("{}".utf8), response(403, headers: ["X-GitHub-SSO": "required"]))])
        await #expect(throws: APIError.ssoRequired(nil)) { try await api(sso).searchPRs("q") }
        let limited = StubTransport([(Data("{}".utf8), response(403, headers: ["retry-after": "30"]))])
        await #expect(throws: APIError.rateLimited(resetAt: clockNow.addingTimeInterval(30))) {
            try await api(limited, now: clockNow).searchPRs("q")
        }
        let notFound = StubTransport([(Data(), response(404))])
        await #expect(throws: APIError.server(404)) { try await api(notFound).searchPRs("q") }
        #expect(RefreshError(APIError.server(404)) == .other("GitHub server error 404"))
    }

    @Test func insufficientScopesMaps() async {
        let stub = StubTransport(json: [#"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"needs read:org"}]}"#])
        await #expect(throws: APIError.insufficientScopes) { try await api(stub).searchPRs("q") }
    }

    @Test func errorsWithoutDataMapToGraphQL() async {
        let stub = StubTransport(json: [#"{"errors":[{"message":"boom"}]}"#])
        await #expect(throws: APIError.graphQL("boom")) { try await api(stub).searchPRs("q") }
    }

    @Test func detailParses() async throws {
        let stub = StubTransport([(try fixture("pr_detail"), response(200))])
        let key = PRKey(repo: "initech/gadgets", number: 412)
        let detail = try await api(stub).detail(key)
        #expect(detail.key == key)
        #expect(detail.checks.count == 5)
        #expect(detail.checks.first { $0.name == "test" }?.state == .failure)
        #expect(detail.checks.first { $0.name == "build" }?.state == .success)
        #expect(detail.checks.first { $0.name == "lint" }?.state == .pending)
        #expect(detail.checks.first { $0.name == "ci/deploy-preview" }?.state == .pending)
        #expect(detail.checks.first { $0.name == "ci/legacy" }?.state == .failure)
        #expect(detail.checks.first { $0.name == "ci/legacy" }?.url == nil)
        #expect(detail.files.count == 6)
        #expect(detail.comments.map(\.body) == ["First", "Second"])
        #expect(detail.reviews.first?.state == .approved)
        #expect(detail.updatedAt == ISO8601DateFormatter().date(from: "2026-10-25T13:00:00Z"))
        #expect(detail.ci == .failure)
        // PR-level totals, not the sums of the first page of files and checks.
        #expect(detail.changedFiles == 140)
        #expect(detail.additions == 1234)
        #expect(detail.deletions == 567)
        #expect(detail.checkCount == 73)
        #expect(detail.fileTotal == 140)
        #expect(detail.checkTotal == 73)
        #expect(stub.bodies[0].contains("changedFiles additions deletions"))
        #expect(stub.bodies[0].contains("\"owner\":\"initech\""))
        #expect(stub.bodies[0].contains("\"name\":\"gadgets\""))
    }
}

// MARK: - Token sources

private let authNow = Date(timeIntervalSince1970: 1_800_000_000)
private let octocat = AccountRef(login: "octocat", source: .gitHubApp)

/// Hands out `tokens` in turn (the last one repeats) and answers each `rejected` from `answers`.
private actor ScriptedTokenSource: TokenSource {
    private var tokens: [String]
    private var answers: [Result<Bool, any Error>]
    private(set) var rejections: [String] = []

    init(tokens: [String], answers: [Result<Bool, any Error>]) {
        self.tokens = tokens
        self.answers = answers
    }

    func token() async throws -> String {
        tokens.count > 1 ? tokens.removeFirst() : tokens[0]
    }

    func rejected(_ token: String) async throws -> Bool {
        rejections.append(token)
        return try answers.removeFirst().get()
    }
}

/// Answers 401 to `ghu_1`, a token GitHub has expired early, and a one-PR page to any other token.
/// Each 401 waits until `staleCount` requests have carried `ghu_1`, so every query sees one.
private final class ExpiredAtServerTransport: GraphQLTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let staleCount: Int
    private var staleArrivals = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var sentTokens: [String] = []

    init(staleCount: Int) { self.staleCount = staleCount }

    var tokens: [String] { lock.withLock { sentTokens } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { sentTokens.append(token) }
        guard token == "ghu_1" else {
            return (Data(page([prNode(1)], cursor: "C", next: false).utf8), response(200))
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                staleArrivals += 1
                parked.append(continuation)
                guard staleArrivals >= staleCount else { return [] }
                let all = parked
                parked = []
                return all
            }
            ready.forEach { $0.resume() }
        }
        return (Data("{}".utf8), response(401))
    }
}

/// github.com answering every OAuth request with HTTP 500.
private struct ServerErrorOAuth: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
    }
}

/// A broker holding octocat's `ghu_1`/`ghr_1` pair, refreshed against `FakeGitHubOAuth`.
private func broker(
    validRefreshTokens: Set<String>, accessExpiresAt: Date = authNow + 3600,
    oauth: ((FakeGitHubOAuth) -> any HTTPTransport)? = nil
) async -> (broker: TokenBroker, fake: FakeGitHubOAuth) {
    let store = InMemoryCredentialStore()
    store.items[1] = StoredCredential(
        userID: 1, login: "octocat",
        grant: TokenGrant(
            accessToken: "ghu_1", accessExpiresAt: accessExpiresAt, refreshToken: "ghr_1",
            refreshExpiresAt: authNow + 86_400 * 30))
    let fake = FakeGitHubOAuth(validRefreshTokens: validRefreshTokens)
    let broker = TokenBroker(
        store: store,
        deviceFlow: DeviceFlowClient(clientID: "Iv23test", transport: oauth?(fake) ?? fake, now: { authNow }),
        gh: GhCLI(searchPaths: [], fileExists: { _ in false }),
        now: { authNow })
    await broker.register([AccountSummary(userID: 1, login: "octocat")])
    return (broker, fake)
}

private func refreshRequests(_ fake: FakeGitHubOAuth) async -> Int {
    await fake.requests.filter { $0.form["grant_type"] == "refresh_token" }.count
}

extension GitHubAPITests {
    @Test func unauthorizedRetriesOnceWithNewToken() async throws {
        let stub = StubTransport([
            (Data("{}".utf8), response(401)),
            (Data(page([prNode(1)], cursor: "C", next: false).utf8), response(200)),
        ])
        let source = ScriptedTokenSource(tokens: ["ghu_old", "ghu_new"], answers: [.success(true)])
        let prs = try await GitHubAPI(transport: stub, auth: source).searchPRs("q")
        #expect(prs.map(\.key.number) == [1])
        #expect(stub.tokens == ["ghu_old", "ghu_new"])
        #expect(await source.rejections == ["ghu_old"])
    }

    @Test func unauthorizedTwiceThrows() async {
        let stub = StubTransport([(Data("{}".utf8), response(401)), (Data("{}".utf8), response(401))])
        let source = ScriptedTokenSource(tokens: ["ghu_old", "ghu_new"], answers: [.success(true), .success(true)])
        await #expect(throws: APIError.unauthorized) {
            try await GitHubAPI(transport: stub, auth: source).searchPRs("q")
        }
        #expect(stub.tokens == ["ghu_old", "ghu_new"])
        #expect(await source.rejections == ["ghu_old", "ghu_new"])
    }

    @Test func unauthorizedWithoutRetryThrowsAfterOneSend() async {
        let stub = StubTransport([(Data("{}".utf8), response(401))])
        let source = ScriptedTokenSource(tokens: ["gho_1"], answers: [.success(false)])
        await #expect(throws: APIError.unauthorized) {
            try await GitHubAPI(transport: stub, auth: source).searchPRs("q")
        }
        #expect(stub.tokens == ["gho_1"])
    }

    @Test func rejectedThatThrowsSignedOutPropagates() async {
        let stub = StubTransport([(Data("{}".utf8), response(401))])
        let source = ScriptedTokenSource(tokens: ["ghu_1"], answers: [.failure(AuthError.signedOut(octocat))])
        await #expect(throws: AuthError.signedOut(octocat)) {
            try await GitHubAPI(transport: stub, auth: source).searchPRs("q")
        }
        #expect(stub.tokens == ["ghu_1"])
    }

    @Test func oneRefreshAcrossConcurrentQueries() async throws {
        let (broker, fake) = await broker(validRefreshTokens: ["ghr_1"])
        let transport = ExpiredAtServerTransport(staleCount: 6)
        let api = GitHubAPI(transport: transport, auth: broker.source(for: octocat))
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<6 { group.addTask { try await api.searchPRs("q").count } }
            return try await group.reduce(into: [Int]()) { $0.append($1) }
        }
        #expect(counts == Array(repeating: 1, count: 6))
        #expect(await refreshRequests(fake) == 1)
        #expect(transport.tokens.filter { $0 == "ghu_1" }.count == 6)
        #expect(transport.tokens.filter { $0 == "ghu_rotated1" }.count == 6)
    }

    @Test func refreshFailureIsSignedOut() async {
        let (broker, fake) = await broker(validRefreshTokens: [])
        let api = GitHubAPI(transport: ExpiredAtServerTransport(staleCount: 6), auth: broker.source(for: octocat))
        let results = await withTaskGroup(of: Result<Int, any Error>.self) { group in
            for _ in 0..<6 {
                group.addTask {
                    do { return .success(try await api.searchPRs("q").count) } catch { return .failure(error) }
                }
            }
            return await group.reduce(into: [Result<Int, any Error>]()) { $0.append($1) }
        }
        #expect(results.count == 6)
        for result in results {
            #expect(throws: AuthError.signedOut(octocat)) { try result.get() }
        }
        #expect(await refreshRequests(fake) == 1)
    }

    @Test func ssoHeaderParses() async {
        let withURL = StubTransport([(Data("{}".utf8), response(403, headers: [
            "X-GitHub-SSO": "required; url=https://github.com/orgs/acme/sso?authorization_request=abc",
        ]))])
        let sso = URL(string: "https://github.com/orgs/acme/sso?authorization_request=abc")
        await #expect(throws: APIError.ssoRequired(sso)) {
            try await api(withURL).searchPRs("q")
        }
        let withoutURL = StubTransport([(Data("{}".utf8), response(403, headers: ["X-GitHub-SSO": "required"]))])
        await #expect(throws: APIError.ssoRequired(nil)) { try await api(withoutURL).searchPRs("q") }
        let rateLimit = StubTransport([(Data("{}".utf8), response(403, headers: [
            "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1793050000",
        ]))])
        await #expect(throws: APIError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_793_050_000))) {
            try await api(rateLimit).searchPRs("q")
        }
    }

    @Test func offlineRefreshMapsToOffline() async {
        let (broker, fake) = await broker(validRefreshTokens: ["ghr_1"], accessExpiresAt: authNow - 1)
        await fake.failNext(URLError(.notConnectedToInternet))
        let api = GitHubAPI(transport: ExpiredAtServerTransport(staleCount: 1), auth: broker.source(for: octocat))
        let error = await #expect(throws: APIError.self) { try await api.searchPRs("q") }
        guard case .network? = error else {
            Issue.record("gave \(String(describing: error))")
            return
        }
        #expect(error.map(RefreshError.init) == .offline)
    }

    /// A refresh GitHub answers with something other than an OAuth error (here HTTP 500) is a
    /// token-free poll error, retried later, not a sign-out.
    @Test func unexpectedRefreshFailureIsAnErrorNotASignOut() async throws {
        let (broker, _) = await broker(
            validRefreshTokens: ["ghr_1"], accessExpiresAt: authNow - 1, oauth: { _ in ServerErrorOAuth() })
        let api = GitHubAPI(transport: ExpiredAtServerTransport(staleCount: 1), auth: broker.source(for: octocat))
        for _ in 0..<2 {
            let error = await #expect(throws: (any Error).self) { try await api.searchPRs("q") }
            let mapped = error.map(RefreshError.init)
            #expect(mapped == .other("Couldn't renew the GitHub sign-in (HTTP 500)"))
            #expect(mapped?.message.contains("ghu_") == false)
            #expect(mapped?.message.contains("ghr_") == false)
        }
    }
}
