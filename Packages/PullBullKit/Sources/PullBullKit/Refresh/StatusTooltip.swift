import Foundation

/// The two parts of the menu bar number: PRs for the badge setting, and Assigned issues. `issues` is
/// zero unless "Also count assigned issues" is on.
public struct BadgeParts: Equatable, Sendable {
    public var prs: Int
    public var issues: Int

    public init(prs: Int, issues: Int) {
        self.prs = prs
        self.issues = issues
    }
}

/// The hover text of the menu bar item: one short line saying what the number counts and how fresh it is.
public enum StatusTooltip {
    /// No account yet: the popover is where to sign in, not a terminal.
    public static let noAccountText = "No GitHub account. Open PullBull to sign in."
    public static let noAccount = RefreshError.other(noAccountText)

    public static func text(parts: BadgeParts, source: BadgeSource, countsIssues: Bool, status: RefreshStatus,
                            staleAfter: Duration, now: Date, issuesIncomplete: Bool = false) -> String {
        let age = status.lastSuccess.map { ago($0, now: now) }
        if let error = status.error {
            switch error {
            case .offline: return age.map { "Offline · \($0)" } ?? "Offline"
            case .notLoggedIn, .unauthorized: return "Not signed in"
            case _ where error == noAccount: return noAccountText
            default: return error.message
            }
        }
        guard let age else { return status.isRefreshing ? "Refreshing…" : "Not updated yet" }
        let count = countText(parts: parts, source: source, countsIssues: countsIssues)
        if status.isRefreshing { return "\(count) · refreshing…" }
        if status.isStale(now: now, interval: staleAfter) { return "\(count) · stale, \(age)" }
        // The dimmed icon's other cause: the Assigned count is the last known one.
        if issuesIncomplete { return "\(count) · issues didn't update" }
        return "\(count) · \(age)"
    }

    static func countText(parts: BadgeParts, source: BadgeSource, countsIssues: Bool) -> String {
        let withIssues = countsIssues && parts.issues > 0
        let total = parts.prs + (countsIssues ? parts.issues : 0)
        let combined: String? = switch source {
        case .review, .mine: nil
        case .reviewAndMine: "review + mine"
        case .all: "review + mine + team"
        }
        if let combined {
            return "\(total): \(combined)" + (countsIssues ? " + issues" : "")
        }
        let prPart: String
        switch source {
        case .mine:
            prPart = parts.prs == 0 && !withIssues ? "No PRs of yours"
                : "\(parts.prs) \(parts.prs == 1 ? "PR" : "PRs") of yours"
        default:
            prPart = parts.prs == 0 && !withIssues ? "Nothing to review" : "\(parts.prs) to review"
        }
        guard withIssues else { return prPart }
        return "\(prPart), \(parts.issues) \(parts.issues == 1 ? "issue" : "issues")"
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
