import Foundation

/// One side of a filtered search: the `@`, `~`, `is:`, `status:`, `updated:` and `review:` terms it includes,
/// or the ones it excludes. Logins and labels keep the case typed, deduplicated case-insensitively; `me` is always
/// lowercase. States are deduplicated, statuses deduplicated case-insensitively.
public struct SearchTerms: Equatable, Sendable {
    public var logins: [String]
    public var labels: [String]
    public var states: [StateFilter]
    public var statuses: [BoardStatusFilter]
    /// Included: at most one, the last typed. Excluded: every one typed.
    public var updated: [UpdatedFilter]
    /// The `is:` values that aren't states.
    public var conditions: [ItemCondition]
    public var reviews: [ReviewFilter]
    /// Included: any of them. Excluded: none of them.
    public var repos: [RepoToken]

    public init(
        logins: [String] = [], labels: [String] = [], states: [StateFilter] = [], statuses: [BoardStatusFilter] = [],
        updated: [UpdatedFilter] = [], conditions: [ItemCondition] = [], reviews: [ReviewFilter] = [],
        repos: [RepoToken] = []
    ) {
        self.logins = logins
        self.labels = labels
        self.states = states
        self.statuses = statuses
        self.updated = updated
        self.conditions = conditions
        self.reviews = reviews
        self.repos = repos
    }

    public var isEmpty: Bool {
        logins.isEmpty && labels.isEmpty && states.isEmpty && statuses.isEmpty && updated.isEmpty
            && conditions.isEmpty && reviews.isEmpty && repos.isEmpty
    }

    /// The `@` tokens, then the `~` tokens, then the `is:` tokens (states, then conditions), then the
    /// `status:` tokens, then the `updated:` tokens, then the `review:` tokens, then the `repo:` tokens.
    var tokens: [String] {
        logins.map { "@\($0)" } + labels.map(SearchQuery.labelToken) + states.map(\.token) + conditions.map(\.token)
            + statuses.map(\.token) + updated.map(\.token) + reviews.map(\.token)
            + repos.map(\.token)
    }

    mutating func add(login: String) {
        if !logins.contains(where: { $0.lowercased() == login.lowercased() }) { logins.append(login) }
    }

    mutating func add(label: String) {
        if !labels.contains(where: { $0.lowercased() == label.lowercased() }) { labels.append(label) }
    }

    mutating func add(state: StateFilter) {
        if !states.contains(state) { states.append(state) }
    }

    mutating func add(condition: ItemCondition) {
        if !conditions.contains(condition) { conditions.append(condition) }
    }

    mutating func add(review: ReviewFilter) {
        if !reviews.contains(review) { reviews.append(review) }
    }

    mutating func add(repo: RepoToken) {
        if !repos.contains(where: { $0.text.lowercased() == repo.text.lowercased() }) { repos.append(repo) }
    }

    mutating func add(status: BoardStatusFilter) {
        if !statuses.contains(where: { $0.isSame(as: status) }) { statuses.append(status) }
    }

    /// Whether each login, label, state, condition, review and status term holds for `pr` (`holds` true) or
    /// fails for it (`holds` false). A pull request has no Status.
    func every(holds: Bool, _ pr: PullRequest, viewer: String) -> Bool {
        logins.allSatisfy { !PersonMatch.roles(of: pr, login: $0, viewer: viewer).isEmpty == holds }
            && labels.allSatisfy { Self.has($0, pr.labels) == holds }
            && states.allSatisfy { $0.matches(pr) == holds }
            && conditions.allSatisfy { $0.matches(pr, viewer: viewer) == holds }
            && reviews.allSatisfy { $0.matches(pr) == holds }
            && statuses.allSatisfy { $0.matches(nil) == holds }
            && inRepos(pr.key.repo, holds: holds)
    }

    func every(holds: Bool, _ issue: BoardIssue, viewer: String) -> Bool {
        logins.allSatisfy { !PersonMatch.roles(of: issue, login: $0, viewer: viewer).isEmpty == holds }
            && labels.allSatisfy { Self.has($0, issue.labels) == holds }
            && states.allSatisfy { $0.matches(issue) == holds }
            && conditions.allSatisfy { $0.matches(issue, viewer: viewer) == holds }
            && statuses.allSatisfy { $0.matches(issue.status?.name) == holds }
            && inRepos(issue.key.repo, holds: holds)
    }

    /// With no `repo:` term, true. Otherwise any of them matches `repo` (`holds` true) or none does.
    private func inRepos(_ repo: String, holds: Bool) -> Bool {
        repos.isEmpty || repos.contains { $0.matches(repo: repo) } == holds
    }

    private static func has(_ label: String, _ labels: [String]) -> Bool {
        labels.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
    }
}

/// A filtered search: the terms an item must pass, the terms it must fail, and the words its title holds
/// (lowercased).
public struct SearchFilter: Equatable, Sendable {
    public var include: SearchTerms
    public var exclude: SearchTerms
    public var words: [String]

    public init(include: SearchTerms = SearchTerms(), exclude: SearchTerms = SearchTerms(), words: [String] = []) {
        self.include = include
        self.exclude = exclude
        self.words = words
    }

    /// Included terms only, as the signatures from before exclusion take them.
    static func included(
        logins: [String], labels: [String], states: [StateFilter] = [], statuses: [BoardStatusFilter] = [],
        updated: UpdatedFilter? = nil, words: [String]
    ) -> SearchFilter {
        SearchFilter(
            include: SearchTerms(
                logins: logins, labels: labels, states: states, statuses: statuses, updated: updated.map { [$0] } ?? []),
            words: words)
    }

    /// The included tokens in kind order, then the excluded ones, each with a leading `-`.
    public var tokens: [String] {
        include.tokens + exclude.tokens.map { "-" + $0 }
    }

    /// The search keeps to pull requests: the issue search is skipped and no issue matches. Any condition but
    /// `is:unanswered` or any review does that, included or excluded.
    public var prOnly: Bool {
        (include.conditions + exclude.conditions).contains(where: \.prOnly)
            || !include.reviews.isEmpty || !exclude.reviews.isEmpty
    }

    /// Nothing to ask GitHub: a condition about the viewer's own comments, which GitHub can't search, so the
    /// snapshot answers it, included or excluded.
    var localOnly: Bool {
        (include.conditions + exclude.conditions).contains(.unanswered)
    }

    /// The included `updated:` window and the excluded ones as of `now`, worked out once for a query's rows.
    func windows(now: Date, calendar: Calendar) -> (window: UpdatedFilter.Window?, excluded: [UpdatedFilter.Window]) {
        (include.updated.last?.resolved(now: now, calendar: calendar),
         exclude.updated.map { $0.resolved(now: now, calendar: calendar) })
    }

    /// `pr` passes every included term, fails every excluded one, and has every word in its title. `window`
    /// and `excludedWindows` are the `updated:` windows `windows(now:calendar:)` works out.
    public func matches(
        _ pr: PullRequest, viewer: String, window: UpdatedFilter.Window?, excludedWindows: [UpdatedFilter.Window]
    ) -> Bool {
        window?.matches(pr) != false && excludedWindows.allSatisfy { $0.excludes(pr) } && matchesTitle(pr.title)
            && include.every(holds: true, pr, viewer: viewer) && exclude.every(holds: false, pr, viewer: viewer)
    }

    public func matches(
        _ issue: BoardIssue, viewer: String, window: UpdatedFilter.Window?, excludedWindows: [UpdatedFilter.Window]
    ) -> Bool {
        !prOnly && window?.matches(issue) != false && excludedWindows.allSatisfy { $0.excludes(issue) }
            && matchesTitle(issue.title)
            && include.every(holds: true, issue, viewer: viewer) && exclude.every(holds: false, issue, viewer: viewer)
    }

    private func matchesTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        return words.allSatisfy { lowered.contains($0) }
    }

    /// What GitHub gets for this filter, after the scope and `is:pr` or `is:issue`: every included state as
    /// GitHub names it, the included `updated:` as `serverQualifier` writes it for `now`, `involves:` for the
    /// first login only (`me` is `@me`), a `label:` for every label (GitHub ANDs them), the words quoted as
    /// title terms; then the exclusions: `-author:` for every login (a commenter or reviewer isn't excluded
    /// on GitHub, so it never drops a row the local filter keeps), `-label:` and `-is:`. An excluded `status:`
    /// is the board's, which GitHub doesn't know, and an excluded `updated:` is never sent either: GitHub
    /// judges it on `updatedAt`, while the local filter reads a closed item's close date, so GitHub would drop
    /// rows the local filter keeps. The same goes for an excluded condition or review: GitHub's `status:failure`
    /// and `review:none` aren't known to match exactly what the local filter does, so their `-` forms could drop
    /// rows it keeps. An included condition or review sends its form only when GitHub's match holds every row
    /// the local one does (`is:failing`, `review:none`).
    ///
    /// `repos` resolves the `repo:` terms. The included ones are sent when every one resolves to a known repo
    /// (GitHub ORs them, as the local filter does), and not at all when a `focus` already names the one repo
    /// searched, since GitHub would OR it with the focus. An excluded one is sent as `-repo:owner/name` only
    /// when it resolves to one known repo, so GitHub never drops more than the local filter does.
    ///
    /// GitHub ORs `repo:` with the `org:` or `user:` scope, so `SearchEngine.remoteQuery` sends the repos
    /// from `resolvedRepos` in place of the scope, and passes `includingRepos: false` to leave them out here.
    public func serverQualifiers(
        now: Date, calendar: Calendar, repos: RepoIndex = .empty, focused: Bool = false,
        includingRepos: Bool = true
    ) -> [String] {
        var parts = include.states.map(\.token)
        if let updated = include.updated.last { parts.append(updated.serverQualifier(now: now, calendar: calendar)) }
        if let login = include.logins.first { parts.append("involves:\(Self.serverLogin(login))") }
        parts += SearchEngine.quoted(include.labels).map { "label:\($0)" }
        parts += include.conditions.compactMap(\.serverQualifier)
        parts += include.reviews.compactMap(\.serverQualifier)
        if includingRepos { parts += resolvedRepos(repos, focused: focused).map { "repo:\($0)" } }
        let quotedWords = SearchEngine.quoted(words)
        if !quotedWords.isEmpty { parts.append("in:title \(quotedWords.joined(separator: " "))") }
        parts += exclude.logins.map { "-author:\(Self.serverLogin($0))" }
        parts += SearchEngine.quoted(exclude.labels).map { "-label:\($0)" }
        parts += exclude.states.map { "-" + $0.token }
        parts += Self.distinct(exclude.repos.compactMap { repos.resolve($0) }).map { "-repo:\($0)" }
        return parts
    }

    /// The tokens, read without case or repeats and sorted, with each `updated:` as GitHub gets it for `now`,
    /// so a step's key changes when the day does.
    public func cacheTokens(now: Date, calendar: Calendar) -> [String] {
        func dated(_ terms: SearchTerms) -> [String] {
            var undated = terms
            undated.updated = []
            return undated.tokens + terms.updated.map { $0.serverQualifier(now: now, calendar: calendar) }
        }
        return Set((dated(include) + dated(exclude).map { "-" + $0 }).map { $0.lowercased() }).sorted()
    }

    /// The `owner/name` of every included `repo:` term, when each resolves to one known repo and no focus
    /// already names the repo searched; else none.
    func resolvedRepos(_ repos: RepoIndex, focused: Bool) -> [String] {
        guard !focused, !include.repos.isEmpty else { return [] }
        let resolved = include.repos.map { repos.resolve($0) }
        guard resolved.allSatisfy({ $0 != nil }) else { return [] }
        return Self.distinct(resolved.compactMap { $0 })
    }

    private static func distinct(_ repos: [String]) -> [String] {
        var seen = Set<String>()
        return repos.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func serverLogin(_ login: String) -> String { login == "me" ? "@me" : login }
}

extension UpdatedFilter.Window {
    /// Whether an excluded `updated:` window keeps `pr`: it wasn't active within it. A raw value's window
    /// keeps nothing, as its included form matches nothing.
    func excludes(_ pr: PullRequest) -> Bool { !matchesNothing && !matches(pr) }

    /// An issue with no date is kept.
    func excludes(_ issue: BoardIssue) -> Bool { !matchesNothing && !matches(issue) }
}
