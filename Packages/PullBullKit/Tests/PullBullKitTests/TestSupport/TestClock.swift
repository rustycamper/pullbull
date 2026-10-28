import Foundation

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
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

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
                let (ready, waiters) = lock.withLock { () -> (Result<Void, any Error>?, [CheckedContinuation<Void, Never>]) in
                    if cancelledIDs.remove(id) != nil { return (.failure(CancellationError()), []) }
                    requested.append(current.duration(to: deadline))
                    let due = requestWaiters.filter { $0.count <= requested.count }.map(\.continuation)
                    requestWaiters.removeAll { $0.count <= requested.count }
                    if deadline <= current { return (.success(()), due) }
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return (nil, due)
                }
                waiters.forEach { $0.resume() }
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
    func waitForSleeps(_ count: Int) async -> [Duration] {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> Bool in
                if requested.count >= count { return true }
                requestWaiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
        return requestedSleeps
    }
}
