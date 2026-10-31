import Foundation

public protocol GraphQLTransport: Sendable {
    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse)
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
    public let author: String
    public let body: String
    public let createdAt: Date

    public init(author: String, body: String, createdAt: Date) {
        self.author = author
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

    public init(
        key: PRKey, body: String, checks: [Check], reviews: [Review],
        comments: [Comment], files: [ChangedFile], updatedAt: Date? = nil, ci: CIState? = nil,
        changedFiles: Int? = nil, additions: Int? = nil, deletions: Int? = nil, checkCount: Int? = nil
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
    }

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

/// The read-only detail of one issue.
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

        let commentNodes = (pr["comments"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
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
            checkCount: checkCount)
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
        let author = (node["author"] as? [String: Any])?["login"] as? String ?? "ghost"
        return Comment(author: author, body: body, createdAt: created)
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
                case "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE": state = .failure
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

    // MARK: Transport

    /// Sends one query and returns `data`. Partial results (errors alongside data) are returned as data.
    /// A 401 is reported to the token source; the query is sent again, once, when it has a new token.
    private func execute(_ query: String, _ variables: [String: Any]) async throws -> [String: Any] {
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

        if let sso = APIError.ssoRequired(in: response) { throw sso }
        switch response.statusCode {
        case 401:
            throw APIError.unauthorized
        case 403, 429:
            if let limited = APIError.rateLimited(in: response, body: data, now: now()) { throw limited }
            throw response.statusCode == 403 ? APIError.forbidden : APIError.server(response.statusCode)
        case 500...:
            throw APIError.server(response.statusCode)
        case 200..<300:
            break
        default:
            throw APIError.server(response.statusCode)
        }

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
        throw APIError.graphQL(errors.first?["message"] as? String ?? "empty response")
    }
}
