import Foundation

/// A `repo:` term: `repo:widgets` for every repository of that name, `repo:acme/widgets` for the one.
public struct RepoToken: Hashable, Sendable {
    /// As typed.
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var token: String { "repo:\(text)" }

    /// `repo` is `owner/name`. With a `/` the whole of it has to match, else only the name part does; case
    /// is ignored.
    public func matches(repo: String) -> Bool {
        let wanted = text.lowercased()
        let name = repo.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repo
        return (text.contains("/") ? repo : name).lowercased() == wanted
    }
}

/// A row of the `repo:` completion.
public struct RepoCandidate: CompletionCandidate {
    /// `owner/name`, as first seen.
    public let repo: String
    /// Distinct counted PRs and issues listed in it; 0 when unknown.
    public let openCount: Int
    /// No other repository in the index has this name.
    let uniqueName: Bool

    public var id: String { repo.lowercased() }
    public var name: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    /// `repo:` and the name when it's unique in the index, else `repo:owner/name`.
    public var insertText: String { "repo:" + (uniqueName ? name : repo) }

    init(repo: String, openCount: Int, uniqueName: Bool) {
        self.repo = repo
        self.openCount = openCount
        self.uniqueName = uniqueName
    }
}

/// Every repository PullBull has seen, for the `repo:` completion and for resolving a token to the one
/// repository GitHub is asked about. Derived, never stored.
public struct RepoIndex: Equatable, Sendable {
    public static let empty = RepoIndex(repos: [])

    private let repos: [RepoCandidate]

    private init(repos: [RepoCandidate]) {
        self.repos = repos
    }

    /// The focus menu's repositories, for completion in the app.
    public init(choices: [RepoChoice]) {
        self.init(entries: choices.map { ($0.repo, $0.openCount) })
    }

    /// Every repository of the snapshot's pull requests and issues, for resolution in the engine.
    public static func build(_ snap: Snapshot) -> RepoIndex {
        let prs = snap.reviewCandidates + snap.mine + snap.team + snap.recentlyClosed
        let issues = snap.boardIssues + (snap.assignedIssues ?? []) + (snap.createdIssues ?? [])
        return RepoIndex(entries: (prs.map(\.key.repo) + issues.map(\.key.repo)).map { ($0, 0) })
    }

    private init(entries: [(repo: String, openCount: Int)]) {
        var seen = Set<String>()
        let distinct = entries.filter { seen.insert($0.repo.lowercased()).inserted }
        var names: [String: Int] = [:]
        for entry in distinct { names[Self.name(of: entry.repo).lowercased(), default: 0] += 1 }
        repos = distinct.map {
            RepoCandidate(
                repo: $0.repo, openCount: $0.openCount, uniqueName: names[Self.name(of: $0.repo).lowercased()] == 1)
        }
    }

    public var isEmpty: Bool { repos.isEmpty }

    /// The one `owner/name` `token` matches; nil when it matches none or several.
    public func resolve(_ token: RepoToken) -> String? {
        let found = repos.filter { token.matches(repo: $0.repo) }
        return found.count == 1 ? found[0].repo : nil
    }

    /// Ranked for prefix `p`, ignoring case, over the name and then `owner/name` by `LabelIndex.tier`.
    /// Within a tier, more items first, then by `owner/name`.
    public func candidates(prefix: String, limit: Int = 6) -> [RepoCandidate] {
        let p = prefix.lowercased()
        var ranked: [(tier: Int, repo: RepoCandidate)] = []
        for repo in repos {
            let tiers = [repo.name.lowercased(), repo.id].compactMap { LabelIndex.tier(of: $0, for: p) }
            if let tier = tiers.min() { ranked.append((tier, repo)) }
        }
        ranked.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.repo.openCount != b.repo.openCount { return a.repo.openCount > b.repo.openCount }
            return a.repo.id < b.repo.id
        }
        return ranked.prefix(limit).map(\.repo)
    }

    private static func name(of repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
}
