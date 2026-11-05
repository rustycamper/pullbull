import Foundation

public enum MergeMethod: String, CaseIterable, Codable, Sendable { case merge = "MERGE", squash = "SQUASH", rebase = "REBASE" }

public enum MergeStatus: String, Codable, Sendable {
    case clean, unstable, hasHooks, blocked, behind, dirty, unknown

    init(github raw: String?) {
        switch raw {
        case "CLEAN": self = .clean
        case "UNSTABLE": self = .unstable
        case "HAS_HOOKS": self = .hasHooks
        case "BLOCKED": self = .blocked
        case "BEHIND": self = .behind
        case "DIRTY": self = .dirty
        default: self = .unknown
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MergeStatus(rawValue: raw) ?? .unknown
    }
}

public struct AutoMerge: Codable, Equatable, Sendable {
    public let enabledBy: String?

    public init(enabledBy: String?) { self.enabledBy = enabledBy }
}

public struct CheckTally: Codable, Equatable, Sendable {
    public let failing, running, total: Int

    public init(failing: Int, running: Int, total: Int) {
        self.failing = failing
        self.running = running
        self.total = total
    }

    /// Counts every state of the head commit's check runs and status contexts. A state not listed
    /// here counts as running, so nothing unknown reads as passing.
    init(runs: [(state: String, count: Int)], statuses: [(state: String, count: Int)]) {
        var failing = 0, running = 0, total = 0
        for (state, count) in runs {
            total += count
            switch state {
            case "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE": failing += count
            case "SUCCESS", "NEUTRAL", "SKIPPED", "COMPLETED": break
            default: running += count
            }
        }
        for (state, count) in statuses {
            total += count
            switch state {
            case "FAILURE", "ERROR": failing += count
            case "SUCCESS": break
            default: running += count
            }
        }
        self.init(failing: failing, running: running, total: total)
    }
}

public struct MergeInfo: Codable, Equatable, Sendable {
    public let nodeID: String
    public let status: MergeStatus
    public let hasConflicts: Bool
    public let usesMergeQueue: Bool
    public let isStacked: Bool
    public let isDraft: Bool
    public let autoMerge: AutoMerge?
    public let canEnableAutoMerge: Bool
    public let canDisableAutoMerge: Bool
    public let canWrite: Bool?
    public let allowedMethods: [MergeMethod]
    public let defaultMethod: MergeMethod?
    public let base: String
    public let commitCount: Int
    public let approvals: Int
    public let tally: CheckTally
    public let changesRequested: Bool

    public init(
        nodeID: String, status: MergeStatus, hasConflicts: Bool, usesMergeQueue: Bool, isStacked: Bool,
        isDraft: Bool, autoMerge: AutoMerge?, canEnableAutoMerge: Bool, canDisableAutoMerge: Bool,
        canWrite: Bool?, allowedMethods: [MergeMethod], defaultMethod: MergeMethod?, base: String,
        commitCount: Int, approvals: Int, tally: CheckTally, changesRequested: Bool
    ) {
        self.nodeID = nodeID
        self.status = status
        self.hasConflicts = hasConflicts
        self.usesMergeQueue = usesMergeQueue
        self.isStacked = isStacked
        self.isDraft = isDraft
        self.autoMerge = autoMerge
        self.canEnableAutoMerge = canEnableAutoMerge
        self.canDisableAutoMerge = canDisableAutoMerge
        self.canWrite = canWrite
        self.allowedMethods = allowedMethods
        self.defaultMethod = defaultMethod
        self.base = base
        self.commitCount = commitCount
        self.approvals = approvals
        self.tally = tally
        self.changesRequested = changesRequested
    }

    /// The merge state from the detail query's `pullRequest` and its `repository`; nil when GitHub
    /// returned no node id or base branch.
    static func read(pullRequest pr: [String: Any], repository repo: [String: Any]) -> MergeInfo? {
        guard let nodeID = pr["id"] as? String, let base = pr["baseRefName"] as? String else { return nil }

        let commit = ((pr["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["commit"] as? [String: Any]
        let contexts = (commit?["statusCheckRollup"] as? [String: Any])?["contexts"] as? [String: Any]
        func pairs(_ field: String) -> [(state: String, count: Int)] {
            (contexts?[field] as? [[String: Any]] ?? []).compactMap { entry in
                guard let state = entry["state"] as? String, let count = entry["count"] as? Int else { return nil }
                return (state, count)
            }
        }

        let reviewStates = ((pr["latestReviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            .compactMap { $0["state"] as? String }

        let permission: Bool? = switch repo["viewerPermission"] as? String {
        case "WRITE", "MAINTAIN", "ADMIN": true
        case "READ", "TRIAGE": false
        default: nil
        }

        return MergeInfo(
            nodeID: nodeID,
            status: MergeStatus(github: pr["mergeStateStatus"] as? String),
            hasConflicts: pr["mergeable"] as? String == "CONFLICTING",
            usesMergeQueue: pr["isMergeQueueEnabled"] as? Bool ?? false,
            isStacked: ((pr["stack"] as? [String: Any])?["size"] as? Int ?? 0) > 1,
            isDraft: pr["isDraft"] as? Bool ?? false,
            autoMerge: (pr["autoMergeRequest"] as? [String: Any]).map {
                AutoMerge(enabledBy: ($0["enabledBy"] as? [String: Any])?["login"] as? String)
            },
            canEnableAutoMerge: pr["viewerCanEnableAutoMerge"] as? Bool ?? false,
            canDisableAutoMerge: pr["viewerCanDisableAutoMerge"] as? Bool ?? false,
            canWrite: permission,
            allowedMethods: allowedMethods(pullRequest: pr, repository: repo),
            defaultMethod: (repo["viewerDefaultMergeMethod"] as? String).flatMap(MergeMethod.init(rawValue:)),
            base: base,
            commitCount: (pr["commitTotal"] as? [String: Any])?["totalCount"] as? Int ?? 0,
            approvals: reviewStates.filter { $0 == "APPROVED" }.count,
            tally: CheckTally(runs: pairs("checkRunCountsByState"), statuses: pairs("statusContextCountsByState")),
            changesRequested: reviewStates.contains("CHANGES_REQUESTED"))
    }

    /// What the repository allows, narrowed by the base branch's rules and by `canBeRebased`, in
    /// `MergeMethod.allCases` order. A rules read that is missing narrows nothing.
    private static func allowedMethods(pullRequest pr: [String: Any], repository repo: [String: Any]) -> [MergeMethod] {
        var allowed = Set<MergeMethod>()
        if repo["mergeCommitAllowed"] as? Bool == true { allowed.insert(.merge) }
        if repo["squashMergeAllowed"] as? Bool == true { allowed.insert(.squash) }
        if repo["rebaseMergeAllowed"] as? Bool == true { allowed.insert(.rebase) }

        let rules = ((pr["baseRef"] as? [String: Any])?["rules"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        for rule in rules {
            switch rule["type"] as? String {
            case "PULL_REQUEST":
                guard let listed = (rule["parameters"] as? [String: Any])?["allowedMergeMethods"] as? [String] else { continue }
                allowed.formIntersection(listed.compactMap(MergeMethod.init(rawValue:)))
            case "REQUIRED_LINEAR_HISTORY":
                allowed.remove(.merge)
            default:
                continue
            }
        }
        if pr["canBeRebased"] as? Bool != true { allowed.remove(.rebase) }
        return MergeMethod.allCases.filter(allowed.contains)
    }
}
