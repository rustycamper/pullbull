import Foundation
import Testing
@testable import PullBullKit

private func counts(_ pairs: [(String, Int)]) -> [[String: Any]] {
    pairs.map { ["state": $0.0, "count": $0.1] }
}

private func pullRequest(
    status: Any = "CLEAN", mergeable: String = "MERGEABLE", rules: Any? = [[String: Any]](),
    canBeRebased: Bool = true, runs: [(String, Int)] = [("SUCCESS", 3)], statuses: [(String, Int)] = [],
    reviews: [String] = [], extra: [String: Any] = [:]
) -> [String: Any] {
    var pr: [String: Any] = [
        "id": "PR_node", "isDraft": false, "mergeable": mergeable, "mergeStateStatus": status,
        "isMergeQueueEnabled": false, "baseRefName": "main", "canBeRebased": canBeRebased,
        "viewerCanEnableAutoMerge": true, "viewerCanDisableAutoMerge": false,
        "stack": NSNull(), "autoMergeRequest": NSNull(), "commitTotal": ["totalCount": 4],
        "latestReviews": ["nodes": reviews.map { ["state": $0] }],
        "commits": ["nodes": [["commit": ["statusCheckRollup": ["state": "SUCCESS", "contexts": [
            "checkRunCountsByState": counts(runs), "statusContextCountsByState": counts(statuses)]]]]]],
        "baseRef": rules.map { ["rules": ["nodes": $0]] } ?? NSNull(),
    ]
    for (field, value) in extra { pr[field] = value }
    return pr
}

private func repository(
    permission: Any = "WRITE", merge: Bool = true, squash: Bool = true, rebase: Bool = true,
    defaultMethod: Any = "SQUASH"
) -> [String: Any] {
    [
        "viewerPermission": permission, "mergeCommitAllowed": merge, "squashMergeAllowed": squash,
        "rebaseMergeAllowed": rebase, "viewerDefaultMergeMethod": defaultMethod,
    ]
}

private func rule(_ type: String, methods: [String]? = nil) -> [String: Any] {
    ["type": type, "parameters": methods.map { ["allowedMergeMethods": $0] } ?? NSNull()]
}

private func read(_ pr: [String: Any], _ repo: [String: Any] = repository()) throws -> MergeInfo {
    try #require(MergeInfo.read(pullRequest: pr, repository: repo))
}

@Suite struct MergeInfoTests {
    @Test func decodesEveryStatus() throws {
        let expected: [(String, MergeStatus)] = [
            ("CLEAN", .clean), ("UNSTABLE", .unstable), ("HAS_HOOKS", .hasHooks), ("BLOCKED", .blocked),
            ("BEHIND", .behind), ("DIRTY", .dirty), ("UNKNOWN", .unknown), ("DRAFT", .unknown),
            ("SOMETHING_NEW", .unknown),
        ]
        for (raw, status) in expected { #expect(try read(pullRequest(status: raw)).status == status) }
        #expect(try read(pullRequest(status: NSNull())).status == .unknown)
    }

    @Test func oldCachedDetailHasNoMergeInfo() throws {
        let json = #"{"key":{"repo":"o/r","number":7},"body":"b","checks":[],"reviews":[],"comments":[],"files":[]}"#
        let decoded = try JSONDecoder().decode(PRDetail.self, from: Data(json.utf8))
        #expect(decoded.merge == nil)
    }

    @Test func readsTheFlagsAndCounts() throws {
        let info = try read(pullRequest(
            mergeable: "CONFLICTING",
            extra: [
                "isDraft": true, "isMergeQueueEnabled": true, "viewerCanDisableAutoMerge": true,
                "stack": ["size": 3], "autoMergeRequest": ["enabledBy": ["login": "alice"]],
            ]), repository(permission: "ADMIN"))
        #expect(info.nodeID == "PR_node")
        #expect(info.hasConflicts)
        #expect(info.isDraft && info.usesMergeQueue && info.isStacked)
        #expect(info.canEnableAutoMerge && info.canDisableAutoMerge)
        #expect(info.autoMerge == AutoMerge(enabledBy: "alice"))
        #expect(info.base == "main")
        #expect(info.commitCount == 4)
        #expect(info.defaultMethod == .squash)
        #expect(info.canWrite == true)
    }

    @Test func methodsNarrowToTheBranchRules() throws {
        let allowed = try read(pullRequest(rules: [rule("PULL_REQUEST", methods: ["SQUASH"])]))
        #expect(allowed.allowedMethods == [.squash])
        let intersected = try read(pullRequest(rules: [
            rule("PULL_REQUEST", methods: ["MERGE", "SQUASH"]), rule("PULL_REQUEST", methods: ["SQUASH", "REBASE"]),
        ]))
        #expect(intersected.allowedMethods == [.squash])
        let repoOnly = try read(pullRequest(), repository(merge: true, squash: false, rebase: true))
        #expect(repoOnly.allowedMethods == [.merge, .rebase])
        let ordered = try read(pullRequest(rules: [rule("PULL_REQUEST", methods: ["REBASE", "MERGE"])]))
        #expect(ordered.allowedMethods == [.merge, .rebase])
    }

    @Test func linearHistoryDropsMergeCommits() throws {
        let info = try read(pullRequest(rules: [rule("REQUIRED_LINEAR_HISTORY")]))
        #expect(info.allowedMethods == [.squash, .rebase])
    }

    @Test func rebaseNeedsCanBeRebased() throws {
        let info = try read(pullRequest(canBeRebased: false))
        #expect(info.allowedMethods == [.merge, .squash])
    }

    @Test func tallyComesFromTheCountsNotTheFirstFifty() throws {
        let info = try read(pullRequest(runs: [("SUCCESS", 100), ("FAILURE", 2), ("IN_PROGRESS", 5)], statuses: [("SUCCESS", 20)]))
        #expect(info.tally == CheckTally(failing: 2, running: 5, total: 127))
    }

    @Test func tallyCountsStatusContextsToo() throws {
        let info = try read(pullRequest(runs: [("SUCCESS", 2)], statuses: [("FAILURE", 1)]))
        #expect(info.tally == CheckTally(failing: 1, running: 0, total: 3))
    }

    @Test func noRulesReadLeavesTheRepoMethods() throws {
        let info = try read(pullRequest(rules: nil))
        #expect(info.allowedMethods == [.merge, .squash, .rebase])
    }

    @Test func changesRequestedReadsTheLatestReviews() throws {
        let blocked = try read(pullRequest(reviews: ["APPROVED", "CHANGES_REQUESTED", "APPROVED", "COMMENTED"]))
        #expect(blocked.changesRequested)
        #expect(blocked.approvals == 2)
        let clear = try read(pullRequest(reviews: ["APPROVED"]))
        #expect(!clear.changesRequested)
        #expect(clear.approvals == 1)
    }

    @Test func unknownPermissionDecodesToNil() throws {
        #expect(try read(pullRequest(), repository(permission: NSNull())).canWrite == nil)
        #expect(try read(pullRequest(), repository(permission: "MODERATE")).canWrite == nil)
        #expect(try read(pullRequest(), repository(permission: "READ")).canWrite == false)
        #expect(try read(pullRequest(), repository(permission: "TRIAGE")).canWrite == false)
        for granted in ["WRITE", "MAINTAIN", "ADMIN"] {
            #expect(try read(pullRequest(), repository(permission: granted)).canWrite == true)
        }
    }

    @Test func tallyMapsEveryState() {
        let failingRuns = ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"]
        let passingRuns = ["SUCCESS", "NEUTRAL", "SKIPPED", "COMPLETED"]
        let runningRuns = ["QUEUED", "IN_PROGRESS", "PENDING", "WAITING"]
        for state in failingRuns { #expect(CheckTally(runs: [(state, 1)], statuses: []) == CheckTally(failing: 1, running: 0, total: 1)) }
        for state in passingRuns { #expect(CheckTally(runs: [(state, 1)], statuses: []) == CheckTally(failing: 0, running: 0, total: 1)) }
        for state in runningRuns { #expect(CheckTally(runs: [(state, 1)], statuses: []) == CheckTally(failing: 0, running: 1, total: 1)) }
        for state in ["FAILURE", "ERROR"] { #expect(CheckTally(runs: [], statuses: [(state, 1)]) == CheckTally(failing: 1, running: 0, total: 1)) }
        #expect(CheckTally(runs: [], statuses: [("SUCCESS", 1)]) == CheckTally(failing: 0, running: 0, total: 1))
        for state in ["PENDING", "EXPECTED"] { #expect(CheckTally(runs: [], statuses: [(state, 1)]) == CheckTally(failing: 0, running: 1, total: 1)) }
    }

    @Test func anUnrecognisedStateCountsAsRunning() {
        #expect(CheckTally(runs: [("BRAND_NEW", 2)], statuses: [("ODD", 1)]) == CheckTally(failing: 0, running: 3, total: 3))
    }
}
