import Foundation
import Testing
@testable import PullBullKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private struct Reply {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
}

private actor StubHTTP: HTTPTransport {
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let reply = replies.count > 1 ? replies.removeFirst() : replies[0]
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (reply.body, response)
    }
}

private struct FailingHTTP: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.notConnectedToInternet) }
}

private actor RejectingSource: TokenSource {
    private var tokens: [String]
    private let retry: Bool
    private(set) var rejectedTokens: [String] = []

    init(tokens: [String], retry: Bool) {
        self.tokens = tokens
        self.retry = retry
    }

    func token() async throws -> String { tokens.count > 1 ? tokens.removeFirst() : tokens[0] }

    func rejected(_ token: String) async throws -> Bool {
        rejectedTokens.append(token)
        return retry
    }
}

private func checker(_ http: any HTTPTransport, auth: any TokenSource = StaticTokenSource("t")) -> AccessChecker {
    AccessChecker(transport: http, auth: auth, appSlug: "pullbull-for-macos")
}

private func ok(_ name: String) throws -> Reply { Reply(body: try fixture(name)) }

private func installationsPage(count: Int, total: Int, offset: Int = 0) -> Reply {
    let items = (0..<count).map {
        #"{"id":\#(offset + $0),"account":{"login":"org\#(offset + $0)"},"repository_selection":"all","permissions":{}}"#
    }
    return Reply(body: Data(#"{"total_count":\#(total),"installations":[\#(items.joined(separator: ","))]}"#.utf8))
}

private let installURL = URL(string: "https://github.com/apps/pullbull-for-macos/installations/new")!

@Suite struct AccessCheckerTests {
    @Test func identityDecodes() async throws {
        let http = StubHTTP([try ok("user")])
        let identity = try await checker(http).identity()
        #expect(identity == GitHubIdentity(
            login: "octocat", userID: 583231,
            avatarURL: URL(string: "https://avatars.githubusercontent.com/u/583231?v=4")))

        let request = try #require(await http.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/user")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    }

    @Test func allRepositories() async throws {
        let http = StubHTTP([try ok("installations_all")])
        #expect(try await checker(http).access(for: "acme") == .ok(allRepos: true, canReadProjects: true))
    }

    @Test func selectedRepositories() async throws {
        let http = StubHTTP([try ok("installations_selected")])
        #expect(try await checker(http).access(for: "acme") == .ok(allRepos: false, canReadProjects: true))
    }

    @Test func missingOrg() async throws {
        let http = StubHTTP([try ok("installations_other_org")])
        #expect(try await checker(http).access(for: "acme") == .notInstalled(installURL))
    }

    @Test func missingProjectsPermission() async throws {
        let http = StubHTTP([try ok("installations_no_projects")])
        #expect(try await checker(http).access(for: "acme") == .ok(allRepos: true, canReadProjects: false))
    }

    @Test func orgMatchIsCaseInsensitive() async throws {
        let http = StubHTTP([try ok("installations_all")])
        #expect(try await checker(http).access(for: "ACME") == .ok(allRepos: true, canReadProjects: true))
    }

    @Test func installationParsesFields() async throws {
        let http = StubHTTP([try ok("installations_selected")])
        let list = try await checker(http).installations()
        #expect(list == [Installation(
            id: 1, org: "acme", allRepositories: false,
            permissions: ["metadata": "read", "organization_projects": "write", "pull_requests": "read"])])
        #expect(list[0].canReadProjects)
    }

    @Test func projectsPermissionLevels() {
        func installation(_ level: String?) -> Installation {
            Installation(org: "a", allRepositories: true, permissions: level.map { ["organization_projects": $0] } ?? [:])
        }
        #expect(installation("read").canReadProjects)
        #expect(installation("write").canReadProjects)
        #expect(installation("admin").canReadProjects)
        #expect(!installation("none").canReadProjects)
        #expect(!installation(nil).canReadProjects)
    }

    @Test func staticLookupAndInstallURL() {
        let list = [Installation(org: "Acme", allRepositories: false, permissions: [:])]
        #expect(AccessChecker.access(for: "acme", in: list, appSlug: "pullbull-for-macos") == .ok(allRepos: false, canReadProjects: false))
        #expect(AccessChecker.access(for: "x", in: list, appSlug: "pullbull-for-macos") == .notInstalled(installURL))
        #expect(AccessChecker.installURL(appSlug: "pullbull-for-macos") == installURL)
    }

    @Test func userInstallationIsNotAnOrg() async throws {
        let http = StubHTTP([try ok("installations_user")])
        let list = try await checker(http).installations()
        #expect(list.map(\.org) == ["octocat", "acme"])
        #expect(list.map(\.isOrganization) == [false, true])
    }

    @Test func userInstallationNeverGrantsOrgAccess() async throws {
        let http = StubHTTP([try ok("installations_user")])
        #expect(try await checker(http).access(for: "octocat") == .notInstalled(installURL))
        #expect(try await checker(http).access(for: "acme") == .ok(allRepos: true, canReadProjects: true))
    }

    /// No org: the installation on the user's own account is the one that counts, never an org's.
    @Test func personalScopeUsesTheUsersOwnInstallation() async throws {
        let list = try await checker(StubHTTP([try ok("installations_user")])).installations()
        #expect(AccessChecker.access(for: .personal(login: "octocat"), in: list, appSlug: "pullbull-for-macos")
            == .ok(allRepos: true, canReadProjects: false))
        #expect(AccessChecker.access(for: .personal(login: "OctoCat"), in: list, appSlug: "pullbull-for-macos")
            == .ok(allRepos: true, canReadProjects: false))
        #expect(AccessChecker.access(for: .org("acme"), in: list, appSlug: "pullbull-for-macos")
            == .ok(allRepos: true, canReadProjects: true))
        // An org's installation is not the user's.
        #expect(AccessChecker.access(for: .personal(login: "acme"), in: list, appSlug: "pullbull-for-macos") == .notInstalled(installURL))
    }

    @Test func personalScopeWithSelectedRepositories() {
        let list = [
            Installation(org: "solo", allRepositories: false, permissions: [:], isOrganization: false),
            Installation(org: "acme", allRepositories: true, permissions: [:]),
        ]
        #expect(AccessChecker.access(for: .personal(login: "solo"), in: list, appSlug: "pullbull-for-macos")
            == .ok(allRepos: false, canReadProjects: false))
    }

    @Test func personalScopeWithoutAnyInstallation() {
        #expect(AccessChecker.access(for: .personal(login: "solo"), in: [], appSlug: "pullbull-for-macos") == .notInstalled(installURL))
    }

    /// The repositories a selected-repos installation covers, every page, as lowercased `owner/name`.
    @Test func installationRepositoriesPage() async throws {
        func page(_ names: [String], total: Int) -> Reply {
            let items = names.map { #"{"full_name":"\#($0)","name":"x"}"# }.joined(separator: ",")
            return Reply(body: Data(#"{"total_count":\#(total),"repositories":[\#(items)]}"#.utf8))
        }
        let first = (0..<100).map { "solo/r\($0)" }
        let http = StubHTTP([page(first, total: 101), page(["Solo/Dotfiles"], total: 101)])
        let repos = try await checker(http).repositories(installationID: 42)
        #expect(repos.count == 101)
        #expect(repos.contains("solo/dotfiles"))
        let urls = await http.requests.map { $0.url?.absoluteString }
        #expect(urls == [
            "https://api.github.com/user/installations/42/repositories?per_page=100&page=1",
            "https://api.github.com/user/installations/42/repositories?per_page=100&page=2",
        ])
    }

    @Test func repositoriesThrowAtThePageCapRatherThanTruncate() async {
        let full = Reply(body: Data(("{\"total_count\":1500,\"repositories\":["
            + (0..<100).map { #"{"full_name":"solo/r\#($0)"}"# }.joined(separator: ",") + "]}").utf8))
        await #expect(throws: APIError.self) { try await checker(StubHTTP([full])).repositories(installationID: 1) }
    }

    private static let soloAll = Installation(id: 7, org: "solo", allRepositories: true, permissions: [:], isOrganization: false)
    private static let soloSelected = Installation(
        id: 7, org: "Solo", allRepositories: false, permissions: [:], isOrganization: false)
    private static let acmeSelected = Installation(id: 8, org: "acme", allRepositories: false, permissions: [:])

    /// All repositories, or no installation on the user's account: every owned repo, with no request.
    @Test func personalReposAllNeedsNoRead() async {
        let http = StubHTTP([Reply(status: 500)])
        #expect(await checker(http).personalRepos(of: "solo", in: [Self.soloAll], previous: nil) == .all)
        #expect(await checker(http).personalRepos(of: "solo", in: [Self.acmeSelected], previous: nil) == .all)
        #expect(await http.requests.isEmpty)
    }

    /// GitHub's casing ("Solo/Dotfiles") is normalised, so items in any casing are covered.
    @Test func personalReposAreReadAndNormalised() async {
        let body = #"{"total_count":1,"repositories":[{"full_name":"Solo/Dotfiles"}]}"#
        let http = StubHTTP([Reply(body: Data(body.utf8))])
        let result = await checker(http).personalRepos(of: "solo", in: [Self.soloSelected, Self.acmeSelected], previous: nil)
        #expect(result == .selected(["solo/dotfiles"]))
        let scope = FetchScope.personal(login: "solo", repos: result.repos)
        #expect(scope.covers("SOLO/dotfiles"))
        #expect(scope.covers("solo/DotFiles"))
        #expect(!scope.covers("solo/mtbfit"))
        let urls = await http.requests.map { $0.url?.absoluteString }
        #expect(urls == ["https://api.github.com/user/installations/7/repositories?per_page=100&page=1"])
    }

    /// A failed read keeps the set read before; with none it is unreadable, never every owned repo.
    @Test func personalReposFailureKeepsThePreviousSetOrWaits() async {
        let failing = StubHTTP([Reply(status: 502)])
        #expect(await checker(failing).personalRepos(of: "solo", in: [Self.soloSelected], previous: ["solo/a"])
            == .selected(["solo/a"]))
        let unreadable = await checker(failing).personalRepos(of: "solo", in: [Self.soloSelected], previous: nil)
        #expect(unreadable == .unreadable(.other("Couldn't load the repositories PullBull can see")))
        #expect(unreadable.repos == nil)
        #expect(await checker(FailingHTTP()).personalRepos(of: "solo", in: [Self.soloSelected], previous: nil)
            == .unreadable(.offline))
    }

    /// An installation without an ID is a failed read, with no request.
    @Test func personalReposWithoutAnInstallationIDIsUnreadable() async {
        let http = StubHTTP([Reply(status: 500)])
        let noID = Installation(org: "solo", allRepositories: false, permissions: [:], isOrganization: false)
        #expect(await checker(http).personalRepos(of: "solo", in: [noID], previous: nil)
            == .unreadable(.other("Couldn't load the repositories PullBull can see")))
        #expect(await checker(http).personalRepos(of: "solo", in: [noID], previous: ["solo/a"]) == .selected(["solo/a"]))
        #expect(await http.requests.isEmpty)
    }

    @Test func personalInstallationIsFound() async throws {
        let list = try await checker(StubHTTP([try ok("installations_user")])).installations()
        #expect(AccessChecker.personalInstallation(of: "OctoCat", in: list)?.id == 1)
        #expect(AccessChecker.personalInstallation(of: "acme", in: list) == nil)
    }

    @Test func installURLPreselectsTheUsersAccount() {
        #expect(AccessChecker.installURL(appSlug: "pullbull-for-macos", targetID: 1234).absoluteString
            == "https://github.com/apps/pullbull-for-macos/installations/new/permissions?target_id=1234")
        #expect(AccessChecker.installationSettingsURL(id: 42).absoluteString
            == "https://github.com/settings/installations/42")
    }

    @Test func installURLEncodesMalformedSlug() {
        #expect(
            AccessChecker.installURL(appSlug: "pull bar").absoluteString
                == "https://github.com/apps/pull%20bar/installations/new")
        #expect(
            AccessChecker.installURL(appSlug: "a/b").absoluteString
                == "https://github.com/apps/a%2Fb/installations/new")
    }

    @Test func rateLimited403IsRateLimited() async {
        let http = StubHTTP([Reply(status: 403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1800000000"])])
        await #expect(throws: APIError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_800_000_000))) {
            try await checker(http).installations()
        }
    }

    @Test func http429IsRateLimited() async {
        let http = StubHTTP([Reply(status: 429, headers: ["retry-after": "30"])])
        let error = await #expect(throws: APIError.self) { try await checker(http).access(for: "acme") }
        guard case .rateLimited(let resetAt?) = error else {
            Issue.record("gave \(String(describing: error))")
            return
        }
        #expect(resetAt > Date())
    }

    @Test func plain403IsForbidden() async {
        let http = StubHTTP([Reply(status: 403)])
        await #expect(throws: APIError.forbidden) { try await checker(http).installations() }
    }

    @Test func paginates() async throws {
        let http = StubHTTP([
            installationsPage(count: 100, total: 150),
            installationsPage(count: 50, total: 150, offset: 100),
        ])
        let list = try await checker(http).installations()
        #expect(list.count == 150)
        let urls = await http.requests.map { $0.url?.absoluteString }
        #expect(urls == [
            "https://api.github.com/user/installations?per_page=100&page=1",
            "https://api.github.com/user/installations?per_page=100&page=2",
        ])
    }

    @Test func stopsWhenTotalReached() async throws {
        let http = StubHTTP([installationsPage(count: 100, total: 100)])
        #expect(try await checker(http).installations().count == 100)
        #expect(await http.requests.count == 1)
    }

    @Test func stopsAtTenPages() async throws {
        let http = StubHTTP([installationsPage(count: 100, total: 5000)])
        #expect(try await checker(http).installations().count == 1000)
        #expect(await http.requests.count == 10)
    }

    @Test func ssoRequiredHeader() async throws {
        let sso = "https://github.com/orgs/acme/sso?authorization_request=abc"
        let http = StubHTTP([Reply(status: 403, headers: ["X-GitHub-SSO": "required; url=\(sso)"])])
        #expect(try await checker(http).access(for: "acme") == .ssoRequired(URL(string: sso)))
    }

    @Test func ssoWinsOverRateLimit() async throws {
        let sso = "https://github.com/orgs/acme/sso?authorization_request=abc"
        let http = StubHTTP([Reply(
            status: 403, headers: ["X-GitHub-SSO": "required; url=\(sso)", "x-ratelimit-remaining": "0"])])
        #expect(try await checker(http).access(for: "acme") == .ssoRequired(URL(string: sso)))
    }

    @Test func identityPropagatesSSOError() async {
        let http = StubHTTP([Reply(status: 403, headers: ["X-GitHub-SSO": "required"])])
        await #expect(throws: APIError.ssoRequired(nil)) { try await checker(http).identity() }
    }

    @Test func unauthorizedUsesTokenSource() async throws {
        let auth = RejectingSource(tokens: ["old", "new"], retry: true)
        let http = StubHTTP([Reply(status: 401), try ok("installations_all")])
        let access = try await checker(http, auth: auth).access(for: "acme")
        #expect(access == .ok(allRepos: true, canReadProjects: true))
        #expect(await auth.rejectedTokens == ["old"])
        let sent = await http.requests.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(sent == ["Bearer old", "Bearer new"])
    }

    @Test func unauthorizedWithoutRetryThrows() async {
        let auth = RejectingSource(tokens: ["old"], retry: false)
        let http = StubHTTP([Reply(status: 401)])
        await #expect(throws: APIError.unauthorized) { try await checker(http, auth: auth).installations() }
        #expect(await http.requests.count == 1)
    }

    @Test func secondUnauthorizedThrowsAfterOneRetry() async {
        let auth = RejectingSource(tokens: ["a", "b"], retry: true)
        let http = StubHTTP([Reply(status: 401)])
        await #expect(throws: APIError.unauthorized) { try await checker(http, auth: auth).installations() }
        #expect(await http.requests.count == 2)
        #expect(await auth.rejectedTokens == ["a", "b"])
    }

    @Test func otherStatusIsServerError() async {
        let http = StubHTTP([Reply(status: 500)])
        await #expect(throws: APIError.server(500)) { try await checker(http).installations() }
    }

    @Test func urlErrorMapsToNetwork() async {
        await #expect(throws: APIError.self) { try await checker(FailingHTTP()).installations() }
    }

    /// One installation that doesn't decode is skipped; the rest of the list still counts.
    @Test func oddInstallationIsSkipped() async throws {
        let body = #"""
            {"total_count":3,"installations":[
            {"id":1,"account":{"login":"acme","type":"Organization"},"repository_selection":"all","permissions":{}},
            {"id":2,"account":null,"repository_selection":"all","permissions":{}},
            {"id":3,"account":{"login":"beta","type":"Organization"},"repository_selection":"selected",
             "permissions":{"organization_projects":["read"]}}]}
            """#
        let http = StubHTTP([Reply(body: Data(body.utf8))])
        #expect(try await checker(http).installations().map(\.org) == ["acme"])
    }

    /// Skipped items still count toward the page size, so paging goes on past them.
    @Test func skippedInstallationsStillCountForPaging() async throws {
        let odd = #"{"id":0,"account":null,"repository_selection":"all","permissions":{}}"#
        let items = [odd] + (1..<100).map {
            #"{"id":\#($0),"account":{"login":"org\#($0)"},"repository_selection":"all","permissions":{}}"#
        }
        let first = Reply(body: Data(#"{"total_count":101,"installations":[\#(items.joined(separator: ","))]}"#.utf8))
        let http = StubHTTP([first, installationsPage(count: 1, total: 101, offset: 100)])
        #expect(try await checker(http).installations().count == 100)
        #expect(await http.requests.count == 2)
    }

    @Test func malformedBodyThrows() async {
        let http = StubHTTP([Reply(body: Data("nope".utf8))])
        let malformed = APIError.graphQL("malformed response")
        await #expect(throws: malformed) { try await checker(http).installations() }
        await #expect(throws: malformed) { try await checker(http).identity() }
    }

    @Test func accessPropagatesNonSSOErrors() async {
        let http = StubHTTP([Reply(status: 500)])
        await #expect(throws: APIError.server(500)) { try await checker(http).access(for: "acme") }
    }
}

@Suite struct AppSlugValidationTests {
    @Test func acceptsLowercaseDigitsAndHyphens() {
        #expect(AccessChecker.isValidAppSlug("pullbull"))
        #expect(AccessChecker.isValidAppSlug("my-app-2"))
    }

    @Test(arguments: ["", "PullBull", "a/b", "a%20b", "pullbär"])
    func rejectsEverythingElse(_ slug: String) {
        #expect(!AccessChecker.isValidAppSlug(slug))
    }
}
