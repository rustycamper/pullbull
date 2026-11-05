import Foundation
import Testing
@testable import PullBullKit

private struct Boom: Error {}

@MainActor private final class Script {
    var answers: [Result<Set<Int64>?, Error>]
    var reads = 0
    var sleeps: [Duration] = []
    var sleepFails = false
    init(_ answers: [Result<Set<Int64>?, Error>]) { self.answers = answers }

    func settle(sent: Set<Int64>) async {
        await RerunFlow.settle(
            sent: sent,
            read: {
                self.reads += 1
                return try self.answers.removeFirst().get()
            },
            sleep: {
                self.sleeps.append($0)
                if self.sleepFails { throw Boom() }
            })
    }
}

@Suite struct RerunFlowTests {
    private let key = PRKey(repo: "o/r", number: 88)

    @Test func theConstantsAreThreeReadsTwoSecondsApart() {
        #expect(RerunFlow.reads == 3)
        #expect(RerunFlow.readGap == .seconds(2))
    }

    @MainActor @Test func stopsAtTheFirstReadThatShowsAllRestarted() async {
        let script = Script([.success([]), .success([1])])
        await script.settle(sent: [1, 2])
        #expect(script.reads == 1)
        #expect(script.sleeps.isEmpty)
    }

    @MainActor @Test func stopsOnceNoneOfTheSentRunsIsOffered() async {
        let script = Script([.success([1, 2]), .success([9]), .success([1])])
        await script.settle(sent: [1, 2])
        #expect(script.reads == 2)
        #expect(script.sleeps == [.seconds(2)])
    }

    @MainActor @Test func aRunOfferedAmongOthersKeepsItGoing() async {
        let script = Script([.success([1]), .success([1]), .success([1])])
        await script.settle(sent: [1, 2])
        #expect(script.reads == 3)
    }

    @MainActor @Test func readsThreeTimesWithTwoSleepsThenGivesUp() async {
        let script = Script([.success([1]), .success([1]), .success([1]), .success([])])
        await script.settle(sent: [1])
        #expect(script.reads == 3)
        #expect(script.sleeps == [.seconds(2), .seconds(2)])
    }

    @MainActor @Test func aFailedReadCountsAsOneOfThree() async {
        let script = Script([.failure(Boom()), .failure(Boom()), .failure(Boom()), .success([])])
        await script.settle(sent: [1])
        #expect(script.reads == 3)
        #expect(script.sleeps.count == 2)
    }

    @MainActor @Test func aSuccessAfterAFailedReadStops() async {
        let script = Script([.failure(Boom()), .success([])])
        await script.settle(sent: [1])
        #expect(script.reads == 2)
    }

    @MainActor @Test func aReadThatSaysStopEndsIt() async {
        let script = Script([.success(nil), .success([1])])
        await script.settle(sent: [1])
        #expect(script.reads == 1)
        #expect(script.sleeps.isEmpty)
    }

    @MainActor @Test func aThrowingSleepEndsIt() async {
        let script = Script([.success([1]), .success([1]), .success([1])])
        script.sleepFails = true
        await script.settle(sent: [1])
        #expect(script.reads == 1)
        #expect(script.sleeps.count == 1)
    }

    @MainActor @Test func nothingSentMeansNoReads() async {
        let script = Script([.success([1])])
        await script.settle(sent: [])
        #expect(script.reads == 0)
        #expect(script.sleeps.isEmpty)
    }

    @Test func noRefusalsGivesNoLine() {
        #expect(RerunFlow.line(refusals: [], of: 3, on: key) == nil)
        #expect(RerunFlow.line(refusals: [], of: 0, on: key) == nil)
    }

    @Test func everyRunRefusedGivesTheFirstReason() {
        #expect(RerunFlow.line(refusals: ["no", "later"], of: 2, on: key)
            == EditMessage.rerunRefused(on: key, reason: "no"))
    }

    @Test func someRefusedGivesTheCount() {
        #expect(RerunFlow.line(refusals: ["no"], of: 3, on: key)
            == "Couldn't re-run 1 of 3 workflow runs on #88.")
    }
}
