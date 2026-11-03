import Foundation

private func shortRepo(_ repo: String) -> String {
    repo.split(separator: "/").last.map(String.init) ?? repo
}

extension PREvent {
    /// `<repo> #<n> · <event>`: the banner is readable at a glance, whatever the body truncates to.
    public var notificationTitle: String {
        "\(shortRepo(pr.key.repo)) #\(pr.key.number) · \(eventName)"
    }

    /// Who did it. CI has no actor: its subtitle names what failed (`ciSubtitle`), once the checks are known.
    public var notificationSubtitle: String? {
        switch kind {
        case .ciFailed: nil
        default: actor.map { "by \($0)" }
        }
    }

    /// The failing checks by name: one is named, several are counted. With none failed, the cancelled ones,
    /// which GitHub's rollup counts as failures. Nil when neither is known.
    public static func ciSubtitle(_ checks: [Check]) -> String? {
        for (state, word) in [(CIState.failure, "failed"), (.cancelled, "cancelled")] {
            let names = checks.filter { $0.state == state }.map(\.name)
            switch names.count {
            case 0: continue
            case 1: return "\(names[0]) \(word)"
            default: return "\(names.count) checks \(word)"
            }
        }
        return nil
    }

    /// The PR title.
    public var notificationBody: String { pr.title }

    private var eventName: String {
        switch kind {
        case .reviewRequested: "Review requested"
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .ciFailed: "CI failed"
        case .newComment: "New comment"
        case .readyToMerge: "Ready to merge"
        case .merged: "Merged"
        case .commentAfterMyReview: "New comment since your review"
        case .reviewDismissed: "Your review was dismissed"
        }
    }
}

extension IssueEvent {
    public var notificationTitle: String {
        "\(shortRepo(issue.key.repo)) #\(issue.key.number) · \(eventName)"
    }

    public var notificationSubtitle: String? {
        actor.map { "by \($0)" }
    }

    /// The issue title.
    public var notificationBody: String { issue.title }

    private var eventName: String {
        switch kind {
        case .assigned: "Assigned to you"
        case .comment: count == 1 ? "New comment" : "\(count) new comments"
        case .statusChanged: "\(move?.from ?? "No Status") → \(move?.to ?? "No Status")"
        case .closed:
            switch issue.stateReason {
            case .notPlanned: "Closed as not planned"
            case .duplicate: "Closed as duplicate"
            default: "Closed"
            }
        case .reopened: "Reopened"
        }
    }
}
