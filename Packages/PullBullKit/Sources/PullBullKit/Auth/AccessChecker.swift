import Foundation

/// One installation of the GitHub App on an account the user can reach.
public struct Installation: Sendable, Equatable {
    /// The installation's ID, for its repository list; nil when GitHub didn't send one.
    public let id: Int64?
    /// `account.login`.
    public let org: String
    /// `repository_selection == "all"`.
    public let allRepositories: Bool
    public let permissions: [String: String]
    /// `account.type == "Organization"`; false for an installation on a personal account.
    public let isOrganization: Bool

    public init(
        id: Int64? = nil, org: String, allRepositories: Bool, permissions: [String: String], isOrganization: Bool = true
    ) {
        self.id = id
        self.org = org
        self.allRepositories = allRepositories
        self.permissions = permissions
        self.isOrganization = isOrganization
    }

    public var canReadProjects: Bool {
        ["read", "write", "admin"].contains(permissions["organization_projects"] ?? "")
    }

    /// Labels and assignees, on issues and pull requests.
    public var canWriteIssues: Bool { ["write", "admin"].contains(permissions["issues"] ?? "") }

    /// A board item's Status, and adding an issue to the board.
    public var canWriteProjects: Bool { ["write", "admin"].contains(permissions["organization_projects"] ?? "") }
}

/// The repositories no-org mode covers for an app account's own-account installation.
public enum PersonalRepos: Equatable, Sendable {
    /// Every repository the login owns: the installation covers all, or there is none to limit by.
    case all
    /// Only these (lowercased `owner/name`).
    case selected(Set<String>)
    /// Limited to selected repositories whose list has never been read; polling waits. Retry reads it.
    case unreadable(RefreshError)

    /// Why the list couldn't be read: as a poll would say it when it can (offline, rate limited, …),
    /// else a plain "couldn't load".
    static func reason(_ error: any Error) -> RefreshError {
        let mapped = RefreshError(error)
        if case .other = mapped { return .other("Couldn't load the repositories PullBull can see") }
        return mapped
    }

    /// The polling scope's `repos`: nil for `.all`; nil too while unreadable, when nothing polls.
    public var repos: Set<String>? {
        guard case .selected(let repos) = self else { return nil }
        return repos
    }
}

public enum OrgAccess: Equatable, Sendable {
    case ok(allRepos: Bool, canReadProjects: Bool)
    /// The app is not installed on the org; the URL starts the installation.
    case notInstalled(URL)
    /// The org requires SAML SSO for this token; the URL (when GitHub sent one) starts a session.
    case ssoRequired(URL?)
}

/// Which orgs have the GitHub App installed for the signed-in user, and with what access.
public struct AccessChecker: Sendable {
    private let transport: any HTTPTransport
    private let auth: any TokenSource
    private let appSlug: String

    private static let perPage = 100
    private static let maxPages = 10

    public init(transport: any HTTPTransport, auth: any TokenSource, appSlug: String) {
        self.transport = transport
        self.auth = auth
        self.appSlug = appSlug
    }

    public func identity() async throws -> GitHubIdentity {
        let wire = try decode(UserWire.self, from: try await get("https://api.github.com/user"))
        return GitHubIdentity(login: wire.login, userID: wire.id, avatarURL: wire.avatarURL.flatMap(URL.init(string:)))
    }

    public func installations() async throws -> [Installation] {
        var result: [Installation] = []
        var seen = 0
        for page in 1...Self.maxPages {
            let data = try await get("https://api.github.com/user/installations?per_page=\(Self.perPage)&page=\(page)")
            let wire = try decode(InstallationsWire.self, from: data)
            result += wire.installations.map {
                Installation(
                    id: $0.id, org: $0.account.login, allRepositories: $0.repositorySelection == "all",
                    permissions: $0.permissions, isOrganization: $0.account.type == "Organization")
            }
            seen += wire.itemCount
            if wire.itemCount < Self.perPage || seen >= wire.totalCount { break }
        }
        return result
    }

    public func access(for org: String) async throws -> OrgAccess {
        do {
            return Self.access(for: org, in: try await installations(), appSlug: appSlug)
        } catch APIError.ssoRequired(let url) {
            return .ssoRequired(url)
        }
    }

    /// Only organization installations count: a personal account with the same login is not the org.
    public static func access(for org: String, in installations: [Installation], appSlug: String) -> OrgAccess {
        guard let match = installations.first(where: {
            $0.isOrganization && $0.org.caseInsensitiveCompare(org) == .orderedSame
        }) else {
            return .notInstalled(installURL(appSlug: appSlug))
        }
        return .ok(allRepos: match.allRepositories, canReadProjects: match.canReadProjects)
    }

    /// The installation that covers `scope`: the org's, or for the personal scope the one on the user's
    /// own account (never an org's). The personal scope's board is a user-owned one, which GitHub gives
    /// apps no permission to read (only organizations have a Projects permission), so no Projects access.
    public static func access(for scope: FetchScope, in installations: [Installation], appSlug: String) -> OrgAccess {
        switch scope {
        case .org(let org):
            return access(for: org, in: installations, appSlug: appSlug)
        case .personal(let login, _):
            guard let match = personalInstallation(of: login, in: installations) else {
                return .notInstalled(installURL(appSlug: appSlug))
            }
            return .ok(allRepos: match.allRepositories, canReadProjects: false)
        }
    }

    /// The installation on `login`'s own account, if any.
    public static func personalInstallation(of login: String, in installations: [Installation]) -> Installation? {
        installations.first { !$0.isOrganization && $0.org.caseInsensitiveCompare(login) == .orderedSame }
    }

    /// What no-org mode may show for `login`'s own-account installation: every owned repo, or only the
    /// selected ones. A failed read (or an installation without an ID) keeps `previous`, the last set
    /// read; with none it is `.unreadable`, so polling waits instead of widening to every owned repo.
    public func personalRepos(
        of login: String, in installations: [Installation], previous: Set<String>?
    ) async -> PersonalRepos {
        guard let installation = Self.personalInstallation(of: login, in: installations),
              !installation.allRepositories
        else { return .all }
        do {
            guard let id = installation.id else { throw APIError.graphQL("installation without an ID") }
            return .selected(try await repositories(installationID: id))
        } catch {
            if let previous { return .selected(previous) }
            return .unreadable(PersonalRepos.reason(error))
        }
    }

    /// The repositories an installation covers, as lowercased `owner/name` (for one limited to selected
    /// repositories; the scope's `repos`). Throws rather than return part of a list longer than the
    /// page cap.
    public func repositories(installationID: Int64) async throws -> Set<String> {
        var result: Set<String> = []
        var seen = 0
        var total = 0
        for page in 1...Self.maxPages {
            let data = try await get(
                "https://api.github.com/user/installations/\(installationID)/repositories?per_page=\(Self.perPage)&page=\(page)")
            let wire = try decode(RepositoriesWire.self, from: data)
            result.formUnion(wire.repositories.map { $0.fullName.lowercased() })
            seen += wire.repositories.count
            total = wire.totalCount
            if wire.repositories.count < Self.perPage || seen >= total { return result }
        }
        guard seen >= total else { throw APIError.graphQL("incomplete repository list") }
        return result
    }

    /// A GitHub App slug: non-empty lowercase letters, digits and hyphens.
    public static func isValidAppSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
    }

    private static let appsBase = URL(string: "https://github.com/apps/")!

    /// The slug is one percent-encoded path segment, so a malformed slug can neither crash nor
    /// change the path.
    public static func installURL(appSlug: String) -> URL {
        appsBase.appending(component: appSlug).appending(path: "installations/new")
    }

    /// The install page with the user's own account preselected (`targetID` is the user ID), so a
    /// personal user isn't asked which account to install on.
    public static func installURL(appSlug: String, targetID: Int64) -> URL {
        appsBase.appending(component: appSlug).appending(path: "installations/new/permissions")
            .appending(queryItems: [URLQueryItem(name: "target_id", value: String(targetID))])
    }

    /// Where the user changes which of their repositories an installation on their own account covers.
    public static func installationSettingsURL(id: Int64) -> URL {
        URL(string: "https://github.com/settings/installations/")!.appending(component: String(id))
    }

    /// Where the installation's new permissions are accepted: the org's installation settings (by an
    /// owner), or the user's own. Nil without an installation ID.
    public static func permissionsReviewURL(for installation: Installation) -> URL? {
        guard let id = installation.id else { return nil }
        guard installation.isOrganization else { return installationSettingsURL(id: id) }
        return URL(string: "https://github.com/organizations/")!
            .appending(component: installation.org)
            .appending(path: "settings/installations")
            .appending(component: String(id))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw APIError.graphQL("malformed response")
        }
        return value
    }

    /// GET with the app's token; a 2xx body, else the matching `APIError`.
    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.unreachable(.badURL) }
        let (data, response) = try await sendAuthorized(with: auth) { token in
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            return try await transport.send(request)
        }
        if let sso = APIError.ssoRequired(in: response) { throw sso }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw APIError.unauthorized
        case 403, 429:
            if let limited = APIError.rateLimited(in: response, body: data, now: Date()) { throw limited }
            throw response.statusCode == 403 ? APIError.forbidden : APIError.server(response.statusCode)
        default: throw APIError.server(response.statusCode)
        }
    }
}

private struct UserWire: Decodable {
    let login: String
    let id: Int64
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case login, id
        case avatarURL = "avatar_url"
    }
}

private struct RepositoriesWire: Decodable {
    struct Repository: Decodable {
        let fullName: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    let totalCount: Int
    let repositories: [Repository]

    enum CodingKeys: String, CodingKey {
        case repositories
        case totalCount = "total_count"
    }
}

private struct InstallationsWire: Decodable {
    struct Item: Decodable {
        struct Account: Decodable {
            let login: String
            let type: String?
        }
        let id: Int64?
        let account: Account
        let repositorySelection: String
        let permissions: [String: String]

        enum CodingKeys: String, CodingKey {
            case id, account, permissions
            case repositorySelection = "repository_selection"
        }
    }

    /// Decodes anything; stands in for an item that doesn't decode, so the list moves past it.
    private struct Skipped: Decodable {
        init(from decoder: any Decoder) {}
    }

    let totalCount: Int
    /// The items that decoded. One without `account.login`, say, is skipped rather than failing the list.
    let installations: [Item]
    /// Every item on the page, decoded or not, for paging.
    let itemCount: Int

    enum CodingKeys: String, CodingKey {
        case installations
        case totalCount = "total_count"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        var list = try container.nestedUnkeyedContainer(forKey: .installations)
        var items: [Item] = []
        var count = 0
        while !list.isAtEnd {
            count += 1
            if let item = try? list.decode(Item.self) {
                items.append(item)
            } else {
                _ = try list.decode(Skipped.self)
            }
        }
        installations = items
        itemCount = count
    }
}
