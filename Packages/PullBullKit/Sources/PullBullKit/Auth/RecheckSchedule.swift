import Foundation

/// What one timed re-check found.
public enum RecheckResult: Equatable, Sendable {
    /// What was waited for happened; the checks stop.
    case done
    /// Something changed, but not that.
    case changed
    case unchanged
}

/// Why a run of timed re-checks ended.
public enum RecheckEnd: Equatable, Sendable {
    case done, outOfTime, cancelled
}

/// The timed re-checks behind a waiting screen: a first check after `firstDelay`, then one every
/// `interval`, one at a time, for at most `limit`. With `resetsOnChange` the limit counts from the last
/// change instead of the start. Event-driven checks (activation, Check Again) are the caller's.
public struct RecheckSchedule: Equatable, Sendable {
    public let firstDelay: Duration
    public let interval: Duration
    public let limit: Duration
    public let resetsOnChange: Bool

    public init(firstDelay: Duration, interval: Duration, limit: Duration, resetsOnChange: Bool) {
        self.firstDelay = firstDelay
        self.interval = interval
        self.limit = limit
        self.resetsOnChange = resetsOnChange
    }

    /// Waiting for PullBull to be installed on the user's own account: about 60 checks at most.
    public static let personalInstall = RecheckSchedule(
        firstDelay: .seconds(5), interval: .seconds(10), limit: .seconds(600), resetsOnChange: false)

    /// The GitHub CLI setup checklist: every 10 s until 10 minutes pass without a change.
    public static let ghSetup = RecheckSchedule(
        firstDelay: .seconds(10), interval: .seconds(10), limit: .seconds(600), resetsOnChange: true)

    /// Runs `check` on the schedule until it reports `.done`, the time runs out or the task is cancelled.
    /// `startingAfter` is time already spent (a wait resumed when its screen shows again).
    public func run(
        clock: any Clock<Duration>, startingAfter elapsed: Duration = .zero,
        isolation: isolated (any Actor)? = #isolation, check: () async -> RecheckResult
    ) async -> RecheckEnd {
        var counted = elapsed
        var wait = firstDelay
        while counted + wait <= limit {
            do { try await clock.sleep(for: wait) } catch { return .cancelled }
            if Task.isCancelled { return .cancelled }
            counted += wait
            switch await check() {
            case .done: return .done
            case .changed: if resetsOnChange { counted = .zero }
            case .unchanged: break
            }
            wait = interval
        }
        return .outOfTime
    }
}
