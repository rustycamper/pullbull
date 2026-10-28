import Foundation

/// Whose work a poll covers: one organization, or, for an account in none, the user's own repositories.
public enum FetchScope: Hashable, Sendable {
    case org(String)
    /// `repos` (lowercased `owner/name`, as `AccessChecker.repositories` returns them) limits it to the repositories an app installation on the user's
    /// account was given; nil is every repository `login` owns.
    case personal(login: String, repos: Set<String>? = nil)

    /// The org; nil for the personal scope.
    public var org: String? {
        guard case .org(let org) = self else { return nil }
        return org
    }

    /// The search qualifier that keeps a search to this scope.
    public var searchQualifier: String {
        switch self {
        case .org(let org): "org:\(org)"
        case .personal(let login, _): "user:\(login)"
        }
    }

    /// Whether an item in `repo` (`owner/name`) belongs to this scope. An org's searches already keep
    /// to it; the personal scope keeps the login's own repos, and of those only `repos` when set.
    public func covers(_ repo: String) -> Bool {
        guard case .personal(let login, let repos) = self else { return true }
        let owner = repo.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        guard owner.caseInsensitiveCompare(login) == .orderedSame else { return false }
        return repos?.contains(repo.lowercased()) ?? true
    }

    /// What follows `<login>@` in the snapshot file's name. Org logins can't start with `-`, so the
    /// personal scope never shares a file with an org.
    var cacheKey: String {
        switch self {
        case .org(let org): org
        case .personal: "-personal"
        }
    }
}

public extension PRTab {
    /// The PR tabs shown for `scope`: Team needs an org's members.
    static func shown(in scope: FetchScope) -> [PRTab] {
        scope.org == nil ? allCases.filter { $0 != .team } : allCases
    }
}
