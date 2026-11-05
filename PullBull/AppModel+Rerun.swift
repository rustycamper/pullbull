import Foundation
import PullBullKit
import SwiftUI

// MARK: - Re-running failed jobs

extension AppModel {
    /// A plan is worked out for a detail on an open PR whose checks failed. The detail holds 50 checks, so a
    /// bigger PR pages all of them in.
    func planRerun(for detail: PRDetail, account: AccountRef) {
        let key = detail.key
        guard detail.state == .open, detail.ci == .failure else {
            rerunPlans[key] = nil
            return
        }
        guard detail.checksTruncated else {
            rerunPlans[key] = RerunPlan(checks: detail.checks)
            return
        }
        let client = api(for: account)
        let head = detail.headOid
        Task { [weak self] in
            guard let checks = try? await client.allChecks(key) else { return }
            guard let self, self.runningAccount == account, self.details[key]?.headOid == head else { return }
            self.rerunPlans[key] = RerunPlan(checks: checks)
        }
    }

    /// Whether the detail shows **Re-run failed jobs**: a failed run to re-run on an open PR the viewer can
    /// write to, and the permission to do it.
    func isRerunOffered(for key: PRKey) -> Bool {
        isRerunCandidate(key) && setEditPermission(.rerun, for: key) == .ready
    }

    /// The permission to show in the button's place, when the button would show but for it.
    func rerunNote(for key: PRKey) -> EditPermission? {
        guard isRerunCandidate(key) else { return nil }
        let permission = setEditPermission(.rerun, for: key)
        return permission == .ready ? nil : permission
    }

    private func isRerunCandidate(_ key: PRKey) -> Bool {
        guard editPermissionsKnown, let plan = rerunPlans[key], !plan.isEmpty, let detail = details[key],
              detail.merge?.canWrite != false,
              edits.overrides.apply(toState: detail.state, on: key) == .open
        else { return false }
        return true
    }

    /// Reads every check afresh, so a run restarted since the plan was made isn't sent, re-runs each
    /// failed run, and reads the detail again. Runs refused don't stop the rest.
    func rerunFailedJobs(on key: PRKey) {
        guard isRerunOffered(for: key), !rerunning.contains(key), let account = runningAccount else { return }
        edits.dismissFailure(startingOn: key)
        rerunning.insert(key)
        AccessibilityNotification.Announcement("Re-running failed jobs").post()
        let client = api(for: account)
        Task { [weak self] in
            var line: String?
            do {
                let plan = RerunPlan(checks: try await client.allChecks(key))
                var refusals: [String] = []
                for id in plan.runIDs {
                    do {
                        try await client.rerunFailedJobs(key, runID: id)
                    } catch {
                        refusals.append(MergeFlow.reason(for: error))
                    }
                }
                if let first = refusals.first {
                    line = refusals.count == plan.runIDs.count
                        ? EditMessage.rerunRefused(on: key, reason: first)
                        : EditMessage.rerunPartlyRefused(refused: refusals.count, of: plan.runIDs.count)
                }
            } catch {
                line = EditMessage.rerunRefused(on: key, reason: MergeFlow.reason(for: error))
            }
            let fresh = try? await client.detail(key)
            self?.rerunAnswered(key, account: account, line: line, fresh: fresh)
        }
    }

    /// Nothing changes on screen if the account changed meanwhile.
    private func rerunAnswered(_ key: PRKey, account: AccountRef, line: String?, fresh: PRDetail?) {
        guard runningAccount == account else { return }
        rerunning.remove(key)
        if let fresh { storeDetail(fresh, account: account) }
        if let line {
            let url = fetchedPullRequest(for: key)?.url ?? GitHubLinks.pullRequest(key)
            edits.showFailure(EditFailure(text: line, url: url, key: key))
        }
    }
}
