import Foundation

/// The GitHub Actions runs whose failed jobs can be re-run: finished runs with a check that failed,
/// timed out or was cancelled. External checks (no Actions run), runs still going, `ACTION_REQUIRED`
/// and `STARTUP_FAILURE` are left out.
public struct RerunPlan: Equatable, Sendable {
    /// One ID per run, in the order its first failed check appears.
    public let runIDs: [Int64]

    private static let rerunnable: Set<String> = ["FAILURE", "TIMED_OUT", "CANCELLED"]

    public init(checks: [Check]) {
        var seen = Set<Int64>()
        var ids: [Int64] = []
        for check in checks {
            guard check.suiteStatus == "COMPLETED", let conclusion = check.conclusion,
                  Self.rerunnable.contains(conclusion),
                  let id = Self.runID(from: check.url),
                  seen.insert(id).inserted
            else { continue }
            ids.append(id)
        }
        runIDs = ids
    }

    public var isEmpty: Bool { runIDs.isEmpty }

    /// The run ID in an Actions details URL (`/actions/runs/{id}/job/{job}`); nil for any other URL.
    public static func runID(from detailsURL: URL?) -> Int64? {
        guard let parts = detailsURL?.pathComponents,
              let index = zip(parts, parts.dropFirst()).enumerated()
                  .first(where: { $0.element == ("actions", "runs") })?.offset,
              parts.indices.contains(index + 2)
        else { return nil }
        return Int64(parts[index + 2])
    }
}
