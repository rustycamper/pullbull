import Testing
@testable import PullBullKit

private let a = PRKey(repo: "o/a", number: 1)
private let b = PRKey(repo: "o/a", number: 2)
private let c = PRKey(repo: "o/b", number: 3)
private let z = PRKey(repo: "o/z", number: 9)

@Suite struct DetailWalkTests {
    @Test func opensAtIndex() throws {
        let walk = try #require(DetailWalk(keys: [a, b, c], opening: b, kind: .pullRequest))
        #expect(walk.current == b)
        #expect(walk.index == 1)
        #expect(walk.position(showing: b, kind: .pullRequest) == "2 of 3")
    }

    @Test func stepsAndStops() throws {
        let walk = try #require(DetailWalk(keys: [a, b, c], opening: b, kind: .pullRequest))
        let next = try #require(walk.stepped(by: 1))
        #expect(next.current == c)
        #expect(next.position(showing: c, kind: .pullRequest) == "3 of 3")
        #expect(next.stepped(by: 1) == nil)
        let first = try #require(walk.stepped(by: -1))
        #expect(first.current == a)
        #expect(first.stepped(by: -1) == nil)
    }

    @Test func notInKeysIsNil() {
        #expect(DetailWalk(keys: [a], opening: z, kind: .pullRequest) == nil)
        #expect(DetailWalk(keys: [], opening: z, kind: .issue) == nil)
    }

    @Test func walkIgnoresAnotherDetail() throws {
        let walk = try #require(DetailWalk(keys: [a, b, c], opening: b, kind: .pullRequest))
        #expect(walk.position(showing: z, kind: .pullRequest) == nil)
        // A linked PR opened from an issue walk, the other way round.
        #expect(walk.position(showing: b, kind: .issue) == nil)
        // A key of the walk that isn't the current one isn't the walk's either.
        #expect(walk.position(showing: a, kind: .pullRequest) == nil)
    }

    @Test func singleItem() throws {
        let walk = try #require(DetailWalk(keys: [a], opening: a, kind: .issue))
        #expect(walk.position(showing: a, kind: .issue) == "1 of 1")
        #expect(walk.stepped(by: 1) == nil)
        #expect(walk.stepped(by: -1) == nil)
    }

    @Test func skipsWhatCantOpen() throws {
        let d = PRKey(repo: "o/b", number: 4)
        let walk = try #require(DetailWalk(keys: [a, b, c, d], opening: a, kind: .pullRequest))
        // b left the data: the step lands on c, which keeps its place in the snapshot.
        let next = try #require(walk.stepped(by: 1, skipping: { $0 == b }))
        #expect(next.current == c)
        #expect(next.position(showing: c, kind: .pullRequest) == "3 of 4")
        let back = try #require(next.stepped(by: -1, skipping: { $0 == b }))
        #expect(back.current == a)
        // Nothing left to open that way: the step stops, as at the end.
        #expect(next.stepped(by: 1, skipping: { $0 == d }) == nil)
        #expect(walk.stepped(by: 1, skipping: { $0 != a }) == nil)
    }

    @Test func snapshotIsKept() throws {
        // The walk holds its own copy of the order; the source changing later doesn't reach it.
        var keys = [a, b, c]
        let walk = try #require(DetailWalk(keys: keys, opening: a, kind: .pullRequest))
        keys.reverse()
        #expect(walk.keys == [a, b, c])
        #expect(walk.stepped(by: 1)?.current == b)
    }
}
