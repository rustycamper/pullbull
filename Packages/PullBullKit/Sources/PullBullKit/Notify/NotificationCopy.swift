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

    /// The failing checks by name: one is named, several are counted. Nil when none are known.
    public static func ciSubtitle(_ checks: [Check]) -> String? {
        let failed = checks.filter { $0.state == .failure }.map(\.name)
        switch failed.count {
        case 0: return nil
        case 1: return "\(failed[0]) failed"
        default: return "\(failed.count) checks failed"
        }
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
        }
    }
}
