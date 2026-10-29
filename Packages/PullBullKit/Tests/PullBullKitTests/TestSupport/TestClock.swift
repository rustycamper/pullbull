import Foundation
import Testing

/// A manually advanced clock. `sleep` suspends until `advance(by:)` moves `now` past the deadline.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Int: Sleeper] = [:]
    private var cancelledIDs: Set<Int> = []
    private var nextID = 0
    private var requested: [Duration] = []
    private var requestWaiters: [Int: RequestWaiter] = [:]

    private struct RequestWaiter {
        let condition: @Sendable ([Duration]) -> Bool
        let continuation: CheckedContinuation<Bool, Never>
    }

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    /// Every sleep request so far, as `deadline − now` at the time of the call.
    var requestedSleeps: [Duration] { lock.withLock { requested } }
    var pendingSleepers: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = lock.withLock { () -> Int in
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let (ready, waiters) = lock.withLock { () -> (Result<Void, any Error>?, [CheckedContinuation<Bool, Never>]) in
                    if cancelledIDs.remove(id) != nil { return (.failure(CancellationError()), []) }
                    requested.append(current.duration(to: deadline))
                    let due = requestWaiters.filter { $0.value.condition(requested) }
                    for id in due.keys { requestWaiters.removeValue(forKey: id) }
                    if deadline <= current { return (.success(()), due.values.map(\.continuation)) }
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return (nil, due.values.map(\.continuation))
                }
                waiters.forEach { $0.resume(returning: true) }
                if let ready { continuation.resume(with: ready) }
            }
        } onCancel: {
            let sleeper = lock.withLock { () -> Sleeper? in
                if let sleeper = sleepers.removeValue(forKey: id) { return sleeper }
                cancelledIDs.insert(id)
                return nil
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.value.deadline <= current }
            for id in due.keys { sleepers.removeValue(forKey: id) }
            return Array(due.values)
        }
        due.forEach { $0.continuation.resume() }
    }

    /// Suspends until at least `count` sleeps have been requested, then returns all requests.
    func waitForSleeps(
        _ count: Int, timeout: Duration = testWaitLimit, sourceLocation: SourceLocation = #_sourceLocation
    ) async -> [Duration] {
        await waitForSleeps(timeout: timeout, sourceLocation: sourceLocation) { $0.count >= count }
        return requestedSleeps
    }

    /// Suspends until the sleeps requested so far satisfy `condition`, checked at each new request rather
    /// than on the wall clock. Past `timeout` (real time) it records an issue and returns false, so a
    /// sleep that never comes fails the test instead of hanging the run.
    @discardableResult
    func waitForSleeps(
        timeout: Duration = testWaitLimit, sourceLocation: SourceLocation = #_sourceLocation,
        until condition: @escaping @Sendable ([Duration]) -> Bool
    ) async -> Bool {
        let met = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let id = lock.withLock { () -> Int? in
                if condition(requested) { return nil }
                nextID += 1
                requestWaiters[nextID] = RequestWaiter(condition: condition, continuation: continuation)
                return nextID
            }
            guard let id else { return continuation.resume(returning: true) }
            Task {
                try? await Task.sleep(for: timeout)
                lock.withLock { requestWaiters.removeValue(forKey: id) }?.continuation.resume(returning: false)
            }
        }
        if !met {
            Issue.record("the expected sleeps were not requested within \(timeout)", sourceLocation: sourceLocation)
        }
        return met
    }
}
