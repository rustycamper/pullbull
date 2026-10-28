import Foundation
import PullBullKit

extension AppModel {
    /// The hover text of the status item; see `StatusTooltip`.
    func statusTooltip(now: Date) -> String {
        // No account yet, or signed out with nothing cached: nothing is counted.
        if showsFirstRun { return isSignedOut ? "Signed out of GitHub" : StatusTooltip.noAccountText }
        let prs = tabs?.badgeCount(settings.badge) ?? 0
        let issues = settings.countAssignedIssues ? issueTabs?.assigned.count ?? 0 : 0
        return StatusTooltip.text(
            parts: BadgeParts(prs: prs, issues: issues), source: settings.badge,
            countsIssues: settings.countAssignedIssues, status: status,
            staleAfter: .seconds(max(1, settings.refreshMinutes) * 60), now: now,
            issuesIncomplete: badgeIssuesIncomplete)
    }
}
