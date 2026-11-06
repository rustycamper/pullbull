import Foundation

/// The GitHub Actions runs whose failed jobs can be re-run: finished runs with a check that failed,
/// timed out or was cancelled. External checks (no Actions run), runs still going, `ACTION_REQUIRED`
/// and `STARTUP_FAILURE` are left out.
public struct RerunPlan: Equatable, Sendable {
    /// One ID per run, in the order its first failed check appears.
    public let runIDs: [Int64]

    private static let rerunnable: Set<String> = ["FAILURE", "TIMED_OUT", "CANCELLED"]

    public init(key: PRKey, checks: [Check]) {
        var seen = Set<Int64>()
        var ids: [Int64] = []
        for check in checks {
            guard check.suiteStatus == "COMPLETED", let conclusion = check.conclusion,
                  Self.rerunnable.contains(conclusion),
                  let id = Self.runID(from: check.url, in: key),
                  seen.insert(id).inserted
            else { continue }
            ids.append(id)
        }
        runIDs = ids
    }

    public var isEmpty: Bool { runIDs.isEmpty }

    /// The run ID in a details URL of this repository's own Actions runs
    /// (`https://github.com/{owner}/{repo}/actions/runs/{id}/job/{job}`); nil for any other URL, including
    /// another repository's runs and other hosts. Host and repository compare without case.
    public static func runID(from detailsURL: URL?, in key: PRKey) -> Int64? {
        guard let url = detailsURL, url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com"
        else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        let own = key.repo.split(separator: "/").map(String.init)
        guard own.count == 2, parts.count >= 5,
              parts[0].lowercased() == own[0].lowercased(), parts[1].lowercased() == own[1].lowercased(),
              parts[2] == "actions", parts[3] == "runs"
        else { return nil }
        return Int64(parts[4])
    }
}
