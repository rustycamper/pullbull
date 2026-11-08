import Testing
@testable import PullBullKit

private let a = PRKey(repo: "o/a", number: 1)
private let b = PRKey(repo: "o/a", number: 2)
private let c = PRKey(repo: "o/b", number: 3)

private func issue(_ key: PRKey) -> DetailTrail.Entry { .init(kind: .issue, key: key) }
private func pr(_ key: PRKey) -> DetailTrail.Entry { .init(kind: .pullRequest, key: key) }

@Suite struct DetailTrailTests {
    @Test func startsOnBase() {
        let trail = DetailTrail(base: issue(a))
        #expect(trail.previous == nil)
        #expect(trail.isOnBase)
        #expect(trail.current == issue(a))
        #expect(trail.base == issue(a))
    }

    @Test func followAppendsAcrossKinds() {
        var trail = DetailTrail(base: issue(a))
        trail.follow(issue(b))
        trail.follow(pr(c))
        #expect(trail.entries.map(\.key) == [a, b, c])
        #expect(trail.previous?.key == b)
        #expect(trail.current == pr(c))
        #expect(!trail.isOnBase)
    }

    @Test func backStepsToPrevious() {
        var trail = DetailTrail(base: issue(a))
        trail.follow(issue(b))
        trail.follow(pr(c))
        #expect(trail.back()?.key == b)
        #expect(trail.back()?.key == a)
        #expect(trail.back() == nil)
        #expect(trail.entries.map(\.key) == [a])
    }

    @Test func followingAnEarlierEntryTruncates() {
        var trail = DetailTrail(base: issue(a))
        trail.follow(issue(b))
        trail.follow(issue(a))
        #expect(trail.entries.map(\.key) == [a])
        #expect(trail.isOnBase)

        var longer = DetailTrail(base: issue(a))
        longer.follow(issue(b))
        longer.follow(pr(c))
        longer.follow(issue(b))
        #expect(longer.entries.map(\.key) == [a, b])
    }

    @Test func followingTheCurrentEntryIsNoOp() {
        var trail = DetailTrail(base: issue(a))
        trail.follow(issue(b))
        trail.follow(issue(b))
        #expect(trail.entries.map(\.key) == [a, b])
    }

    @Test func sameNumberDifferentKindOrRepoAreDistinct() {
        let five = PRKey(repo: "o/r", number: 5)
        var trail = DetailTrail(base: issue(five))
        trail.follow(pr(five))
        #expect(trail.entries == [issue(five), pr(five)])

        trail.follow(issue(PRKey(repo: "o/other", number: 5)))
        #expect(trail.entries.count == 3)
    }
}
