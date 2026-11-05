import Foundation
import PullBullKit
import SwiftUI

// MARK: - Re-running failed jobs

extension AppModel {
    /// A plan is worked out for a detail on an open PR whose checks failed. The detail holds 50 checks, so a
    /// bigger PR pages all of them in, unless the viewer can't write.
    func planRerun(for detail: PRDetail, account: AccountRef) {
        let key = detail.key
        rerunPlanLoads[key] = nil
        guard detail.state == .open, detail.ci == .failure else {
            rerunPlans[key] = nil
            return
        }
        guard detail.checksTruncated else {
            rerunPlans[key] = RerunPlan(key: key, checks: detail.checks)
            return
        }
        guard detail.merge?.canWrite != false else {
            rerunPlans[key] = nil
            return
        }
        let client = api(for: account)
        let head = detail.headOid
        rerunPlanLoads[key] = Task { [weak self] in
            guard let checks = try? await client.allChecks(key) else { return }
            guard let self, self.runningAccount == account, self.details[key]?.headOid == head,
                  self.details[key]?.ci == .failure
            else { return }
            self.rerunPlans[key] = RerunPlan(key: key, checks: checks)
        }
    }

    /// Re-plans a detail just stored when its PR is on screen; any other PR's plan goes.
    func keepRerunPlan(in key: PRKey) {
        guard route == .detail(key), let detail = details[key], let account = runningAccount else {
            rerunPlans[key] = nil
            rerunPlanLoads[key] = nil
            return
        }
        planRerun(for: detail, account: account)
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
              detail.ci == .failure,
              detail.merge?.canWrite != false,
              edits.overrides.apply(toState: detail.state, on: key) == .open
        else { return false }
        return true
    }

    /// Reads every check afresh, so a run restarted since the plan was made isn't sent, re-runs each
    /// failed run, then reads the detail until those runs show as restarted. Runs refused don't stop the
    /// rest. If GitHub is slower than the reads, the button returns and a second press is safe.
    func rerunFailedJobs(on key: PRKey) {
        guard isRerunOffered(for: key), !rerunning.contains(key), let account = runningAccount else { return }
        edits.dismissFailure(startingOn: key)
        rerunning.insert(key)
        AccessibilityNotification.Announcement("Re-running failed jobs").post()
        let client = api(for: account)
        Task { [weak self] in
            var line: String?
            var sent = Set<Int64>()
            do {
                let plan = RerunPlan(key: key, checks: try await client.allChecks(key))
                var refusals: [String] = []
                for id in plan.runIDs {
                    do {
                        try await client.rerunFailedJobs(key, runID: id)
                        sent.insert(id)
                    } catch {
                        refusals.append(MergeFlow.reason(for: error))
                    }
                }
                line = RerunFlow.line(refusals: refusals, of: plan.runIDs.count, on: key)
            } catch {
                line = EditMessage.rerunRefused(on: key, reason: MergeFlow.reason(for: error))
            }
            guard let self else { return }
            await RerunFlow.settle(
                sent: sent,
                read: { try await self.readRerunDetail(key, account: account, client: client) },
                sleep: { try await Task.sleep(for: $0) })
            self.rerunDone(key, account: account, line: line)
        }
    }

    /// One read of the detail after the sends, kept as any detail is, with the runs it still offers; nil
    /// once the viewer left the PR or the account changed. A paged plan is waited for, so "Re-running…"
    /// doesn't go before it lands.
    private func readRerunDetail(_ key: PRKey, account: AccountRef, client: GitHubAPI) async throws -> Set<Int64>? {
        guard runningAccount == account, route == .detail(key) else { return nil }
        let fresh = try await client.detail(key)
        guard runningAccount == account, route == .detail(key) else { return nil }
        storeDetail(fresh, account: account)
        await rerunPlanLoads[key]?.value
        return Set(rerunPlans[key]?.runIDs ?? [])
    }

    /// Nothing changes on screen if the account changed meanwhile.
    private func rerunDone(_ key: PRKey, account: AccountRef, line: String?) {
        guard runningAccount == account else { return }
        rerunning.remove(key)
        if let line {
            let url = fetchedPullRequest(for: key)?.url ?? GitHubLinks.pullRequest(key)
            edits.showFailure(EditFailure(text: line, url: url, key: key))
        }
    }
}
