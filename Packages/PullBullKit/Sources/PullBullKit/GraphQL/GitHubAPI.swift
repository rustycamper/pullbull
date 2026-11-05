import CryptoKit
import Foundation

public protocol GraphQLTransport: Sendable {
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse)
    /// A REST request to `https://api.github.com` + `path` with a JSON body.
    func send(_ method: String, path: String, body: Data, token: String) async throws -> (Data, HTTPURLResponse)
}

extension GraphQLTransport {
    /// Transports that never send REST (most test doubles) refuse it.
    public func send(_ method: String, path: String, body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        throw APIError.server(501)
    }
}

public enum APIError: Error, Equatable {
    case unauthorized
    case rateLimited(resetAt: Date?)
    /// No connectivity (`URLError.Code.meansOffline`).
    case network(String)
    /// Any other transport failure: TLS, a bad response, … (`URLError.Code.unreachableReason`).
    case unreachable(URLError.Code)
    case server(Int)
    /// A 403 that is neither single sign-on nor a rate limit.
    case forbidden
    case graphQL(String)
    case insufficientScopes
    /// A 403 with `X-GitHub-SSO: required`: the org uses SAML single sign-on and this token has no
    /// active SSO session. The URL (from the header, valid for an hour) starts one.
    case ssoRequired(URL?)
    /// GitHub answered FORBIDDEN for a board or an owner's board list: this token may not read it
    /// (a GitHub App's sign-in can't read personal boards).
    case boardForbidden
    /// The PR or issue a detail fetch asked for doesn't exist (deleted or transferred); the message
    /// is the one shown.
    case notFound(String)
    /// GitHub refused a write (`FORBIDDEN`): this token or user may not change it. The message is GitHub's.
    case writeRefused(String)
}

/// Which parts of a label or assignee change GitHub applied. A part with nothing to send counts as
/// applied. `refusal` is GitHub's reason when a part wasn't.
public struct SetChangeResult: Equatable, Sendable {
    public let addApplied: Bool
    public let removeApplied: Bool
    public let refusal: String?

    public init(addApplied: Bool, removeApplied: Bool, refusal: String?) {
        self.addApplied = addApplied
        self.removeApplied = removeApplied
        self.refusal = refusal
    }
}

public struct OrgContext: Codable, Sendable, Equatable {
    public let org: String
    public let viewer: String
    public let members: [String]
    public let myTeams: Set<String>
    public let repos: [String]
    /// True only when `repos` ended because there were no more pages, not because the page cap was hit.
    public let reposComplete: Bool
    /// The personal scope's context: `org` is the viewer's login, `repos` the repositories they own,
    /// and there are no members or teams.
    public let isPersonal: Bool
    /// The personal scope is limited to `repos` (an app installation's selected repositories).
    public let limitedToRepos: Bool

    public init(
        org: String, viewer: String, members: [String], myTeams: Set<String>, repos: [String],
        reposComplete: Bool = true
    ) {
        self.init(
            org: org, viewer: viewer, members: members, myTeams: myTeams, repos: repos,
            reposComplete: reposComplete, isPersonal: false, limitedToRepos: false)
    }

    private init(
        org: String, viewer: String, members: [String], myTeams: Set<String>, repos: [String],
        reposComplete: Bool, isPersonal: Bool, limitedToRepos: Bool
    ) {
        self.org = org
        self.viewer = viewer
        self.members = members
        self.myTeams = myTeams
        self.repos = repos
        self.reposComplete = reposComplete
        self.isPersonal = isPersonal
        self.limitedToRepos = limitedToRepos
    }

    /// The context of an account in no org: the repositories `login` owns (or, `limitedToRepos`, the
    /// ones its installation covers).
    public static func personal(
        login: String, repos: [String], reposComplete: Bool, limitedToRepos: Bool = false
    ) -> OrgContext {
        OrgContext(
            org: login, viewer: login, members: [], myTeams: [], repos: repos, reposComplete: reposComplete,
            isPersonal: true, limitedToRepos: limitedToRepos)
    }

    public var scope: FetchScope {
        guard isPersonal else { return .org(org) }
        let limit = limitedToRepos ? Set(repos.map { "\(org)/\($0)".lowercased() }) : nil
        return .personal(login: viewer, repos: limit)
    }

    /// This context for `scope`: a personal one takes the scope's repositories (those `login` owns) as
    /// its repos, or drops a limit the scope no longer has. Anything else is returned as it is.
    public func limited(to scope: FetchScope) -> OrgContext {
        guard isPersonal, case .personal(let login, let repos) = scope else { return self }
        guard let repos else {
            return limitedToRepos ? .personal(login: org, repos: self.repos, reposComplete: false) : self
        }
        let names = repos.sorted().compactMap { repo -> String? in
            let parts = repo.split(separator: "/", maxSplits: 1)
            guard parts.count == 2, String(parts[0]).caseInsensitiveCompare(login) == .orderedSame else { return nil }
            return String(parts[1])
        }
        return .personal(login: org, repos: names, reposComplete: true, limitedToRepos: true)
    }

    private enum CodingKeys: String, CodingKey {
        case org, viewer, members, myTeams, repos, reposComplete, isPersonal, limitedToRepos
    }

    /// A cache written before `reposComplete` existed counts as incomplete; one written before the
    /// personal scope is an org's.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        org = try container.decode(String.self, forKey: .org)
        viewer = try container.decode(String.self, forKey: .viewer)
        members = try container.decode([String].self, forKey: .members)
        myTeams = try container.decode(Set<String>.self, forKey: .myTeams)
        repos = try container.decode([String].self, forKey: .repos)
        reposComplete = try container.decodeIfPresent(Bool.self, forKey: .reposComplete) ?? false
        isPersonal = try container.decodeIfPresent(Bool.self, forKey: .isPersonal) ?? false
        limitedToRepos = try container.decodeIfPresent(Bool.self, forKey: .limitedToRepos) ?? false
    }

    /// `isPersonal` and `limitedToRepos` are written only when true, so an org's cache keeps the format
    /// older builds read.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(org, forKey: .org)
        try container.encode(viewer, forKey: .viewer)
        try container.encode(members, forKey: .members)
        try container.encode(myTeams, forKey: .myTeams)
        try container.encode(repos, forKey: .repos)
        try container.encode(reposComplete, forKey: .reposComplete)
        if isPersonal { try container.encode(isPersonal, forKey: .isPersonal) }
        if limitedToRepos { try container.encode(limitedToRepos, forKey: .limitedToRepos) }
    }
}

public struct Check: Codable, Sendable, Hashable {
    public let name: String
    public let state: CIState
    public let url: URL?

    public init(name: String, state: CIState, url: URL?) {
        self.name = name
        self.state = state
        self.url = url
    }
}

public struct Comment: Codable, Sendable, Hashable {
    /// The comment's node ID; nil for a comment read before ids were kept.
    public let id: String?
    public let author: String
    /// Whether the author is a bot; nil for a comment read before the author's type was kept.
    public let authorIsBot: Bool?
    public let body: String
    public let createdAt: Date

    public init(id: String? = nil, author: String, authorIsBot: Bool? = nil, body: String, createdAt: Date) {
        self.id = id
        self.author = author
        self.authorIsBot = authorIsBot
        self.body = body
        self.createdAt = createdAt
    }
}

public struct ChangedFile: Codable, Sendable, Hashable {
    public let path: String
    public let additions: Int
    public let deletions: Int

    public init(path: String, additions: Int, deletions: Int) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
    }

    /// The last path component, which the files list leads with: "Metrics.swift" for "PullBull/Style/Metrics.swift".
    public var fileName: String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Everything before the last "/", or "" for a file at the repo root.
    public var directory: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// This file's diff on the PR's Files changed page: `<pr url>/files#diff-<sha256 of the path>`.
    /// GitHub hashes the raw UTF-8 path (the new path for a rename), and the host is the PR's own.
    public func diffURL(in prURL: URL) -> URL {
        let files = prURL.appendingPathComponent("files")
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        var components = URLComponents(url: files, resolvingAgainstBaseURL: false)
        components?.fragment = "diff-\(digest)"
        return components?.url ?? files
    }
}

public struct PRDetail: Codable, Sendable {
    public let key: PRKey
    public let body: String
    public let checks: [Check]
    public let reviews: [Review]
    public let comments: [Comment]
    public let files: [ChangedFile]
    /// The PR's `updatedAt` and head-commit rollup state when this detail was fetched; nil in details
    /// cached before they were stored.
    public let updatedAt: Date?
    public let ci: CIState?
    /// PR-level totals; `files` and `checks` hold only the first page. Nil in details cached before
    /// they were stored, where the totals fall back to the lists.
    public let changedFiles: Int?
    public let additions: Int?
    public let deletions: Int?
    public let checkCount: Int?
    /// Pending review requests; nil in details cached before they were stored.
    public let requests: [Reviewer]?
    /// Every comment on the PR; `comments` holds the newest 50. Nil in details cached before it was stored.
    public let commentCount: Int?
    /// The head commit, the author ("ghost" for a deleted account) and the state when this detail was
    /// fetched; nil in details cached before they were stored.
    public let headOid: String?
    public let author: String?
    public let state: PRState?
    /// What the merge panel needs; nil in details cached before it was stored.
    public let merge: MergeInfo?

    public init(
        key: PRKey, body: String, checks: [Check], reviews: [Review],
        comments: [Comment], files: [ChangedFile], updatedAt: Date? = nil, ci: CIState? = nil,
        changedFiles: Int? = nil, additions: Int? = nil, deletions: Int? = nil, checkCount: Int? = nil,
        requests: [Reviewer]? = nil, commentCount: Int? = nil,
        headOid: String? = nil, author: String? = nil, state: PRState? = nil,
        merge: MergeInfo? = nil
    ) {
        self.key = key
        self.body = body
        self.checks = checks
        self.reviews = reviews
        self.comments = comments
        self.files = files
        self.updatedAt = updatedAt
        self.ci = ci
        self.changedFiles = changedFiles
        self.additions = additions
        self.deletions = deletions
        self.checkCount = checkCount
        self.requests = requests
        self.commentCount = commentCount
        self.headOid = headOid
        self.author = author
        self.state = state
        self.merge = merge
    }

    public var commentTotal: Int { max(commentCount ?? 0, comments.count) }
    /// The comments older than those held, counted above them on the page, as on an issue page.
    public var earlierCommentCount: Int { commentTotal - comments.count }
    public var fileTotal: Int { max(changedFiles ?? 0, files.count) }
    public var additionsTotal: Int { additions ?? files.reduce(0) { $0 + $1.additions } }
    public var deletionsTotal: Int { deletions ?? files.reduce(0) { $0 + $1.deletions } }
    public var checkTotal: Int { max(checkCount ?? 0, checks.count) }
    /// Whether the lists hold fewer entries than the PR has.
    public var filesTruncated: Bool { fileTotal > files.count }
    public var checksTruncated: Bool { checkTotal > checks.count }

    /// Whether this detail still matches the list data for `pr`. A finished CI run does not bump
    /// `updatedAt`, so the rollup state is compared as well.
    public func isCurrent(for pr: PullRequest) -> Bool {
        guard let updatedAt, let ci else { return false }
        return updatedAt == pr.updatedAt && ci == pr.ci
    }
}

/// A pull request that closes an issue (`closedByPullRequestsReferences`), open or not.
public struct LinkedPR: Codable, Sendable, Hashable {
    public let key: PRKey
    public let title: String
    public let url: URL
    public let state: PRState
    /// "ghost" for a deleted author.
    public let author: String
    public let ci: CIState
    /// False in details cached before it was stored.
    public let isDraft: Bool

    public var glyph: PRGlyph { PRGlyph(state: state, isDraft: isDraft) }

    public init(
        key: PRKey, title: String, url: URL, state: PRState, author: String, ci: CIState, isDraft: Bool = false
    ) {
        self.key = key
        self.title = title
        self.url = url
        self.state = state
        self.author = author
        self.ci = ci
        self.isDraft = isDraft
    }

    /// Linked PRs cached before `isDraft` was stored read as not drafts.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(PRKey.self, forKey: .key)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(URL.self, forKey: .url)
        state = try c.decode(PRState.self, forKey: .state)
        author = try c.decode(String.self, forKey: .author)
        ci = try c.decode(CIState.self, forKey: .ci)
        isDraft = try c.decodeIfPresent(Bool.self, forKey: .isDraft) ?? false
    }
}

/// The detail of one issue.
public struct IssueDetail: Codable, Sendable, Equatable {
    public let key: PRKey
    /// The row fields, read with the same fragment as the lists; `status` and `boardItemId` are nil
    /// (they come from the board).
    public let issue: BoardIssue
    public let body: String
    public let commentTotal: Int
    /// Oldest first, at most 2.
    public let lastComments: [Comment]
    public let linkedPRs: [LinkedPR]

    public init(
        key: PRKey, issue: BoardIssue, body: String, commentTotal: Int, lastComments: [Comment], linkedPRs: [LinkedPR]
    ) {
        self.key = key
        self.issue = issue
        self.body = body
        self.commentTotal = commentTotal
        self.lastComments = lastComments
        self.linkedPRs = linkedPRs
    }

    /// Comments before the ones shown.
    public var earlierCommentCount: Int { max(commentTotal - lastComments.count, 0) }

    /// Whether this detail still matches the list row for `row`: both carry the issue's `updatedAt`.
    /// Linked PRs changing (CI, merge) don't bump it, so opening the issue still refreshes it.
    public func isCurrent(for row: BoardIssue) -> Bool {
        guard let updatedAt = issue.updatedAt else { return false }
        return updatedAt == row.updatedAt
    }

    /// The issue's row fields for the detail screen: whichever copy is newer by `updatedAt`. The list copy
    /// (which already has edits laid over it) wins only when it is strictly newer than the detail's, as
    /// after an edit that the detail never re-read; otherwise the detail's copy shows, with `overrides`
    /// laid over it. A nil `updatedAt` on either side keeps the detail's copy. Not `isCurrent(for:)`: that
    /// tests equality, so a detail fetched after the last list refresh would lose to the older row.
    public static func shownIssue(detail: IssueDetail?, list: BoardIssue?, overrides: EditOverrides) -> BoardIssue? {
        guard let detail else { return list }
        if let list, let listAt = list.updatedAt, let detailAt = detail.issue.updatedAt, listAt > detailAt {
            return list
        }
        return overrides.apply(to: detail.issue)
    }
}

public struct URLSessionTransport: GraphQLTransport {
    public init() {}

    public func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public func send(_ method: String, path: String, body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        let request = Self.restRequest(method, path: path, body: body, token: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    static func restRequest(_ method: String, path: String, body: Data, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com\(path)")!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}

public struct GitHubAPI: Sendable {
    private let transport: GraphQLTransport
    private let auth: any TokenSource
    private let now: @Sendable () -> Date
    private static let maxPages = 20
    /// Pages of 100 org members or repos (a generous cap, not a limit expected in practice).
    private static let maxOrgPages = 10

    public init(
        transport: GraphQLTransport = URLSessionTransport(),
        auth: any TokenSource,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.auth = auth
        self.now = now
    }

    // MARK: Public API

    public func orgContext(org: String) async throws -> OrgContext {
        let viewerData = try await execute(Queries.viewer, [:])
        guard let login = (viewerData["viewer"] as? [String: Any])?["login"] as? String else {
            throw APIError.graphQL("missing viewer.login")
        }
        let data = try await execute(Queries.orgContext, ["org": org, "logins": [login]])
        guard let organization = data["organization"] as? [String: Any] else {
            throw APIError.graphQL("organization \(org) not found")
        }
        let members = try await allPages(
            first: organization["membersWithRole"] as? [String: Any], query: Queries.orgMembers, org: org,
            field: "membersWithRole", key: "login")
        let repos = try await allPages(
            first: organization["repositories"] as? [String: Any], query: Queries.orgRepos, org: org,
            field: "repositories", key: "name")
        return OrgContext(
            org: org,
            viewer: login,
            members: members.values,
            myTeams: Set(Self.values(organization["teams"] as? [String: Any], "slug")),
            repos: repos.values,
            reposComplete: repos.complete
        )
    }

    /// The personal scope's context: the viewer and the repositories they own.
    public func personalContext() async throws -> OrgContext {
        let data = try await execute(Queries.personalContext, [:])
        guard let viewer = data["viewer"] as? [String: Any], let login = viewer["login"] as? String else {
            throw APIError.graphQL("missing viewer.login")
        }
        let repos = try await allPages(
            first: viewer["repositories"] as? [String: Any], query: Queries.personalContext, org: nil,
            field: "repositories", key: "name")
        return .personal(login: login, repos: repos.values, reposComplete: repos.complete)
    }

    /// The `key` of every node in an org connection (the viewer's when `org` is nil), following its
    /// cursor from the first page. `complete` is false when the page cap stopped the walk while more
    /// pages remained.
    private func allPages(
        first: [String: Any]?, query: String, org: String?, field: String, key: String
    ) async throws -> (values: [String], complete: Bool) {
        var result = Self.values(first, key)
        var info = first?["pageInfo"] as? [String: Any]
        for _ in 1..<Self.maxOrgPages {
            guard info?["hasNextPage"] as? Bool == true, let cursor = info?["endCursor"] as? String else { break }
            var variables: [String: Any] = ["after": cursor]
            if let org { variables["org"] = org }
            let data = try await execute(query, variables)
            // A missing page must not pass for the end of the list (lookup would miss repos).
            let owner = data[org == nil ? "viewer" : "organization"] as? [String: Any]
            guard let connection = owner?[field] as? [String: Any], connection["nodes"] is [Any]
            else { throw APIError.graphQL("incomplete \(field) list for \(org ?? "the viewer")") }
            result += Self.values(connection, key)
            info = connection["pageInfo"] as? [String: Any]
        }
        return (result, info?["hasNextPage"] as? Bool != true)
    }

    private static func values(_ connection: [String: Any]?, _ key: String) -> [String] {
        let nodes = connection?["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap { $0[key] as? String }
    }

    /// Logins of the organizations the viewer belongs to (first 100).
    public func organizations() async throws -> [String] {
        let data = try await execute(Queries.organizations, [:])
        guard let viewer = data["viewer"] as? [String: Any] else {
            throw APIError.graphQL("missing viewer")
        }
        let nodes = (viewer["organizations"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap { $0["login"] as? String }
    }

    /// The owner's Projects (v2) boards, lowest number first (first 100). Needs the `read:project`
    /// scope. A FORBIDDEN answer with no readable board throws `boardForbidden`.
    public func projects(owner: BoardOwner) async throws -> [BoardSummary] {
        let (data, errors) = try await executeReportingErrors(Queries.projects(owner), ["login": owner.login])
        let forbidden = Self.isForbidden(errors)
        guard let root = data[Queries.root(owner)] as? [String: Any] else {
            if forbidden { throw APIError.boardForbidden }
            throw APIError.graphQL("\(Queries.root(owner)) \(owner.login) not found")
        }
        let nodes = (root["projectsV2"] as? [String: Any])?["nodes"] as? [Any] ?? []
        let boards = nodes.compactMap { raw -> BoardSummary? in
            guard let node = raw as? [String: Any], let number = node["number"] as? Int,
                  let title = node["title"] as? String
            else { return nil }
            return BoardSummary(board: BoardRef(owner: owner, number: number), title: title)
        }
        if boards.isEmpty, forbidden { throw APIError.boardForbidden }
        return boards
    }

    public func searchPRs(_ query: String) async throws -> [PullRequest] {
        try await searchPRs(query, maxPages: Self.maxPages).prs
    }

    /// Up to `maxPages` pages of `pageSize` (GitHub allows 100); `hasMore` when GitHub has further results.
    public func searchPRs(
        _ query: String, maxPages: Int, pageSize: Int = 50
    ) async throws -> (prs: [PullRequest], hasMore: Bool) {
        var result: [PullRequest] = []
        var after: String?
        for _ in 0..<maxPages {
            var variables: [String: Any] = ["q": query, "first": pageSize]
            if let after { variables["after"] = after }
            let data = try await execute(Queries.search, variables)
            guard let search = data["search"] as? [String: Any] else {
                throw APIError.graphQL("missing data.search")
            }
            let nodes = search["nodes"] as? [Any] ?? []
            for raw in nodes {
                guard let node = raw as? [String: Any], !node.isEmpty,
                      let pr = try? Decoding.pullRequest(from: node)
                else { continue }
                result.append(pr)
            }
            let info = search["pageInfo"] as? [String: Any]
            guard info?["hasNextPage"] as? Bool == true, let cursor = info?["endCursor"] as? String else {
                return (result, false)
            }
            after = cursor
        }
        return (result, true)
    }

    /// Issue search, up to `maxPages` pages of `pageSize`; `hasMore` when GitHub has further results. Nodes
    /// that are not decodable issues are skipped. With a `viewer`, each issue carries the viewer's
    /// latest assignment. `activity` adds what issue notifications read (`Queries.issueSearch`).
    public func searchIssues(
        _ query: String, maxPages: Int = 20, pageSize: Int = 50, assignmentFor viewer: String? = nil,
        activity: Bool = false
    ) async throws -> (issues: [BoardIssue], hasMore: Bool) {
        let graphQL = Queries.issueSearch(withAssignment: viewer != nil, withActivity: activity)
        var result: [BoardIssue] = []
        var after: String?
        for _ in 0..<maxPages {
            var variables: [String: Any] = ["q": query, "first": pageSize]
            if let after { variables["after"] = after }
            let data = try await execute(graphQL, variables)
            guard let search = data["search"] as? [String: Any] else {
                throw APIError.graphQL("missing data.search")
            }
            for raw in search["nodes"] as? [Any] ?? [] {
                guard let node = raw as? [String: Any],
                      let issue = Decoding.issue(from: node, assignmentFor: viewer)
                else { continue }
                result.append(issue)
            }
            let info = search["pageInfo"] as? [String: Any]
            guard info?["hasNextPage"] as? Bool == true, let cursor = info?["endCursor"] as? String else {
                return (result, false)
            }
            after = cursor
        }
        return (result, true)
    }

    /// One page (50) of the Ask index search `query`, from `after`; `total` is GitHub's result count.
    /// Nodes that are not decodable PRs or issues are skipped.
    public func askPage(query: String, after: String?) async throws -> AskPage {
        var variables: [String: Any] = ["q": query, "first": 50]
        if let after { variables["after"] = after }
        let data = try await execute(Queries.askSearch, variables)
        guard let search = data["search"] as? [String: Any] else {
            throw APIError.graphQL("missing data.search")
        }
        let items = (search["nodes"] as? [Any] ?? []).compactMap { raw in
            (raw as? [String: Any]).flatMap(Decoding.askItem(from:))
        }
        let info = search["pageInfo"] as? [String: Any]
        let next = info?["hasNextPage"] as? Bool == true ? info?["endCursor"] as? String : nil
        return AskPage(items: items, total: search["issueCount"] as? Int ?? items.count, next: next)
    }

    public func lookup(
        number: Int, org: String, repos: [String]
    ) async throws -> (prs: [PullRequest], issues: [BoardIssue]) {
        let names = repos.filter(Self.isValidRepoName)
        guard !names.isEmpty else { return ([], []) }
        let data = try await execute(Queries.lookup(repoNames: names), ["org": org, "n": number])
        var prs: [PullRequest] = []
        var issues: [BoardIssue] = []
        for index in names.indices {
            guard let repo = data["r\(index)"] as? [String: Any],
                  let node = repo["issueOrPullRequest"] as? [String: Any]
            else { continue }
            switch node["__typename"] as? String {
            case "PullRequest":
                if let pr = try? Decoding.pullRequest(from: node) { prs.append(pr) }
            case "Issue":
                if let issue = Decoding.issue(from: node) { issues.append(issue) }
            default:
                break
            }
        }
        return (prs, issues)
    }

    /// The pull requests `keys` name, as a search row lists them, in one query. A key whose owner or
    /// name isn't a valid repository name is skipped (no query when none is left); one GitHub returns
    /// null for (deleted, or no longer readable) is left out.
    public func pullRequests(_ keys: [PRKey]) async throws -> [PullRequest] {
        let targets = keys.compactMap { key -> (owner: String, name: String, number: Int)? in
            let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts.allSatisfy(Self.isValidRepoName) else { return nil }
            return (parts[0], parts[1], key.number)
        }
        guard !targets.isEmpty else { return [] }
        var variables: [String: Any] = [:]
        for (index, target) in targets.enumerated() {
            variables["o\(index)"] = target.owner
            variables["r\(index)"] = target.name
            variables["n\(index)"] = target.number
        }
        let data = try await execute(Queries.pullRequests(count: targets.count), variables)
        return targets.indices.compactMap { index in
            guard let repo = data["p\(index)"] as? [String: Any],
                  let node = repo["pullRequest"] as? [String: Any]
            else { return nil }
            return try? Decoding.pullRequest(from: node)
        }
    }

    public func boardIssues(_ board: BoardRef) async throws -> [BoardIssue] {
        try await self.board(board).issues
    }

    /// The board's title, its Status options (empty when it has no single-select Status field), its
    /// issue items with their Status (draft items and pull requests are left out), and the node IDs
    /// board mutations take. A board with more than `maxPages` pages of items throws rather than
    /// passing a partial list for the whole. A board GitHub won't let this token read throws
    /// `boardForbidden`, one that isn't there "not found".
    public func board(
        _ board: BoardRef
    ) async throws -> (title: String?, statusOptions: [StatusOption], issues: [BoardIssue], ids: BoardIds?) {
        let projectNumber = board.number
        var result: [BoardIssue] = []
        var title: String?
        var options: [StatusOption]?
        var ids: BoardIds?
        var after: String?
        for _ in 0..<Self.maxPages {
            var variables: [String: Any] = ["login": board.owner.login, "n": projectNumber]
            if let after { variables["after"] = after }
            let (data, errors) = try await executeReportingErrors(Queries.board(board.owner), variables)
            let project = (data[Queries.root(board.owner)] as? [String: Any])?["projectV2"] as? [String: Any]
            guard let items = project?["items"] as? [String: Any] else {
                // Partial data hides the reason: a null owner or project with FORBIDDEN is not "not found".
                if project == nil, Self.isForbidden(errors) { throw APIError.boardForbidden }
                throw APIError.graphQL("project \(projectNumber) not found")
            }
            title = title ?? project?["title"] as? String
            if ids == nil, let projectId = project?["id"] as? String {
                ids = BoardIds(projectId: projectId, statusFieldId: (project?["field"] as? [String: Any])?["id"] as? String)
            }
            if options == nil {
                let nodes = (project?["field"] as? [String: Any])?["options"] as? [[String: Any]] ?? []
                options = nodes.compactMap { node in
                    guard let id = node["id"] as? String, let name = node["name"] as? String else { return nil }
                    return StatusOption(
                        id: id, name: name, color: (node["color"] as? String).flatMap(StatusOptionColor.init(rawValue:)))
                }
            }
            for node in items["nodes"] as? [[String: Any]] ?? [] {
                guard let content = node["content"] as? [String: Any],
                      content["__typename"] as? String == "Issue",
                      let issue = Decoding.issue(
                        from: content, status: Decoding.statusValue(node["fieldValueByName"]),
                        boardItemId: node["databaseId"] as? Int, boardItemNodeId: node["id"] as? String)
                else { continue }
                result.append(issue)
            }
            let info = items["pageInfo"] as? [String: Any]
            guard info?["hasNextPage"] as? Bool == true, let cursor = info?["endCursor"] as? String else {
                return (title, options ?? [], result, ids)
            }
            after = cursor
        }
        throw APIError.graphQL("incomplete board \(projectNumber)")
    }

    public func detail(_ key: PRKey) async throws -> PRDetail {
        let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError.graphQL("bad repo \(key.repo)") }
        let (data, errors) = try await executeReportingErrors(
            Queries.detail, ["owner": parts[0], "name": parts[1], "n": key.number])
        guard let pr = (data["repository"] as? [String: Any])?["pullRequest"] as? [String: Any] else {
            throw Self.missing(data, errors, "pull request \(key.repo)#\(key.number) not found")
        }

        let commit = ((pr["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["commit"]
            as? [String: Any]
        let contexts = (((commit?["statusCheckRollup"] as? [String: Any])?["contexts"]) as? [String: Any])?["nodes"]
            as? [[String: Any]] ?? []
        let checks = contexts.compactMap(Self.check)
        // Nodes the decoder drops (unknown kinds) are not missing from the list, so they leave the total.
        let checkCount = ((((commit?["statusCheckRollup"] as? [String: Any])?["contexts"]) as? [String: Any])?["totalCount"]
            as? Int).map { $0 - (contexts.count - checks.count) }
        let reviewNodes = (pr["latestReviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let reviews = reviewNodes.compactMap { try? Decoding.review($0) }
        let requestNodes = (pr["reviewRequests"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []

        let commentsConnection = pr["comments"] as? [String: Any]
        let commentNodes = commentsConnection?["nodes"] as? [[String: Any]] ?? []
        let comments = commentNodes.compactMap(Self.comment).sorted { $0.createdAt < $1.createdAt }

        let filesConnection = pr["files"] as? [String: Any]
        let fileNodes = filesConnection?["nodes"] as? [[String: Any]] ?? []
        let files = fileNodes.compactMap { node -> ChangedFile? in
            guard let path = node["path"] as? String else { return nil }
            return ChangedFile(
                path: path, additions: node["additions"] as? Int ?? 0, deletions: node["deletions"] as? Int ?? 0)
        }

        return PRDetail(
            key: key, body: pr["body"] as? String ?? "", checks: checks,
            reviews: reviews, comments: comments, files: files,
            updatedAt: (pr["updatedAt"] as? String).flatMap { try? Decoding.date($0) },
            ci: Decoding.ciState(rollup: commit?["statusCheckRollup"]),
            changedFiles: (pr["changedFiles"] as? Int ?? filesConnection?["totalCount"] as? Int)
                .map { $0 - (fileNodes.count - files.count) },
            additions: pr["additions"] as? Int,
            deletions: pr["deletions"] as? Int,
            checkCount: checkCount,
            requests: requestNodes.compactMap(Decoding.reviewer),
            commentCount: (commentsConnection?["totalCount"] as? Int).map { $0 - (commentNodes.count - comments.count) },
            headOid: pr["headRefOid"] as? String,
            author: (pr["author"] as? [String: Any])?["login"] as? String ?? "ghost",
            state: (pr["state"] as? String).flatMap { PRState(rawValue: $0.lowercased()) },
            merge: MergeInfo.read(pullRequest: pr, repository: data["repository"] as? [String: Any]))
    }

    /// The pull request's head commit and state right now, for a review that must name the commit it saw.
    public func prHead(_ key: PRKey) async throws -> PRHead {
        let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError.graphQL("bad repo \(key.repo)") }
        let (data, errors) = try await executeReportingErrors(
            Queries.prHead, ["owner": parts[0], "name": parts[1], "n": key.number])
        guard let pr = (data["repository"] as? [String: Any])?["pullRequest"] as? [String: Any] else {
            throw Self.missing(data, errors, "pull request \(key.repo)#\(key.number) not found")
        }
        guard let oid = pr["headRefOid"] as? String,
              let state = (pr["state"] as? String).flatMap({ PRState(rawValue: $0.lowercased()) })
        else { throw APIError.graphQL("malformed pull request head") }
        return PRHead(oid: oid, state: state)
    }

    /// Submits a review on `commit`, with `body` trimmed and left out when empty. A refusal throws
    /// `writeRefused` with GitHub's reason; a timeout or dropped connection throws `CommentTransportError`,
    /// since the review may have landed.
    public func submitReview(on key: PRKey, verdict: ReviewVerdict, body: String, commit: String) async throws {
        let path = "/repos/\(key.repo)/pulls/\(key.number)/reviews"
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = ["event": verdict.rawValue, "commit_id": commit]
        if !trimmed.isEmpty { payload["body"] = trimmed }
        _ = try await restAnswer("POST", path, payload, keepingTransportFailures: true)
    }

    /// Issue `key` with who last closed it; nil when it is gone (deleted, transferred, no access) or
    /// doesn't decode.
    public func closedIssue(_ key: PRKey) async throws -> BoardIssue? {
        let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let (data, _) = try await executeReportingErrors(
            Queries.closedIssue, ["owner": parts[0], "name": parts[1], "n": key.number])
        guard let node = (data["repository"] as? [String: Any])?["issue"] as? [String: Any] else { return nil }
        return Decoding.issue(from: node)
    }

    public func issueDetail(_ key: PRKey) async throws -> IssueDetail {
        let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError.graphQL("bad repo \(key.repo)") }
        let (data, errors) = try await executeReportingErrors(
            Queries.issueDetail, ["owner": parts[0], "name": parts[1], "n": key.number])
        let message = "issue \(key.repo)#\(key.number) not found"
        guard let node = (data["repository"] as? [String: Any])?["issue"] as? [String: Any] else {
            throw Self.missing(data, errors, message)
        }
        // A node that is there but doesn't decode isn't a missing issue.
        guard let issue = Decoding.issue(from: node) else { throw APIError.graphQL(message) }

        let commentsConnection = node["lastComments"] as? [String: Any]
        let commentNodes = commentsConnection?["nodes"] as? [[String: Any]] ?? []
        let comments = commentNodes.compactMap(Self.comment).sorted { $0.createdAt < $1.createdAt }
        let prNodes = (node["closedByPullRequestsReferences"] as? [String: Any])?["nodes"] as? [Any] ?? []

        return IssueDetail(
            key: key, issue: issue, body: node["body"] as? String ?? "",
            commentTotal: max(commentsConnection?["totalCount"] as? Int ?? issue.commentCount, comments.count),
            lastComments: Array(comments.suffix(2)),
            linkedPRs: prNodes.compactMap { ($0 as? [String: Any]).flatMap(Self.linkedPR) })
    }

    // MARK: Decoding helpers

    private static func comment(_ node: [String: Any]) -> Comment? {
        guard let body = node["body"] as? String,
              let raw = node["createdAt"] as? String,
              let created = try? Decoding.date(raw)
        else { return nil }
        let authorNode = node["author"] as? [String: Any]
        let author = authorNode?["login"] as? String ?? "ghost"
        let isBot = (authorNode?["__typename"] as? String).map { $0 == "Bot" }
        return Comment(id: node["id"] as? String, author: author, authorIsBot: isBot, body: body, createdAt: created)
    }

    private static func linkedPR(_ node: [String: Any]) -> LinkedPR? {
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = (node["url"] as? String).flatMap(URL.init(string:)),
              let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String,
              let state = (node["state"] as? String).flatMap({ PRState(rawValue: $0.lowercased()) })
        else { return nil }
        let commit = ((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["commit"]
            as? [String: Any]
        return LinkedPR(
            key: PRKey(repo: repo, number: number), title: title, url: url, state: state,
            author: (node["author"] as? [String: Any])?["login"] as? String ?? "ghost",
            ci: Decoding.ciState(rollup: commit?["statusCheckRollup"]),
            isDraft: node["isDraft"] as? Bool ?? false)
    }

    static func isValidRepoName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    private static func check(_ node: [String: Any]) -> Check? {
        switch node["__typename"] as? String {
        case "CheckRun":
            guard let name = node["name"] as? String else { return nil }
            let state: CIState
            if node["status"] as? String != "COMPLETED" {
                state = .pending
            } else {
                switch node["conclusion"] as? String {
                case "SUCCESS": state = .success
                case "NEUTRAL", "SKIPPED": state = .skipped
                case "CANCELLED": state = .cancelled
                case "FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE": state = .failure
                default: state = .none
                }
            }
            return Check(name: name, state: state, url: (node["detailsUrl"] as? String).flatMap(URL.init(string:)))
        case "StatusContext":
            guard let name = node["context"] as? String else { return nil }
            return Check(
                name: name, state: Decoding.ciState(node["state"] as? String),
                url: (node["targetUrl"] as? String).flatMap(URL.init(string:)))
        default:
            return nil
        }
    }

    // MARK: Writes

    /// Sets the board item's Status to `option`, or clears it when `option` is nil.
    public func setStatus(project: String, item: String, field: String, option: String?) async throws {
        var variables = ["project": project, "item": item, "field": field]
        if let option {
            variables["option"] = option
            _ = try await mutate(Mutations.setStatus, variables, payload: "updateProjectV2ItemFieldValue")
        } else {
            _ = try await mutate(Mutations.clearStatus, variables, payload: "clearProjectV2ItemFieldValue")
        }
    }

    /// Adds the issue (`content`, its node ID) to the board; returns the new item's node ID. GitHub
    /// returns the existing item when the issue is already on the board.
    public func addToProject(project: String, content: String) async throws -> String {
        let payload = try await mutate(
            Mutations.addToProject, ["project": project, "content": content], payload: "addProjectV2ItemById")
        guard let id = (payload["item"] as? [String: Any])?["id"] as? String else {
            throw APIError.graphQL("missing addProjectV2ItemById.item.id")
        }
        return id
    }

    public func deleteProjectItem(project: String, item: String) async throws {
        _ = try await mutate(Mutations.deleteProjectItem, ["project": project, "item": item], payload: "deleteProjectV2Item")
    }

    /// Adds and removes labels (node IDs) on the issue or PR `subject`, in one request.
    public func changeLabels(of subject: String, adding: [String], removing: [String]) async throws -> SetChangeResult {
        try await changeSet(
            Mutations.labels(adding: !adding.isEmpty, removing: !removing.isEmpty), subject, adding, removing)
    }

    /// Posts `body`, trimmed, as a comment on the issue or PR `key` and returns the comment GitHub made.
    /// A refusal throws `writeRefused` with GitHub's reason. A timeout or dropped connection throws
    /// `CommentTransportError`, since the comment may have landed. An answer that lacks a field throws
    /// `server(201)`: the post was accepted, so it is never a refusal.
    public func postComment(on key: PRKey, body: String) async throws -> Comment {
        let path = "/repos/\(key.repo)/issues/\(key.number)/comments"
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = try await restAnswer("POST", path, ["body": trimmed], keepingTransportFailures: true)
        guard let node = try? JSONSerialization.jsonObject(with: answer) as? [String: Any],
              let id = node["node_id"] as? String,
              let text = node["body"] as? String,
              let raw = node["created_at"] as? String,
              let created = try? Decoding.date(raw),
              let author = (node["user"] as? [String: Any])?["login"] as? String
        else { throw APIError.server(201) }
        return Comment(id: id, author: author, body: text, createdAt: created)
    }

    /// Adds and removes assignees (user node IDs) on the issue or PR `subject`, in one request.
    public func changeAssignees(of subject: String, adding: [String], removing: [String]) async throws -> SetChangeResult {
        try await changeSet(
            Mutations.assignees(adding: !adding.isEmpty, removing: !removing.isEmpty), subject, adding, removing)
    }

    /// Requests reviews from `adding` and removes the requests of `removing` on PR `key`, over REST, which
    /// takes logins and team slugs and changes only what it names. The add goes first. Once one half has
    /// applied, the other's failure is a partial result; a failure with nothing applied throws.
    public func changeReviewers(of key: PRKey, adding: [Reviewer], removing: [Reviewer]) async throws -> SetChangeResult {
        let path = "/repos/\(key.repo)/pulls/\(key.number)/requested_reviewers"
        var addError: APIError?
        if !adding.isEmpty {
            do {
                try await rest("POST", path, Self.reviewersBody(adding, alwaysPeople: false))
            } catch let error as APIError {
                guard case .writeRefused = error, !removing.isEmpty else { throw error }
                addError = error
            }
        }
        guard !removing.isEmpty else { return SetChangeResult(addApplied: true, removeApplied: true, refusal: nil) }
        do {
            // GitHub requires `reviewers` on a removal, even when only teams go.
            try await rest("DELETE", path, Self.reviewersBody(removing, alwaysPeople: true))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let addError { throw addError }
            guard !adding.isEmpty else { throw error }
            return SetChangeResult(addApplied: true, removeApplied: false, refusal: Self.reason(error))
        }
        if let addError {
            return SetChangeResult(addApplied: false, removeApplied: true, refusal: Self.reason(addError))
        }
        return SetChangeResult(addApplied: true, removeApplied: true, refusal: nil)
    }

    /// `reviewers` (logins) and `team_reviewers` (slugs), each only when it has any, unless `alwaysPeople`.
    private static func reviewersBody(_ reviewers: [Reviewer], alwaysPeople: Bool) -> [String: Any] {
        var body: [String: Any] = [:]
        let people = reviewers.compactMap { reviewer -> String? in
            if case .user(let login) = reviewer { return login }
            return nil
        }
        let teams = reviewers.compactMap { reviewer -> String? in
            if case .team(let slug, _) = reviewer { return slug }
            return nil
        }
        if alwaysPeople || !people.isEmpty { body["reviewers"] = people }
        if !teams.isEmpty { body["team_reviewers"] = teams }
        return body
    }

    /// The words of a refused write; the refresh wording for anything else.
    private static func reason(_ error: any Error) -> String {
        if case APIError.writeRefused(let message) = error { return message }
        return RefreshError(error).message
    }

    /// The issue's (`content`, its node ID) item on the board `project`, archived or not; nil when it
    /// isn't on that board.
    public func projectItem(of content: String, in project: String) async throws -> String? {
        let data = try await execute(Mutations.projectItems, ["content": content])
        let items = ((data["node"] as? [String: Any])?["projectItems"] as? [String: Any])?["nodes"] as? [[String: Any]]
        let item = items?.first { ($0["project"] as? [String: Any])?["id"] as? String == project }
        return item?["id"] as? String
    }

    /// The node ID of the issue or PR `key`, for items cached before node IDs were stored.
    public func nodeId(of key: PRKey) async throws -> String {
        let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError.notFound("\(key.repo)#\(key.number) not found") }
        let data = try await execute(Mutations.nodeId, ["owner": parts[0], "name": parts[1], "n": key.number])
        let node = (data["repository"] as? [String: Any])?["issueOrPullRequest"] as? [String: Any]
        guard let id = node?["id"] as? String else { throw APIError.notFound("\(key.repo)#\(key.number) not found") }
        return id
    }

    /// The most pages of labels read for one repo.
    public static let maxLabelPages = 10

    /// The repo's labels by name, and the issue's or PR's own. `complete` is false when the repo has more
    /// than `maxLabelPages` pages. Its labels past the first 100 are not read.
    public func labelCandidates(for key: PRKey) async throws -> SetCandidates {
        let (owner, name) = try Self.ownerAndName(key)
        var all: [SetCandidate] = []
        var current: [SetCandidate] = []
        var after: String?
        for page in 0..<Self.maxLabelPages {
            var variables: [String: Any] = ["owner": owner, "name": name, "n": key.number, "withIssue": page == 0]
            if let after { variables["after"] = after }
            let data = try await execute(Mutations.labelCandidates, variables)
            guard let repository = data["repository"] as? [String: Any] else {
                throw APIError.notFound("\(key.repo) not found")
            }
            if page == 0 {
                current = Self.candidates(in: repository["item"], field: "labels", label: true)
            }
            let labels = repository["labels"] as? [String: Any]
            all += Self.candidates(in: labels, label: true)
            let info = labels?["pageInfo"] as? [String: Any]
            guard info?["hasNextPage"] as? Bool == true, let cursor = info?["endCursor"] as? String else {
                return SetCandidates(all: all, current: current, complete: true)
            }
            after = cursor
        }
        return SetCandidates(all: all, current: current, complete: false)
    }

    /// The first hundred people assignable in the repo (those matching `query`, when it isn't empty),
    /// and the issue's or PR's assignees. `complete` is false when there were more.
    public func assigneeCandidates(for key: PRKey, query: String?) async throws -> SetCandidates {
        let (owner, name) = try Self.ownerAndName(key)
        var variables: [String: Any] = ["owner": owner, "name": name, "n": key.number]
        if let query, !query.isEmpty { variables["q"] = query }
        let data = try await execute(Mutations.assigneeCandidates, variables)
        guard let repository = data["repository"] as? [String: Any] else {
            throw APIError.notFound("\(key.repo) not found")
        }
        let users = repository["assignableUsers"] as? [String: Any]
        let more = (users?["pageInfo"] as? [String: Any])?["hasNextPage"] as? Bool == true
        return SetCandidates(
            all: Self.candidates(in: users, label: false),
            current: Self.candidates(in: repository["item"], field: "assignees", label: false),
            complete: !more)
    }

    /// The first hundred people who can be mentioned in `repo` ("owner/name"; those matching `query`, when
    /// it isn't empty). `complete` is false when there were more. `current` is empty.
    public func mentionableCandidates(repo: String, query: String?) async throws -> SetCandidates {
        let parts = repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError.notFound("\(repo) not found") }
        var variables: [String: Any] = ["owner": parts[0], "name": parts[1]]
        if let query, !query.isEmpty { variables["q"] = query }
        let data = try await execute(Mutations.mentionableCandidates, variables)
        guard let repository = data["repository"] as? [String: Any] else {
            throw APIError.notFound("\(repo) not found")
        }
        let users = repository["mentionableUsers"] as? [String: Any]
        let more = (users?["pageInfo"] as? [String: Any])?["hasNextPage"] as? Bool == true
        return SetCandidates(all: Self.candidates(in: users, label: false), current: [], complete: !more)
    }

    /// The organisation's teams (those matching `query`, when it isn't empty); nil when GitHub won't list
    /// them (a user's account, no `read:org`, no Members permission). Throws when GitHub couldn't be
    /// asked (offline, a 5xx, a rate limit), so a caller can try again. A list cut at `maxLabelPages`
    /// pages is returned as read.
    public func teams(owner: String, query: String?) async throws -> [SetCandidate]? {
        try await teamCandidates(owner: owner, query: query, throwsUnanswered: true)?.list
    }

    /// What the reviewers picker offers on pull request `key`: people (filtered by `query` past the first
    /// 100), the PR's past reviewers with their verdicts, its suggested reviewers, its requests, and the
    /// teams of an organisation owner. A team list that can't be read (no `read:org`, no Members
    /// permission) leaves teams out and throws nothing.
    public func reviewerCandidates(for key: PRKey, query: String?) async throws -> ReviewerCandidates {
        let (owner, name) = try Self.ownerAndName(key)
        var variables: [String: Any] = ["owner": owner, "name": name, "n": key.number]
        if let query, !query.isEmpty { variables["q"] = query }
        let data = try await execute(Mutations.reviewerCandidates, variables)
        guard let repository = data["repository"] as? [String: Any] else {
            throw APIError.notFound("\(key.repo) not found")
        }
        let users = repository["assignableUsers"] as? [String: Any]
        let people = Self.candidates(in: users, label: false)
        let morePeople = (users?["pageInfo"] as? [String: Any])?["hasNextPage"] as? Bool == true
        let isOrganization = (repository["owner"] as? [String: Any])?["__typename"] as? String == "Organization"
        let teams = isOrganization ? try await teamCandidates(owner: owner, query: query) : nil

        let pr = repository["item"] as? [String: Any] ?? [:]
        let author = ((pr["author"] as? [String: Any])?["login"] as? String)?.lowercased()
        var verdicts: [String: ReviewState] = [:]
        var reviewed: [SetCandidate] = []
        for node in Self.nodes(pr["latestReviews"]) {
            guard let person = node["author"] as? [String: Any], person["__typename"] as? String == "User",
                  let review = try? Decoding.review(node), let candidate = Self.person(person) else { continue }
            verdicts[candidate.key] = review.state
            reviewed.append(candidate)
        }
        func with(_ c: SetCandidate, suggested: Bool = false) -> SetCandidate {
            SetCandidate(id: c.id, name: c.name, avatarURL: c.avatarURL, team: c.team,
                         verdict: verdicts[c.key], isSuggested: suggested)
        }

        var seen: Set<String> = author.map { [$0] } ?? []
        var current: [SetCandidate] = []
        for node in Self.nodes(pr["reviewRequests"]) {
            guard let requested = node["requestedReviewer"] as? [String: Any] else { continue }
            let candidate: SetCandidate? = switch requested["__typename"] as? String {
            case "User": Self.person(requested)
            case "Team": (requested["slug"] as? String).map { Self.team(slug: $0, name: requested["name"] as? String) }
            default: nil
            }
            if let candidate, seen.insert(candidate.key).inserted { current.append(with(candidate)) }
        }
        let suggested = (pr["suggestedReviewers"] as? [[String: Any]] ?? [])
            .compactMap { ($0["reviewer"] as? [String: Any]).flatMap(Self.person) }
        var all: [SetCandidate] = []
        for candidate in reviewed where seen.insert(candidate.key).inserted { all.append(with(candidate)) }
        for candidate in suggested where seen.insert(candidate.key).inserted { all.append(with(candidate, suggested: true)) }
        for candidate in people + (teams?.list ?? []) where seen.insert(candidate.key).inserted {
            all.append(with(candidate))
        }
        return ReviewerCandidates(
            people: people, teams: teams?.list,
            picker: SetCandidates(all: all, current: current, complete: !morePeople && teams?.complete != false))
    }

    /// The organisation's teams, paged as labels are; nil when GitHub won't list them. `throwsUnanswered`:
    /// a failure to ask GitHub at all is thrown rather than read as nil.
    private func teamCandidates(
        owner: String, query: String?, throwsUnanswered: Bool = false
    ) async throws -> (list: [SetCandidate], complete: Bool)? {
        var list: [SetCandidate] = []
        var after: String?
        for _ in 0..<Self.maxLabelPages {
            var variables: [String: Any] = ["owner": owner]
            if let query, !query.isEmpty { variables["q"] = query }
            if let after { variables["after"] = after }
            let teams: [String: Any]
            do {
                guard let found = (try await execute(Mutations.teamCandidates, variables)["organization"]
                    as? [String: Any])?["teams"] as? [String: Any] else { return nil }
                teams = found
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if throwsUnanswered, !Self.isRefusal(error) { throw error }
                return nil
            }
            list += Self.nodes(teams).compactMap { node in
                (node["slug"] as? String).map { Self.team(slug: $0, name: node["name"] as? String) }
            }
            let info = teams["pageInfo"] as? [String: Any]
            guard info?["hasNextPage"] as? Bool == true, let cursor = info?["endCursor"] as? String else {
                return (list, true)
            }
            after = cursor
        }
        return (list, false)
    }

    /// GitHub answered, and the answer was no: a missing scope or a 403. A user's login or a token that
    /// can't read the org's teams answers with data and no teams, and comes back as nil before this. Anything
    /// else (offline, a 5xx, a rate limit, a body that isn't GitHub's, an error with no data) means it
    /// wasn't asked.
    private static func isRefusal(_ error: Error) -> Bool {
        switch error as? APIError {
        case .insufficientScopes, .forbidden: true
        default: false
        }
    }

    private static func nodes(_ connection: Any?) -> [[String: Any]] {
        (connection as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    }

    /// A person from a `User` node; the node ID when the node has one, else the login's key.
    private static func person(_ node: [String: Any]) -> SetCandidate? {
        guard let login = node["login"] as? String else { return nil }
        return SetCandidate(
            id: node["id"] as? String ?? login.lowercased(), name: login,
            avatarURL: (node["avatarUrl"] as? String).flatMap(URL.init(string:)))
    }

    /// A team, its id its key; the slug stands in for a missing name.
    private static func team(slug: String, name: String?) -> SetCandidate {
        SetCandidate(id: "team:" + slug.lowercased(), name: name ?? slug, team: slug)
    }

    private static func ownerAndName(_ key: PRKey) throws -> (String, String) {
        let parts = key.repo.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw APIError.notFound("\(key.repo) not found") }
        return (parts[0], parts[1])
    }

    /// The candidates in `connection["nodes"]`, or in `parent[field]["nodes"]` when `field` is given;
    /// empty when the parent is null.
    private static func candidates(in parent: Any?, field: String? = nil, label: Bool) -> [SetCandidate] {
        var connection = parent as? [String: Any]
        if let field { connection = connection?[field] as? [String: Any] }
        let nodes = connection?["nodes"] as? [[String: Any]] ?? []
        return nodes.compactMap { node in
            guard let id = node["id"] as? String else { return nil }
            if label {
                guard let name = node["name"] as? String else { return nil }
                return SetCandidate(
                    id: id, name: name, detail: node["description"] as? String, color: node["color"] as? String)
            }
            guard let login = node["login"] as? String else { return nil }
            return SetCandidate(
                id: id, name: login, avatarURL: (node["avatarUrl"] as? String).flatMap(URL.init(string:)))
        }
    }

    /// Sends a mutation and returns its `payload` field. A null payload throws `writeRefused` for a
    /// FORBIDDEN error, else `graphQL`.
    private func mutate(_ mutation: String, _ variables: [String: Any], payload: String) async throws -> [String: Any] {
        let (data, errors) = try await executeReportingErrors(mutation, variables)
        if let result = data[payload] as? [String: Any] { return result }
        throw Self.refusal(errors)
    }

    private func changeSet(
        _ mutation: String?, _ subject: String, _ adding: [String], _ removing: [String]
    ) async throws -> SetChangeResult {
        guard let mutation else { return SetChangeResult(addApplied: true, removeApplied: true, refusal: nil) }
        var variables: [String: Any] = ["subject": subject]
        if !adding.isEmpty { variables["add"] = adding }
        if !removing.isEmpty { variables["remove"] = removing }
        let (data, errors) = try await executeReportingErrors(mutation, variables)
        let addSent = !adding.isEmpty, removeSent = !removing.isEmpty
        let addApplied = !addSent || data["add"] is [String: Any]
        let removeApplied = !removeSent || data["remove"] is [String: Any]
        let sentApplied = (addSent && addApplied) || (removeSent && removeApplied)
        if !sentApplied { throw Self.refusal(errors) }
        let refusal = addApplied && removeApplied ? nil : errors.first?["message"] as? String
        return SetChangeResult(addApplied: addApplied, removeApplied: removeApplied, refusal: refusal)
    }

    private static func refusal(_ errors: [[String: Any]]) -> APIError {
        let message = errors.first?["message"] as? String ?? "GitHub didn't apply the change"
        return isForbidden(errors) ? .writeRefused(message) : .graphQL(message)
    }

    // MARK: Transport

    /// Sends one query and returns `data`. Partial results (errors alongside data) are returned as data.
    /// A 401 is reported to the token source; the query is sent again, once, when it has a new token.
    func execute(_ query: String, _ variables: [String: Any]) async throws -> [String: Any] {
        try await executeReportingErrors(query, variables).data
    }

    /// Why a detail's PR or issue node is null: `.notFound` when GitHub says so (a `NOT_FOUND` error,
    /// or the repository there without the item), else `.graphQL(message)`, as for a repository hidden
    /// behind `FORBIDDEN` (single sign-on, permissions).
    private static func missing(_ data: [String: Any], _ errors: [[String: Any]], _ message: String) -> APIError {
        if isForbidden(errors) { return .graphQL(message) }
        let notFound = data["repository"] is [String: Any]
            || errors.contains { $0["type"] as? String == "NOT_FOUND" }
        return notFound ? .notFound(message) : .graphQL(message)
    }

    private static func isForbidden(_ errors: [[String: Any]]) -> Bool {
        errors.contains { $0["type"] as? String == "FORBIDDEN" }
    }

    /// The error a non-2xx status means; nil for 2xx. `refusing`: a REST write, where a 403 that isn't a
    /// rate limit, a 404, a 410 or a 422 is the write refused, for the reason in the body: the first of
    /// `errors` (a validation failure's detail) when it has one, else `message`.
    private func httpError(_ data: Data, _ response: HTTPURLResponse, refusing: Bool = false) -> APIError? {
        if let sso = APIError.ssoRequired(in: response) { return sso }
        let status = response.statusCode
        if (200..<300).contains(status) { return nil }
        if status == 401 { return .unauthorized }
        if let limited = APIError.rateLimited(in: response, body: data, now: now()) { return limited }
        if refusing, [403, 404, 410, 422].contains(status) {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let first = (body?["errors"] as? [Any])?.first
            let detail = (first as? [String: Any])?["message"] as? String ?? first as? String
            let reason = [detail, body?["message"] as? String].compactMap { $0 }.first { !$0.isEmpty }
            return .writeRefused(reason ?? "GitHub didn't apply the change")
        }
        return status == 403 ? .forbidden : .server(status)
    }

    /// Sends one REST write with a JSON body; throws unless the answer is 2xx.
    private func rest(_ method: String, _ path: String, _ body: [String: Any]) async throws {
        _ = try await restAnswer(method, path, body)
    }

    /// Sends one REST write with a JSON body and returns the answer's body; throws unless it is 2xx.
    /// `keepingTransportFailures`: a `URLError` (except a cancellation) reaches the caller as a
    /// `CommentTransportError` with its code, not as the `APIError` that `sendAuthorized` makes of it.
    private func restAnswer(
        _ method: String, _ path: String, _ body: [String: Any], keepingTransportFailures: Bool = false
    ) async throws -> Data {
        try Task.checkCancellation()
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let (answer, response) = try await sendAuthorized(with: auth) { token in
            do {
                return try await transport.send(method, path: path, body: data, token: token)
            } catch let error as URLError where keepingTransportFailures && error.code != .cancelled {
                throw CommentTransportError(code: error.code)
            }
        }
        if let error = httpError(answer, response, refusing: true) { throw error }
        return answer
    }

    /// `execute`, also returning the errors that came alongside partial data, for callers that tell a
    /// null field GitHub wouldn't show from one that isn't there.
    private func executeReportingErrors(
        _ query: String, _ variables: [String: Any]
    ) async throws -> (data: [String: Any], errors: [[String: Any]]) {
        // A cancelled fetch (a sibling hit a rate limit) sends no further pages.
        try Task.checkCancellation()
        let body = try JSONSerialization.data(
            withJSONObject: ["query": query, "variables": variables], options: [.sortedKeys])
        let (data, response) = try await sendAuthorized(with: auth) { token in
            try await transport.send(body, token: token)
        }

        if let error = httpError(data, response) { throw error }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.graphQL("malformed response")
        }
        let errors = root["errors"] as? [[String: Any]] ?? []
        if let payload = root["data"] as? [String: Any] { return (payload, errors) }
        if errors.contains(where: { $0["type"] as? String == "INSUFFICIENT_SCOPES" }) {
            throw APIError.insufficientScopes
        }
        if errors.contains(where: { $0["type"] as? String == "RATE_LIMITED" }) {
            throw APIError.rateLimited(resetAt: APIError.rateLimitEnd(response, now: now()))
        }
        // A refused mutation may come back without a data object at all.
        if query.hasPrefix("mutation"), Self.isForbidden(errors) { throw Self.refusal(errors) }
        throw APIError.graphQL(errors.first?["message"] as? String ?? "empty response")
    }
}
