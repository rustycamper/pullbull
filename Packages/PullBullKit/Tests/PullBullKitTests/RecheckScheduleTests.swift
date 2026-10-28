import Foundation
import Testing
@testable import PullBullKit

private actor Checks {
    private(set) var count = 0
    private let results: (Int) -> RecheckResult

    init(_ results: @escaping @Sendable (Int) -> RecheckResult) { self.results = results }

    func next() -> RecheckResult {
        count += 1
        return results(count)
    }
}

@Suite struct RecheckScheduleTests {
    /// Lets the loop run `sleeps` sleeps, advancing the clock by each one as it is requested.
    private func drive(_ clock: TestClock, sleeps: Int) async {
        for index in 1...sleeps {
            let requested = await clock.waitForSleeps(index)
            clock.advance(by: requested[index - 1])
        }
    }

    @Test func personalInstallChecksFiveSecondsInThenEveryTenForTenMinutes() async {
        let clock = TestClock()
        let checks = Checks { _ in .unchanged }
        let task = Task { await RecheckSchedule.personalInstall.run(clock: clock) { await checks.next() } }
        await drive(clock, sleeps: 60)
        #expect(await task.value == .outOfTime)
        #expect(await checks.count == 60)
        let sleeps = clock.requestedSleeps
        #expect(sleeps.first == .seconds(5))
        #expect(sleeps.dropFirst().allSatisfy { $0 == .seconds(10) })
        #expect(sleeps.reduce(.zero, +) <= .seconds(600))
    }

    @Test func stopsAsSoonAsACheckFinds() async {
        let clock = TestClock()
        let checks = Checks { $0 == 3 ? .done : .unchanged }
        let task = Task { await RecheckSchedule.personalInstall.run(clock: clock) { await checks.next() } }
        await drive(clock, sleeps: 3)
        #expect(await task.value == .done)
        #expect(await checks.count == 3)
    }

    @Test func aResumedWaitUsesOnlyWhatIsLeft() async {
        let clock = TestClock()
        let checks = Checks { _ in .unchanged }
        let task = Task {
            await RecheckSchedule.personalInstall.run(clock: clock, startingAfter: .seconds(595)) { await checks.next() }
        }
        await drive(clock, sleeps: 1)
        #expect(await task.value == .outOfTime)
        #expect(await checks.count == 1)
    }

    @Test func aWaitWithNoTimeLeftChecksNothing() async {
        let clock = TestClock()
        let checks = Checks { _ in .unchanged }
        let end = await RecheckSchedule.personalInstall.run(clock: clock, startingAfter: .seconds(600)) {
            await checks.next()
        }
        #expect(end == .outOfTime)
        #expect(await checks.count == 0)
    }

    @Test func ghSetupCountsTenMinutesFromTheLastChange() async {
        let clock = TestClock()
        let checks = Checks { $0 == 30 ? .changed : .unchanged }
        let task = Task { await RecheckSchedule.ghSetup.run(clock: clock) { await checks.next() } }
        await drive(clock, sleeps: 90)
        #expect(await task.value == .outOfTime)
        #expect(await checks.count == 90)
        #expect(clock.requestedSleeps.allSatisfy { $0 == .seconds(10) })
    }

    @Test func personalInstallDoesNotRestartOnChange() async {
        let clock = TestClock()
        let checks = Checks { $0 == 30 ? .changed : .unchanged }
        let task = Task { await RecheckSchedule.personalInstall.run(clock: clock) { await checks.next() } }
        await drive(clock, sleeps: 60)
        #expect(await task.value == .outOfTime)
        #expect(await checks.count == 60)
    }

    @Test func cancellingStopsTheLoop() async {
        let clock = TestClock()
        let checks = Checks { _ in .unchanged }
        let task = Task { await RecheckSchedule.ghSetup.run(clock: clock) { await checks.next() } }
        _ = await clock.waitForSleeps(1)
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(await checks.count == 0)
    }
}
