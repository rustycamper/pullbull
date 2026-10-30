import Foundation

/// GitHub's answers to recent searches, as fetched (before the snapshot is merged in), in memory only.
/// An answer is fresh for two minutes, then shown while it is fetched again for up to ten; older ones
/// are gone. Entries belong to one account and scope: a key for another clears the rest. A repo focus
/// is part of the key, so focused and unfocused answers never mix; an `.item` names its own repository,
/// so its key has no focus.
public final class SearchCache: @unchecked Sendable {
    static let capacity = 32
    static let freshFor: TimeInterval = 120
    static let keptFor: TimeInterval = 600

    /// The account, the scope, the focused repo (lowercased; nil unfocused) and the query, read without
    /// case, spacing, repeats or term order.
    public struct Key: Hashable, Sendable {
        let account: AccountRef
        let scope: FetchScope
        let focus: String?
        let query: Query

        /// `now` and `calendar` date an `updated:` step, so its key changes when the day does.
        public init(
            account: AccountRef, scope: FetchScope, query: SearchQuery, focus: RepoFocus? = nil, now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.account = account
            self.scope = scope
            self.focus = query.keeping(focus)?.repo.lowercased()
            self.query = Query(query, now: now, calendar: calendar)
        }
    }

    enum Query: Hashable, Sendable {
        case number(Int)
        case item(repo: String, number: Int)
        /// `extra` holds the filter's other cache tokens: its exclusions and included statuses.
        case terms(
            logins: [String], labels: [String], words: [String], states: [StateFilter], updated: String?,
            extra: [String])
        case empty

        init(_ query: SearchQuery, now: Date, calendar: Calendar) {
            switch query {
            case .number(let n): self = .number(n)
            case .item(let repo, let n): self = .item(repo: repo.lowercased(), number: n)
            case .empty: self = .empty
            case .text, .filtered:
                self = .terms(
                    logins: Self.folded(query.logins), labels: Self.folded(query.labels),
                    words: Self.folded(query.words),
                    states: Set(query.states).sorted { $0.rawValue < $1.rawValue },
                    updated: query.updated?.serverQualifier(now: now, calendar: calendar),
                    extra: Self.extra(query.filter, now: now, calendar: calendar))
            }
        }

        /// `filter`'s cache tokens less the included logins, labels, states and `updated:` the other parts hold.
        private static func extra(_ filter: SearchFilter?, now: Date, calendar: Calendar) -> [String] {
            guard let filter else { return [] }
            let include = filter.include
            let held = SearchFilter(include: SearchTerms(
                logins: include.logins, labels: include.labels, states: include.states, updated: include.updated))
            let heldTokens = Set(held.cacheTokens(now: now, calendar: calendar))
            return filter.cacheTokens(now: now, calendar: calendar).filter { !heldTokens.contains($0) }
        }

        private static func folded(_ terms: [String]) -> [String] {
            Set(terms.map { $0.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }).sorted()
        }
    }

    struct Entry: Sendable {
        let remote: SearchEngine.Remote
        let fetchedAt: Date
    }

    enum Lookup: Sendable {
        /// Shown as is; nothing is fetched.
        case fresh(Entry)
        /// Shown while it is fetched again.
        case stale(Entry)
        case miss
    }

    let now: @Sendable () -> Date
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    /// Least recently used first.
    private var order: [Key] = []
    private var owner: (account: AccountRef, scope: FetchScope)?

    public convenience init() {
        self.init(capacity: Self.capacity, now: { Date() })
    }

    init(capacity: Int, now: @escaping @Sendable () -> Date) {
        self.capacity = capacity
        self.now = now
    }

    var count: Int { lock.withLock { entries.count } }

    func lookup(_ key: Key) -> Lookup {
        lock.withLock {
            claim(for: key)
            guard let entry = entries[key] else { return .miss }
            let age = now().timeIntervalSince(entry.fetchedAt)
            guard age < Self.keptFor else {
                entries[key] = nil
                order.removeAll { $0 == key }
                return .miss
            }
            touch(key)
            return age < Self.freshFor ? .fresh(entry) : .stale(entry)
        }
    }

    func store(_ remote: SearchEngine.Remote, fetchedAt: Date, for key: Key) {
        lock.withLock {
            claim(for: key)
            entries[key] = Entry(remote: remote, fetchedAt: fetchedAt)
            touch(key)
            while order.count > capacity { entries[order.removeFirst()] = nil }
        }
    }

    /// Sign-out, or another account or scope.
    public func removeAll() {
        lock.withLock {
            entries = [:]
            order = []
            owner = nil
        }
    }

    /// Drops every entry of another account or scope than `key`'s. Called with the lock held.
    private func claim(for key: Key) {
        if let owner, owner.account == key.account, owner.scope == key.scope { return }
        entries = [:]
        order = []
        owner = (key.account, key.scope)
    }

    /// Makes `key` the most recently used. Called with the lock held.
    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
