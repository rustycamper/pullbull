import Foundation

/// What an edit changes on GitHub. `comment` posts a comment rather than changing a field, and gates
/// like the item's other edits.
public enum EditField: Sendable {
    case status, labels, assignees, reviewers, comment
}

/// Whether the current account may make an edit, and if not, what it needs.
public enum EditPermission: Equatable, Sendable {
    case ready
    /// The GitHub App's installation on `owner` still has its old, read-only permissions; someone
    /// accepts the new ones at `url`.
    case needsAppApproval(owner: String, isOrganization: Bool, url: URL?)
    /// The `gh` login lacks the `project` scope; `command` adds it.
    case needsGhScope(command: String)
    /// This account can't make the edit at all (no installation, or a GitHub App on a personal board).
    case unavailable

    /// `installation` is the GitHub App's installation on the item's owner, for an app account;
    /// `onPullRequest` says the item is a pull request, whose edits need the Pull requests permission.
    public static func of(
        _ field: EditField, account: AccountRef, boardOwner: BoardOwner?, installation: Installation?,
        ghAccounts: [GhAccount], onPullRequest: Bool = false
    ) -> EditPermission {
        switch account.source {
        case .gh:
            guard field == .status, !ghAccounts.canWriteProjects(for: account.login) else { return .ready }
            let active = ghAccounts.first(where: \.active)?.login
            return .needsGhScope(command: GhCommands.addProjectScope(
                login: account.login, activeLogin: active, scope: "project"))
        case .gitHubApp:
            guard let installation else { return .unavailable }
            // GitHub gives apps no permission for user-owned boards.
            if field == .status, boardOwner?.isUser == true { return .unavailable }
            let canWrite = field == .status ? installation.canWriteProjects
                : onPullRequest || field == .reviewers ? installation.canWritePullRequests
                : installation.canWriteIssues
            if canWrite { return .ready }
            return .needsAppApproval(
                owner: installation.org, isOrganization: installation.isOrganization,
                url: AccessChecker.permissionsReviewURL(for: installation))
        }
    }

    /// The one line shown in place of the picker; nil when there's nothing to say.
    public var note: String? { note(doing: "Editing") }

    /// The one line shown in place of the picker or the comment field for `field`; nil when there's
    /// nothing to say.
    public func note(for field: EditField) -> String? {
        note(doing: field == .comment ? "Commenting" : "Editing")
    }

    private func note(doing: String) -> String? {
        switch self {
        case .ready, .unavailable:
            nil
        case .needsAppApproval(let owner, let isOrganization, _):
            isOrganization
                ? "\(doing) needs PullBull's new permissions for \(owner). An org owner accepts them on GitHub."
                : "\(doing) needs PullBull's new permissions. Accept them on GitHub."
        case .needsGhScope(let command):
            "Setting Status needs the project scope. Run: \(command)"
        }
    }
}
