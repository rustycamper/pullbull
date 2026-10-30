import Foundation

public enum SearchQuery: Equatable, Sendable {
    case number(Int)
    /// One PR or issue by its repository (`owner/name`) and number, from a pasted link or `o/r#12`.
    case item(repo: String, number: Int)
    case text([String])
    /// `@login`, `~label`, `is:`, `status:` and `updated:` terms ANDed with title words, each included or,
    /// after a `-`, excluded. Two states that contradict match nothing, and so does a term both included and
    /// excluded. Any included status keeps the search to board issues. An included `updated:` term limits the
    /// search to recent activity (the last one typed counts).
    case filtered(SearchFilter)
    case empty

    /// A `.filtered` query of included terms only.
    public static func filtered(
        logins: [String], labels: [String], words: [String], states: [StateFilter] = [],
        statuses: [BoardStatusFilter] = [], updated: UpdatedFilter? = nil
    ) -> SearchQuery {
        .filtered(.included(
            logins: logins, labels: labels, states: states, statuses: statuses, updated: updated, words: words))
    }

    /// `pending` is a range of `raw` (an `@`, `~`, `is:`, `status:` or `updated:` token still being completed) that is left out of
    /// the query; a `-` left before it is dropped. An `is:` with a value that isn't a state is a word, and so
    /// is a `-` before anything but a sigil.
    public static func parse(_ raw: String, excluding pending: Range<String.Index>? = nil) -> SearchQuery {
        var source = raw
        if let pending { source.replaceSubrange(pending, with: " ") }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if let item = ItemReference(trimmed) { return .item(repo: item.repo, number: item.number) }
        let digits = trimmed.hasPrefix("#")
            ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        if digits.isEmpty { return .empty }
        if digits.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(digits) {
            return .number(number)
        }
        var filter = SearchFilter()
        for term in QueryScanner.terms(in: trimmed) {
            let side: WritableKeyPath<SearchFilter, SearchTerms> = term.negated ? \.exclude : \.include
            switch term.kind {
            case .person:
                let rest = term.value
                if rest.isEmpty { continue }
                if isLogin(rest) {
                    filter[keyPath: side].add(login: rest.lowercased() == "me" ? "me" : String(rest))
                    continue
                }
                filter.words.append(trimmed[term.range].lowercased())
            case .label, .labelAlias:
                let label = term.value.trimmingCharacters(in: .whitespaces)
                if label.isEmpty { continue }
                filter[keyPath: side].add(label: label)
            case .state:
                if term.value.isEmpty { continue }
                if let state = StateFilter(rawValue: term.value.lowercased()) {
                    filter[keyPath: side].add(state: state)
                    continue
                }
                filter.words.append(trimmed[term.range].lowercased())
            case .status:
                let name = term.value.trimmingCharacters(in: .whitespaces)
                if name.isEmpty { continue }
                filter[keyPath: side].add(status: BoardStatusFilter(name: name, exact: term.quoted))
            case .updated:
                if term.value.isEmpty { continue }
                let updated = UpdatedFilter.parse(String(term.value))
                if !term.negated {
                    filter.include.updated = [updated]
                } else if !filter.exclude.updated.contains(updated) {
                    filter.exclude.updated.append(updated)
                }
            case .word:
                // What a pending token leaves of `-@an`.
                if term.value == "-" { continue }
                filter.words.append(trimmed[term.range].lowercased())
            }
        }
        if !filter.include.isEmpty || !filter.exclude.isEmpty { return .filtered(filter) }
        return filter.words.isEmpty ? .empty : .text(filter.words)
    }

    /// A GitHub login: 1 to 39 of `A-Z a-z 0-9 -`, not starting with `-`.
    public static func isLogin(_ s: Substring) -> Bool {
        guard (1...39).contains(s.count), s.first != "-" else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// `@a`, `@a and @b`, or `@a, @b and @c`.
    public static func mentionList(_ logins: [String]) -> String {
        joinedList(logins.map { "@\($0)" })
    }

    /// The `@` tokens, then the `~` tokens, then the `is:` tokens, then the `status:` tokens, then the
    /// `updated:` token, listed as `mentionList` lists names.
    public static func tokenList(
        logins: [String], labels: [String], states: [StateFilter] = [], statuses: [BoardStatusFilter] = [],
        updated: UpdatedFilter? = nil
    ) -> String {
        joinedList(
            SearchFilter.included(
                logins: logins, labels: labels, states: states, statuses: statuses, updated: updated, words: []
            ).tokens)
    }

    /// `~bug`, or `~"good first issue"` for a name with whitespace.
    public static func labelToken(_ name: String) -> String {
        name.contains(where: \.isWhitespace) ? "~\"\(name)\"" : "~\(name)"
    }

    /// `a`, `a and b`, or `a, b and c`.
    static func joinedList(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    public var filter: SearchFilter? {
        if case .filtered(let filter) = self { return filter }
        return nil
    }

    /// The included logins; `filter` has the excluded ones.
    public var logins: [String] { filter?.include.logins ?? [] }

    /// The included labels.
    public var labels: [String] { filter?.include.labels ?? [] }

    /// The included states.
    public var states: [StateFilter] { filter?.include.states ?? [] }

    /// The included statuses.
    public var statuses: [BoardStatusFilter] { filter?.include.statuses ?? [] }

    /// The included `updated:` term.
    public var updated: UpdatedFilter? { filter?.include.updated.last }

    public var words: [String] {
        switch self {
        case .text(let words): return words
        case .filtered(let filter): return filter.words
        case .number, .item, .empty: return []
        }
    }

    /// Nothing to ask GitHub: empty, or a search for an included `status:`. GitHub knows no board Status, and
    /// the snapshot holds the whole board, so such a match is always local. An excluded `status:` keeps pull
    /// requests and issues off the board, so GitHub is still asked.
    var isLocalOnly: Bool { self == .empty || !statuses.isEmpty }

    /// The repo focus a search for this query keeps to: none for `.item`, which names its own repository.
    public func keeping(_ focus: RepoFocus?) -> RepoFocus? {
        if case .item = self { return nil }
        return focus
    }

    private func matches(number: Int, title: String) -> Bool {
        switch self {
        case .number(let n): return number == n
        case .item: return false
        case .text(let words):
            let lowered = title.lowercased()
            return words.allSatisfy { lowered.contains($0) }
        case .filtered, .empty: return false
        }
    }
}

extension SearchQuery {
    /// A `.filtered` query matches when every included login has a role on the item, every included label
    /// is one of its labels (by name, ignoring case), it is in every included state, its board Status matches
    /// every included status, every word is in its title and its activity date is within the included
    /// `updated:` step or date form (a raw `updated:` value matches nothing), and every excluded term fails
    /// by the same rule (an excluded raw `updated:` value matches nothing too); `.number` and `.text` match
    /// as before. A pull request has no Status.
    func matches(_ pr: PullRequest, viewer: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let windows = updatedWindows(now: now, calendar: calendar)
        return matches(pr, viewer: viewer, window: windows.window, excludedWindows: windows.excluded)
    }

    /// As above, with the `updated:` windows already worked out, for a loop over many rows.
    func matches(
        _ pr: PullRequest, viewer: String, window: UpdatedFilter.Window?, excludedWindows: [UpdatedFilter.Window]
    ) -> Bool {
        switch self {
        case .filtered(let filter):
            return filter.matches(pr, viewer: viewer, window: window, excludedWindows: excludedWindows)
        case .item:
            return names(pr.key)
        default:
            return matches(number: pr.key.number, title: pr.title)
        }
    }

    func matches(_ issue: BoardIssue, viewer: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let windows = updatedWindows(now: now, calendar: calendar)
        return matches(issue, viewer: viewer, window: windows.window, excludedWindows: windows.excluded)
    }

    func matches(
        _ issue: BoardIssue, viewer: String, window: UpdatedFilter.Window?, excludedWindows: [UpdatedFilter.Window]
    ) -> Bool {
        switch self {
        case .filtered(let filter):
            return filter.matches(issue, viewer: viewer, window: window, excludedWindows: excludedWindows)
        case .item:
            return names(issue.key)
        default:
            return matches(number: issue.key.number, title: issue.title)
        }
    }

    /// The filter's `updated:` windows as of `now`; none for any other query.
    func updatedWindows(
        now: Date, calendar: Calendar
    ) -> (window: UpdatedFilter.Window?, excluded: [UpdatedFilter.Window]) {
        filter?.windows(now: now, calendar: calendar) ?? (nil, [])
    }

    /// An `.item` for `key`, the repository read without case.
    func names(_ key: PRKey) -> Bool {
        guard case .item(let repo, let number) = self else { return false }
        return key.number == number && key.repo.caseInsensitiveCompare(repo) == .orderedSame
    }
}

public enum SearchPhase: Equatable, Sendable {
    case searching
    case done
    case failedRemote(String)
}

public struct SearchResults: Equatable, Sendable {
    public var openPRs: [PullRequest]
    public var closedPRs: [PullRequest]
    /// Open issues first, then by most recently updated.
    public var issues: [BoardIssue]
    public var phase: SearchPhase
    /// GitHub's title search had more matches than were fetched.
    public var truncated: Bool

    public init(
        openPRs: [PullRequest], closedPRs: [PullRequest], issues: [BoardIssue], phase: SearchPhase,
        truncated: Bool = false
    ) {
        self.openPRs = openPRs
        self.closedPRs = closedPRs
        self.issues = issues
        self.phase = phase
        self.truncated = truncated
    }

    public var openIssues: [BoardIssue] { issues.filter(\.isOpen) }
    public var closedIssues: [BoardIssue] { issues.filter { !$0.isOpen } }

    /// Pull requests and issues are searched separately, each capped at the same number of matches.
    public var truncationNote: String? {
        truncated
            ? "Showing the \(SearchEngine.remotePageSize * SearchEngine.remoteTextPages) most recent matches of each kind"
            : nil
    }

    public var isEmpty: Bool { openPRs.isEmpty && closedPRs.isEmpty && issues.isEmpty }

    /// The current mode's results in display order: open then closed-or-merged pull requests in PR mode,
    /// open then closed issues in Issues mode. The other kind only feeds `crossModeFallback`.
    public func orderedKeys(mode: PopoverMode) -> [PRKey] {
        switch mode {
        case .pullRequests: return openPRs.map(\.key) + closedPRs.map(\.key)
        case .issues: return openIssues.map(\.key) + closedIssues.map(\.key)
        }
    }

    /// No result of the mode's kind.
    public func isEmpty(in mode: PopoverMode) -> Bool {
        switch mode {
        case .pullRequests: return openPRs.isEmpty && closedPRs.isEmpty
        case .issues: return issues.isEmpty
        }
    }

    /// The failure `mode` shows: its kind's title search failed, or GitHub wasn't reached at all. Nil
    /// when only the other kind's search failed, which leaves this kind's answer whole.
    public func failure(in mode: PopoverMode) -> String? {
        guard case .failedRemote(let message) = phase else { return nil }
        switch message {
        case SearchEngine.issueFailureMessage: return mode == .issues ? message : nil
        case SearchEngine.prFailureMessage: return mode == .pullRequests ? message : nil
        default: return message
        }
    }

    /// `phase` as `mode` sees it: the other kind's failed title search counts as done.
    public func phase(in mode: PopoverMode) -> SearchPhase {
        if case .failedRemote = phase, failure(in: mode) == nil { return .done }
        return phase
    }

    /// Once the search is over, the mode has no match and the other kind has some: the line that says
    /// so and switches to it. Nil while searching, and when the other kind's search failed, since its
    /// matches are unknown.
    public func crossModeFallback(mode: PopoverMode, query: SearchQuery) -> CrossModeFallback? {
        let other: PopoverMode = mode == .pullRequests ? .issues : .pullRequests
        guard phase != .searching, isEmpty(in: mode), failure(in: other) == nil else { return nil }
        let count = orderedKeys(mode: other).count
        guard count > 0 else { return nil }
        // `#123` across several repositories is counted instead.
        let number: Int? = switch query {
        case .number(let n) where count == 1: n
        case .item(_, let n): n
        default: nil
        }
        return CrossModeFallback(target: other, count: count, number: number)
    }

    /// Named for the mode's kind. With `scope`, a link to a repository outside it says so. Only when the
    /// mode's search is done with no match and `crossModeFallback` has nothing to show instead.
    public func emptyMessage(
        org: String, query: SearchQuery, scope: FetchScope? = nil, mode: PopoverMode
    ) -> String? {
        guard phase(in: mode) == .done, isEmpty(in: mode), crossModeFallback(mode: mode, query: query) == nil
        else { return nil }
        let one = mode == .pullRequests ? "PR" : "issue"
        let kind = mode == .pullRequests ? "pull requests" : "issues"
        switch query {
        case .number(let n): return "No \(one) #\(n) in \(org)"
        case .item(let repo, let n):
            guard let scope, !scope.reaches(repo) else { return "No \(one) #\(n) in \(repo)" }
            return "PullBull searches \(scope.org ?? "your repos") only, not \(repo)"
        case .text(let words): return "No \(kind) match “\(words.joined(separator: " "))”"
        case .filtered(let filter):
            let names = SearchQuery.joinedList(filter.tokens)
            return filter.words.isEmpty
                ? "No \(kind) with \(names)"
                : "No \(kind) with \(names) match “\(filter.words.joined(separator: " "))”"
        case .empty: return nil
        }
    }
}

/// The quiet line in place of the empty message when only the other mode's kind matches: how many
/// match (or, for one number looked up, what it is) and the shortcut to that mode.
public struct CrossModeFallback: Equatable, Sendable {
    /// The mode with the matches.
    public let target: PopoverMode
    public let count: Int
    /// The number looked up, when the match is that one item.
    public let number: Int?

    public init(target: PopoverMode, count: Int, number: Int? = nil) {
        self.target = target
        self.count = count
        self.number = number
    }

    /// `2 issues match · ⌘2`, `1 pull request matches · ⌘1`, `#123 is an issue · ⌘2`.
    public var text: String { "\(statement) · ⌘\(digit)" }

    /// The statement and where it goes, for VoiceOver.
    public var accessibilityLabel: String {
        "\(statement). Show \(target == .pullRequests ? "pull requests" : "issues"), Command-\(digit)"
    }

    private var digit: Int { target == .pullRequests ? 1 : 2 }

    private var statement: String {
        let one = target == .pullRequests ? "pull request" : "issue"
        if let number { return "#\(number) is \(target == .pullRequests ? "a" : "an") \(one)" }
        return count == 1 ? "1 \(one) matches" : "\(count) \(one)s match"
    }
}

public struct SearchEngine: Sendable {
    static let remoteFailureMessage = "Couldn't reach GitHub, showing local results only"
    /// The issue title search failed but the PR search did not.
    static let issueFailureMessage = "Couldn't search issues on GitHub, showing local issues only"
    /// The PR title search failed but the issue search did not.
    static let prFailureMessage = "Couldn't search pull requests on GitHub, showing local pull requests only"
    /// Title search fetches at most this many pages of `remotePageSize`, newest first: one page of 100 (GitHub's
    /// maximum) is one round trip where two pages of 50 were two in a row.
    static let remoteTextPages = 1
    static let remotePageSize = 100

    private let api: GitHubAPI

    public init(api: GitHubAPI) { self.api = api }

    /// The snapshot's matches; with `focus`, only those in its repository.
    public func local(_ q: SearchQuery, in snap: Snapshot, focus: RepoFocus? = nil) -> SearchResults {
        let focus = q.keeping(focus)
        guard q != .empty else {
            return SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .searching)
        }
        let prs = snap.reviewCandidates + snap.mine + snap.team + snap.recentlyClosed
        let (window, excluded) = q.updatedWindows(now: Date(), calendar: .current)
        let matching = prs.filter {
            q.matches($0, viewer: snap.org.viewer, window: window, excludedWindows: excluded) && Self.inFocus($0.key, focus)
        }
        let issues = Self.cachedIssues(snap).filter {
            q.matches($0, viewer: snap.org.viewer, window: window, excludedWindows: excluded) && Self.inFocus($0.key, focus)
        }
        return Self.assemble(prs: matching, issues: issues, phase: .searching)
    }

    /// `focus` keeps a search, local and remote, to its repository; `.item` names its own.
    public func results(_ q: SearchQuery, snap: Snapshot, focus: RepoFocus? = nil) -> AsyncStream<SearchResults> {
        let focus = q.keeping(focus)
        let localResults = local(q, in: snap, focus: focus)
        if q.isLocalOnly {
            var done = localResults
            done.phase = .done
            return Self.finished(with: [done])
        }
        return fetching(
            q, snap: snap, focus: focus, local: localResults, first: localResults, cached: nil, cache: nil)
    }

    /// A search through `cache`: `first` shows at once, `updates` follow. A fresh answer is final and
    /// fetches nothing. A stale one shows while GitHub is asked again `debounce` later, and stays if
    /// that fails. Without one, the snapshot's matches show until GitHub answers, as `results` does.
    /// A focused search has its own cache entries. A `status:` search is the snapshot's alone and final.
    public func results(
        _ q: SearchQuery, snap: Snapshot, account: AccountRef, cache: SearchCache, focus: RepoFocus? = nil,
        debounce: Duration = .zero
    ) -> (first: SearchResults, updates: AsyncStream<SearchResults>) {
        let focus = q.keeping(focus)
        let localResults = local(q, in: snap, focus: focus)
        guard !q.isLocalOnly else {
            var done = localResults
            done.phase = .done
            return (done, Self.finished(with: []))
        }
        let key = SearchCache.Key(account: account, scope: snap.scope, query: q, focus: focus)
        switch cache.lookup(key) {
        case .fresh(let entry):
            return (Self.merge(entry, local: localResults, snap: snap, phase: .done), Self.finished(with: []))
        case .stale(let entry):
            let first = Self.merge(entry, local: localResults, snap: snap, phase: .searching)
            let updates = fetching(
                q, snap: snap, focus: focus, local: localResults, first: nil, cached: entry, cache: (cache, key),
                debounce: debounce)
            return (first, updates)
        case .miss:
            let updates = fetching(
                q, snap: snap, focus: focus, local: localResults, first: nil, cached: nil, cache: (cache, key),
                debounce: debounce)
            return (localResults, updates)
        }
    }

    private static func finished(with values: [SearchResults]) -> AsyncStream<SearchResults> {
        let (stream, continuation) = AsyncStream.makeStream(of: SearchResults.self)
        values.forEach { continuation.yield($0) }
        continuation.finish()
        return stream
    }

    /// Yields `first` (when given), then GitHub's answer merged with `local`. A complete answer is
    /// stored in `cache`. When the fetch fails, `cached` (when given) shows as final instead.
    private func fetching(
        _ q: SearchQuery, snap: Snapshot, focus: RepoFocus?, local localResults: SearchResults, first: SearchResults?,
        cached: SearchCache.Entry?, cache: (cache: SearchCache, key: SearchCache.Key)?, debounce: Duration = .zero
    ) -> AsyncStream<SearchResults> {
        let (stream, continuation) = AsyncStream.makeStream(of: SearchResults.self)
        let api = api
        let task = Task {
            if let first { continuation.yield(first) }
            do {
                if debounce > .zero { try await Task.sleep(for: debounce) }
                let fetchedAt = cache?.cache.now() ?? Date()
                let remote = try await Self.fetchRemote(q, snap: snap, focus: focus, api: api)
                try Task.checkCancellation()
                let complete = !remote.issuesFailed && !remote.prsFailed
                if let cached, !complete {
                    // Half an answer doesn't replace a whole one.
                    continuation.yield(Self.merge(cached, local: localResults, snap: snap, phase: .done))
                } else {
                    if complete, let cache { cache.cache.store(remote, fetchedAt: fetchedAt, for: cache.key) }
                    // A failed title search of one kind keeps the other kind's remote matches and its own
                    // local ones, and says so.
                    let phase: SearchPhase =
                        remote.issuesFailed ? .failedRemote(Self.issueFailureMessage)
                        : remote.prsFailed ? .failedRemote(Self.prFailureMessage) : .done
                    let entry = SearchCache.Entry(remote: remote, fetchedAt: fetchedAt)
                    continuation.yield(Self.merge(entry, local: localResults, snap: snap, phase: phase))
                }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    if let cached {
                        continuation.yield(Self.merge(cached, local: localResults, snap: snap, phase: .done))
                    } else {
                        var failed = localResults
                        failed.phase = .failedRemote(Self.remoteFailureMessage)
                        continuation.yield(failed)
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// `local` (the snapshot's matches) with GitHub's rows. Of GitHub's copy and the snapshot's, the one
    /// updated later wins, the one fetched later on a tie; a winning snapshot copy that no longer
    /// matches leaves the row out. The board copy supplies the Status GitHub doesn't carry.
    private static func merge(
        _ entry: SearchCache.Entry, local localResults: SearchResults, snap: Snapshot, phase: SearchPhase
    ) -> SearchResults {
        func remoteWins(_ remote: Date?, over copy: Date?) -> Bool {
            let r = remote ?? .distantPast, c = copy ?? .distantPast
            return r != c ? r > c : entry.fetchedAt >= snap.fetchedAt
        }
        let snapshotPRs = Dictionary(
            (snap.reviewCandidates + snap.mine + snap.team + snap.recentlyClosed).map { ($0.key, $0) }
        ) { first, _ in first }
        let snapshotIssues = Dictionary(cachedIssues(snap).map { ($0.key, $0) }) { first, _ in first }
        let localPRs = localResults.openPRs + localResults.closedPRs
        var prs: [PRKey: PullRequest] = Dictionary(localPRs.map { ($0.key, $0) }) { first, _ in first }
        for pr in entry.remote.prs where snapshotPRs[pr.key].map({ remoteWins(pr.updatedAt, over: $0.updatedAt) }) ?? true {
            prs[pr.key] = pr
        }
        let boardCopies = Self.boardCopies(snap)
        var issues: [PRKey: BoardIssue] = Dictionary(localResults.issues.map { ($0.key, $0) }) { first, _ in first }
        for issue in entry.remote.issues
        where snapshotIssues[issue.key].map({ remoteWins(issue.updatedAt, over: $0.updatedAt) }) ?? true {
            issues[issue.key] = issue.withBoardItem(of: boardCopies[issue.key], in: snap)
        }
        var done = Self.assemble(prs: Array(prs.values), issues: Array(issues.values), phase: phase)
        done.truncated = entry.remote.truncated
        return done
    }

    /// Board, Assigned and Created issues, one per key: the copy updated most recently (the board copy
    /// on a tie or without dates), with the Status of the board copy.
    static func cachedIssues(_ snap: Snapshot) -> [BoardIssue] {
        var order: [PRKey] = []
        var newest: [PRKey: BoardIssue] = [:]
        for issue in snap.boardIssues + (snap.assignedIssues ?? []) + (snap.createdIssues ?? []) {
            guard let kept = newest[issue.key] else {
                order.append(issue.key)
                newest[issue.key] = issue
                continue
            }
            if isNewer(issue, than: kept) { newest[issue.key] = issue }
        }
        let boardCopies = boardCopies(snap)
        return order.compactMap { newest[$0] }.map { $0.withBoardItem(of: boardCopies[$0.key], in: snap) }
    }

    /// `issues` (a tab's copies) with the board item and shown Status of their board copy, as search
    /// results carry them.
    static func onBoard(_ issues: [BoardIssue], in snap: Snapshot) -> [BoardIssue] {
        let boardCopies = boardCopies(snap)
        return issues.map { $0.withBoardItem(of: boardCopies[$0.key], in: snap) }
    }

    /// The cached copy of one issue, picked as search picks it: the copy among board, Assigned and
    /// Created updated most recently, with the Status of the board copy. Nil when no list has it.
    public static func cachedIssue(_ key: PRKey, in snap: Snapshot) -> BoardIssue? {
        let board = snap.boardIssues.first { $0.key == key }
        let copies = [board].compactMap { $0 }
            + (snap.assignedIssues ?? []).filter { $0.key == key }
            + (snap.createdIssues ?? []).filter { $0.key == key }
        guard var newest = copies.first else { return nil }
        for issue in copies.dropFirst() where isNewer(issue, than: newest) { newest = issue }
        return newest.withBoardItem(of: board, in: snap)
    }

    /// Whether `issue` replaces the copy kept so far: only a strictly later `updatedAt` does.
    private static func isNewer(_ issue: BoardIssue, than kept: BoardIssue) -> Bool {
        guard let updated = issue.updatedAt else { return false }
        return updated > kept.updatedAt ?? .distantPast
    }

    private static func boardCopies(_ snap: Snapshot) -> [PRKey: BoardIssue] {
        Dictionary(snap.boardIssues.map { ($0.key, $0) }) { first, _ in first }
    }

    /// GitHub's rows for one query, before the snapshot is merged in.
    struct Remote: Sendable {
        var prs: [PullRequest] = []
        var issues: [BoardIssue] = []
        var truncated = false
        /// The issue title search failed; `issues` is empty.
        var issuesFailed = false
        /// The PR title search failed; `prs` is empty.
        var prsFailed = false
    }

    /// Throws when the lookup fails or both title searches fail; one failed title search only sets
    /// `prsFailed` or `issuesFailed`. With `focus`, GitHub is asked about its repository only.
    private static func fetchRemote(
        _ q: SearchQuery, snap: Snapshot, focus: RepoFocus?, api: GitHubAPI
    ) async throws -> Remote {
        // A personal scope limited to an installation's repos drops matches elsewhere.
        let scope = snap.scope
        switch q {
        case .number(let n):
            guard n > 0, n <= Int(Int32.max) else { return Remote() }
            // `org.org` is the repos' owner: the org, or the login in the personal scope.
            let (owner, repos) = focus.map(lookupTarget) ?? (snap.org.org, snap.org.repos)
            let found = try await api.lookup(number: n, org: owner, repos: repos)
            func kept(_ key: PRKey) -> Bool { key.number == n && scope.covers(key.repo) && inFocus(key, focus) }
            return Remote(prs: found.prs.filter { kept($0.key) }, issues: found.issues.filter { kept($0.key) })
        case .item(let repo, let n):
            // Only the scope's repositories are asked about; the focus doesn't apply.
            guard scope.reaches(repo) else { return Remote() }
            let (owner, repos) = lookupTarget(RepoFocus(repo: repo))
            let found = try await api.lookup(number: n, org: owner, repos: repos)
            return Remote(prs: found.prs.filter { q.names($0.key) }, issues: found.issues.filter { q.names($0.key) })
        case .text(let words):
            return try await searchTitles(q, sent: SearchFilter(words: words), snap: snap, focus: focus, api: api)
        case .filtered(let filter):
            // A raw `updated:` value, included or excluded, is GitHub's to judge, so the rows it returns aren't
            // checked against it here.
            func isRaw(_ updated: UpdatedFilter) -> Bool {
                if case .raw = updated { return true }
                return false
            }
            var checked = filter
            checked.include.updated.removeAll(where: isRaw)
            checked.exclude.updated.removeAll(where: isRaw)
            return try await searchTitles(.filtered(checked), sent: filter, snap: snap, focus: focus, api: api)
        case .empty:
            return Remote()
        }
    }

    /// The owner and the one repository name a focused `#123`, or an `.item`, asks about.
    private static func lookupTarget(_ focus: RepoFocus) -> (owner: String, repos: [String]) {
        let parts = focus.repo.split(separator: "/", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], [parts[1]]) : ("", [])
    }

    static func inFocus(_ key: PRKey, _ focus: RepoFocus?) -> Bool {
        focus?.matches(key) ?? true
    }

    /// The PR and issue search strings within `scope` (`org:` or `user:`), or `repo:` for `focus`: the
    /// filter's `serverQualifiers` for `now`, newest first.
    static func remoteQuery(
        kind: String, scope: FetchScope, focus: RepoFocus? = nil, filter: SearchFilter, now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let qualifier = focus.map { "repo:\($0.repo)" } ?? scope.searchQualifier
        let parts = [qualifier, "is:\(kind)"] + filter.serverQualifiers(now: now, calendar: calendar)
        return (parts + ["sort:updated-desc"]).joined(separator: " ")
    }

    /// As above, for included terms only.
    static func remoteQuery(
        kind: String, scope: FetchScope, focus: RepoFocus? = nil, logins: [String], labels: [String],
        states: [StateFilter] = [], updated: UpdatedFilter? = nil, words: [String], now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        remoteQuery(
            kind: kind, scope: scope, focus: focus,
            filter: .included(logins: logins, labels: labels, states: states, updated: updated, words: words), now: now,
            calendar: calendar)
    }

    /// Each term in double quotes, without the quotes and backslashes it held; empty terms are dropped.
    static func quoted(_ terms: [String]) -> [String] {
        terms.compactMap { term -> String? in
            let bare = term.filter { $0 != "\"" && $0 != "\\" }
            return bare.isEmpty ? nil : "\"\(bare)\""
        }
    }

    /// GitHub's rows for `sent`, each checked against `q`.
    private static func searchTitles(
        _ q: SearchQuery, sent: SearchFilter, snap: Snapshot, focus: RepoFocus?, api: GitHubAPI
    ) async throws -> Remote {
        let now = Date()
        guard !sent.serverQualifiers(now: now, calendar: .current).isEmpty else { return Remote() }
        // A personal scope limited to an installation's repos drops matches elsewhere.
        let scope = snap.scope
        let prQuery = remoteQuery(kind: "pr", scope: scope, focus: focus, filter: sent, now: now)
        // An included `is:merged` or `is:draft` matches no issue, so the issue search is skipped.
        let searchesIssues = !sent.prOnly && sent.include.states.allSatisfy(\.appliesToIssues)
        let issueQuery = searchesIssues
            ? remoteQuery(kind: "issue", scope: scope, focus: focus, filter: sent, now: now)
            : nil
        async let prSearch = api.searchPRs(prQuery, maxPages: remoteTextPages, pageSize: remotePageSize)
        async let issueSearch = searchIssues(issueQuery, api: api)
        var remote = Remote()
        let (window, excluded) = q.updatedWindows(now: now, calendar: .current)
        do {
            let prs = try await prSearch
            remote.prs = prs.prs.filter {
                q.matches($0, viewer: snap.org.viewer, window: window, excludedWindows: excluded)
                    && scope.covers($0.key.repo) && inFocus($0.key, focus)
            }
            remote.truncated = prs.hasMore
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Without an issue search, this was the only one.
            if !searchesIssues { throw error }
            remote.prsFailed = true
        }
        do {
            guard let issues = try await issueSearch else { return remote }
            // Checked with its board copy's Status, which an excluded `status:` reads.
            let boardCopies = Self.boardCopies(snap)
            remote.issues = issues.issues.filter {
                q.matches(
                    $0.withBoardItem(of: boardCopies[$0.key], in: snap), viewer: snap.org.viewer, window: window,
                    excludedWindows: excluded)
                    && scope.covers($0.key.repo) && inFocus($0.key, focus)
            }
            remote.truncated = remote.truncated || issues.hasMore
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if remote.prsFailed { throw error }
            remote.issuesFailed = true
        }
        return remote
    }

    /// The issue title search for `query`; nil when there is none to run.
    private static func searchIssues(
        _ query: String?, api: GitHubAPI
    ) async throws -> (issues: [BoardIssue], hasMore: Bool)? {
        guard let query else { return nil }
        return try await api.searchIssues(query, maxPages: remoteTextPages, pageSize: remotePageSize)
    }

    static func assemble(prs: [PullRequest], issues: [BoardIssue], phase: SearchPhase) -> SearchResults {
        var seen = Set<PRKey>()
        let unique = prs.filter { seen.insert($0.key).inserted }
        func tiebreak(_ a: PRKey, _ b: PRKey) -> Bool {
            a.repo != b.repo ? a.repo < b.repo : a.number < b.number
        }
        let open = unique.filter { $0.state == .open }.sorted {
            $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : tiebreak($0.key, $1.key)
        }
        let closed = unique.filter { $0.state != .open }.sorted {
            let a = $0.closedAt ?? .distantPast, b = $1.closedAt ?? .distantPast
            return a != b ? a > b : tiebreak($0.key, $1.key)
        }
        var seenIssues = Set<PRKey>()
        let sortedIssues = issues.filter { seenIssues.insert($0.key).inserted }.sorted {
            if $0.isOpen != $1.isOpen { return $0.isOpen }
            let a = $0.updatedAt ?? .distantPast, b = $1.updatedAt ?? .distantPast
            return a != b ? a > b : tiebreak($0.key, $1.key)
        }
        return SearchResults(openPRs: open, closedPRs: closed, issues: sortedIssues, phase: phase)
    }
}

private extension BoardIssue {
    /// This copy with the board item of `board`, the same issue's board copy (nil when it is not on
    /// the board), and its Status only where the lists show it.
    func withBoardItem(of board: BoardIssue?, in snap: Snapshot) -> BoardIssue {
        BoardIssue(
            key: key, title: title, url: url, isOpen: isOpen, author: author, stateReason: stateReason,
            createdAt: createdAt, updatedAt: updatedAt, closedAt: closedAt, commentCount: commentCount,
            labels: labels, labelColors: labelColors, assignees: assignees, status: IssueTabBuilder.shownStatus(board?.status, in: snap),
            boardItemId: board?.boardItemId, myAssignment: myAssignment)
    }
}
