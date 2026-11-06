import Foundation

/// What follows a re-run's sends: reads of the detail until the runs show as restarted, and the line for
/// any run GitHub refused.
public enum RerunFlow {
    public static let reads = 3
    public static let readGap: Duration = .seconds(2)

    /// Reads up to `reads` times, `readGap` apart, and stops as soon as none of `sent` is among the runs
    /// `read` says are still offered. `read` returns nil to stop (the viewer left); a read that throws
    /// counts as one of the reads. Nothing is sent, so nothing is read; a throwing `sleep` ends it.
    @MainActor
    public static func settle(
        sent: Set<Int64>,
        read: @MainActor () async throws -> Set<Int64>?,
        sleep: @MainActor (Duration) async throws -> Void
    ) async {
        guard !sent.isEmpty else { return }
        for attempt in 0..<reads {
            if attempt > 0 {
                do { try await sleep(readGap) } catch { return }
            }
            do {
                guard let offered = try await read() else { return }
                if sent.isDisjoint(with: offered) { return }
            } catch {
                continue
            }
        }
    }

    /// The line for `refusals` among `total` runs sent: the first reason when every run was refused, the
    /// count when only some were, nil when none was.
    public static func line(refusals: [String], of total: Int, on key: PRKey) -> String? {
        guard let first = refusals.first else { return nil }
        return refusals.count == total
            ? EditMessage.rerunRefused(on: key, reason: first)
            : EditMessage.rerunPartlyRefused(refused: refusals.count, of: total, on: key)
    }
}
