import Foundation

/// One side of a filtered search: the `@`, `~`, `is:`, `status:` and `updated:` terms it includes, or the
/// ones it excludes. Logins and labels keep the case typed, deduplicated case-insensitively; `me` is always
/// lowercase. States are deduplicated, statuses deduplicated case-insensitively.
public struct SearchTerms: Equatable, Sendable {
    public var logins: [String]
    public var labels: [String]
    public var states: [StateFilter]
    public var statuses: [BoardStatusFilter]
    /// Included: at most one, the last typed. Excluded: every one typed.
    public var updated: [UpdatedFilter]

    public init(
        logins: [String] = [], labels: [String] = [], states: [StateFilter] = [], statuses: [BoardStatusFilter] = [],
        updated: [UpdatedFilter] = []
    ) {
        self.logins = logins
        self.labels = labels
        self.states = states
        self.statuses = statuses
        self.updated = updated
    }

    public var isEmpty: Bool {
        logins.isEmpty && labels.isEmpty && states.isEmpty && statuses.isEmpty && updated.isEmpty
    }

    /// The `@` tokens, then the `~` tokens, then the `is:` tokens, then the `status:` tokens, then the
    /// `updated:` tokens.
    var tokens: [String] {
        logins.map { "@\($0)" } + labels.map(SearchQuery.labelToken) + states.map(\.token) + statuses.map(\.token)
            + updated.map(\.token)
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

    mutating func add(status: BoardStatusFilter) {
        if !statuses.contains(where: { $0.isSame(as: status) }) { statuses.append(status) }
    }

    /// Whether each login, label, state and status term holds for `pr` (`holds` true) or fails for it (`holds`
    /// false). A pull request has no Status.
    func every(holds: Bool, _ pr: PullRequest, viewer: String) -> Bool {
        logins.allSatisfy { !PersonMatch.roles(of: pr, login: $0, viewer: viewer).isEmpty == holds }
            && labels.allSatisfy { Self.has($0, pr.labels) == holds }
            && states.allSatisfy { $0.matches(pr) == holds }
            && statuses.allSatisfy { $0.matches(nil) == holds }
    }

    func every(holds: Bool, _ issue: BoardIssue, viewer: String) -> Bool {
        logins.allSatisfy { !PersonMatch.roles(of: issue, login: $0, viewer: viewer).isEmpty == holds }
            && labels.allSatisfy { Self.has($0, issue.labels) == holds }
            && states.allSatisfy { $0.matches(issue) == holds }
            && statuses.allSatisfy { $0.matches(issue.status?.name) == holds }
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

    /// The search keeps to pull requests: the issue search is skipped and no issue matches.
    public var prOnly: Bool { false }

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
    /// on GitHub, so it never drops a row the local filter keeps), `-label:`, `-is:` and `-updated:`. A
    /// `status:` is the board's, which GitHub doesn't know, so it is never sent.
    public func serverQualifiers(now: Date, calendar: Calendar) -> [String] {
        var parts = include.states.map(\.token)
        if let updated = include.updated.last { parts.append(updated.serverQualifier(now: now, calendar: calendar)) }
        if let login = include.logins.first { parts.append("involves:\(Self.serverLogin(login))") }
        parts += SearchEngine.quoted(include.labels).map { "label:\($0)" }
        let quotedWords = SearchEngine.quoted(words)
        if !quotedWords.isEmpty { parts.append("in:title \(quotedWords.joined(separator: " "))") }
        parts += exclude.logins.map { "-author:\(Self.serverLogin($0))" }
        parts += SearchEngine.quoted(exclude.labels).map { "-label:\($0)" }
        parts += exclude.states.map { "-" + $0.token }
        parts += exclude.updated.map { "-" + $0.serverQualifier(now: now, calendar: calendar) }
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

    private static func serverLogin(_ login: String) -> String { login == "me" ? "@me" : login }
}

extension UpdatedFilter.Window {
    /// Whether an excluded `updated:` window keeps `pr`: it wasn't active within it. A raw value's window
    /// keeps nothing, as its included form matches nothing.
    func excludes(_ pr: PullRequest) -> Bool { !matchesNothing && !matches(pr) }

    /// An issue with no date is kept.
    func excludes(_ issue: BoardIssue) -> Bool { !matchesNothing && !matches(issue) }
}
