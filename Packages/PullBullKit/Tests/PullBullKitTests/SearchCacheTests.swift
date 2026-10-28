import Foundation
import Testing
@testable import PullBullKit

/// A wall clock moved by hand.
final class ManualNow: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private let start = Date(timeIntervalSince1970: 1_790_000_000)
private let alice = AccountRef(login: "alice", source: .gh)
private let org = FetchScope.org("initech")

private func key(
    _ raw: String, account: AccountRef = alice, scope: FetchScope = org, focus: String? = nil
) -> SearchCache.Key {
    SearchCache.Key(account: account, scope: scope, query: SearchQuery.parse(raw), focus: focus.map(RepoFocus.init))
}

private func cache(_ clock: ManualNow, capacity: Int = SearchCache.capacity) -> SearchCache {
    SearchCache(capacity: capacity, now: { clock.now })
}

/// A remote answer told apart by its one PR number.
private func remote(_ number: Int) -> SearchEngine.Remote {
    SearchEngine.Remote(prs: [
        PullRequest(
            key: PRKey(repo: "initech/gadgets", number: number), title: "PR",
            url: URL(string: "https://github.com/initech/gadgets/pull/\(number)")!, author: "alice",
            authorAvatarURL: nil, state: .open, isDraft: false, createdAt: start, updatedAt: start, closedAt: nil,
            headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
            lastCommentAuthor: nil, latestReviews: [], reviewRequests: []),
    ])
}

private extension SearchCache.Lookup {
    var number: Int? {
        switch self {
        case .fresh(let entry), .stale(let entry): entry.remote.prs.first?.key.number
        case .miss: nil
        }
    }

    var isFresh: Bool { if case .fresh = self { true } else { false } }
    var isStale: Bool { if case .stale = self { true } else { false } }
}

@Suite struct SearchCacheTests {
    @Test func keyIgnoresCaseSpacingAndOrder() {
        #expect(key("Flaky test") == key("  test   FLAKY "))
        #expect(key("flaky flaky test") == key("test flaky"))
        #expect(key("@Alice ~Bug is:open fix") == key("fix is:open ~bug @alice"))
        #expect(key("@alice @bob") == key("@bob @alice"))
        #expect(key("is:open is:draft") == key("is:draft is:open"))
        #expect(key(#"~"good  first issue""#) == key(#"~"Good First Issue""#))
        #expect(key("flaky test") != key("flaky tests"))
        #expect(key("@alice") != key("alice"))
    }

    @Test func numberLookupsShareAKey() {
        #expect(key("#412") == key("412"))
        #expect(key("# 412") == key("412"))
        #expect(key("#412") != key("#41"))
    }

    @Test func keyCoversAccountAndScope() {
        #expect(key("x") != key("x", account: AccountRef(login: "bob", source: .gh)))
        #expect(key("x") != key("x", account: AccountRef(login: "alice", source: .gitHubApp)))
        #expect(key("x") != key("x", scope: .org("other")))
        #expect(key("x") != key("x", scope: .personal(login: "alice")))
    }

    /// A focused search is its own answer; the repo is read without case.
    @Test func keyCoversTheFocusedRepo() {
        #expect(key("x") != key("x", focus: "initech/widgets"))
        #expect(key("#412") != key("#412", focus: "initech/widgets"))
        #expect(key("x", focus: "initech/widgets") != key("x", focus: "initech/gadgets"))
        #expect(key("x", focus: "initech/widgets") == key("x", focus: "Initech/Widgets"))
    }

    /// A link names its own repo, so the focus is not part of its key; the repo is read without case.
    @Test func linkKeyIgnoresTheFocus() {
        let link = "https://github.com/initech/widgets/pull/250"
        #expect(key(link) == key(link, focus: "initech/gadgets"))
        #expect(key(link) == key("Initech/Widgets#250"))
        #expect(key(link) != key("initech/gadgets#250"))
        #expect(key(link) != key("#250"))
    }

    /// Focusing a repo keeps the unfocused answers: only another account or scope clears them.
    @Test func focusedAndUnfocusedAnswersLiveSideBySide() {
        let c = cache(ManualNow(start))
        c.store(remote(1), fetchedAt: start, for: key("x"))
        c.store(remote(2), fetchedAt: start, for: key("x", focus: "initech/widgets"))
        #expect(c.lookup(key("x")).number == 1)
        #expect(c.lookup(key("x", focus: "initech/widgets")).number == 2)
    }

    @Test func freshForTwoMinutesThenStaleUntilTen() {
        let clock = ManualNow(start)
        let c = cache(clock)
        #expect(c.lookup(key("x")).number == nil)
        c.store(remote(1), fetchedAt: clock.now, for: key("x"))
        #expect(c.lookup(key("x")).isFresh)
        clock.advance(by: 119)
        #expect(c.lookup(key("x")).isFresh)
        clock.advance(by: 1)
        #expect(c.lookup(key("x")).isStale)
        clock.advance(by: 479)
        #expect(c.lookup(key("x")).isStale)
        #expect(c.lookup(key("x")).number == 1)
        clock.advance(by: 1)
        #expect(c.lookup(key("x")).number == nil)
    }

    @Test func storingAgainRestartsTheClock() {
        let clock = ManualNow(start)
        let c = cache(clock)
        c.store(remote(1), fetchedAt: clock.now, for: key("x"))
        clock.advance(by: 300)
        c.store(remote(2), fetchedAt: clock.now, for: key("x"))
        #expect(c.lookup(key("x")).isFresh)
        #expect(c.lookup(key("x")).number == 2)
    }

    @Test func leastRecentlyUsedGoesFirst() {
        let clock = ManualNow(start)
        let c = cache(clock, capacity: 3)
        for (i, word) in ["a", "b", "c"].enumerated() { c.store(remote(i), fetchedAt: clock.now, for: key(word)) }
        _ = c.lookup(key("a"))
        c.store(remote(3), fetchedAt: clock.now, for: key("d"))
        #expect(c.lookup(key("b")).number == nil)
        #expect(c.lookup(key("a")).number == 0)
        #expect(c.lookup(key("c")).number == 2)
        #expect(c.lookup(key("d")).number == 3)
        #expect(c.count == 3)
    }

    @Test func capsAtThirtyTwo() {
        let clock = ManualNow(start)
        let c = cache(clock)
        for i in 0..<40 { c.store(remote(i), fetchedAt: clock.now, for: key("w\(i)")) }
        #expect(c.count == 32)
        #expect(c.lookup(key("w7")).number == nil)
        #expect(c.lookup(key("w8")).number == 8)
    }

    @Test func anotherAccountOrScopeClearsTheCache() {
        let clock = ManualNow(start)
        let c = cache(clock)
        c.store(remote(1), fetchedAt: clock.now, for: key("x"))
        #expect(c.lookup(key("x", scope: .org("other"))).number == nil)
        #expect(c.lookup(key("x")).number == nil)
        c.store(remote(2), fetchedAt: clock.now, for: key("x"))
        c.store(remote(3), fetchedAt: clock.now, for: key("y", account: AccountRef(login: "bob", source: .gh)))
        #expect(c.lookup(key("x")).number == nil)
    }

    @Test func removeAllEmptiesIt() {
        let clock = ManualNow(start)
        let c = cache(clock)
        c.store(remote(1), fetchedAt: clock.now, for: key("x"))
        c.removeAll()
        #expect(c.count == 0)
        #expect(c.lookup(key("x")).number == nil)
    }
}
