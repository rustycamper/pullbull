import Foundation

/// What an edit changes on GitHub.
public enum EditField: Sendable {
    case status, labels, assignees
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

    /// `installation` is the GitHub App's installation on the item's owner, for an app account.
    public static func of(
        _ field: EditField, account: AccountRef, boardOwner: BoardOwner?, installation: Installation?,
        ghAccounts: [GhAccount]
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
            let canWrite = field == .status ? installation.canWriteProjects : installation.canWriteIssues
            if canWrite { return .ready }
            return .needsAppApproval(
                owner: installation.org, isOrganization: installation.isOrganization,
                url: AccessChecker.permissionsReviewURL(for: installation))
        }
    }

    /// The one line shown in place of the picker; nil when there's nothing to say.
    public var note: String? {
        switch self {
        case .ready, .unavailable:
            nil
        case .needsAppApproval(let owner, let isOrganization, _):
            isOrganization
                ? "Editing needs PullBull's new permissions for \(owner). An org owner accepts them on GitHub."
                : "Editing needs PullBull's new permissions. Accept them on GitHub."
        case .needsGhScope(let command):
            "Setting Status needs the project scope. Run: \(command)"
        }
    }
}
