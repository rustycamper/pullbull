import Testing
@testable import PullBullKit

@Suite struct DiffstatBlocksTests {
    private static func split(_ additions: Int, _ deletions: Int) -> [Int] {
        let blocks = DiffstatBlocks(additions: additions, deletions: deletions)
        return [blocks.additions, blocks.deletions, blocks.neutral]
    }

    @Test func noChangesIsAllNeutral() {
        #expect(Self.split(0, 0) == [0, 0, 5])
    }

    @Test func onlyAdditionsIsAllGreen() {
        #expect(Self.split(184, 0) == [5, 0, 0])
        #expect(Self.split(5, 0) == [5, 0, 0])
    }

    @Test func smallDiffsFillOneBlockPerLine() {
        #expect(Self.split(1, 0) == [1, 0, 4])
        #expect(Self.split(2, 1) == [2, 1, 2])
        #expect(Self.split(0, 4) == [0, 4, 1])
    }

    @Test func onlyDeletionsIsAllRed() {
        #expect(Self.split(0, 42) == [0, 5, 0])
    }

    @Test func splitsByShare() {
        #expect(Self.split(184, 42) == [4, 1, 0])
        #expect(Self.split(60, 40) == [3, 2, 0])
        #expect(Self.split(40, 60) == [2, 3, 0])
    }

    @Test func anyNonZeroSideGetsABlock() {
        #expect(Self.split(1000, 1) == [4, 1, 0])
        #expect(Self.split(1, 1000) == [1, 4, 0])
    }

    @Test func evenSplitRoundsTowardAdditions() {
        #expect(Self.split(1, 1) == [1, 1, 3])
        #expect(Self.split(5, 5) == [3, 2, 0])
    }

    @Test func negativeCountsCountAsZero() {
        #expect(Self.split(-3, 0) == [0, 0, 5])
    }
}
