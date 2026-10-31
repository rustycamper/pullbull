import Foundation
import Testing
@testable import PullBullKit

private let app = AccountRef(login: "me", source: .gitHubApp)
private let ghMe = AccountRef(login: "me", source: .gh)

private func install(
    _ permissions: [String: String], org: String = "acme", isOrganization: Bool = true, id: Int64? = 9
) -> Installation {
    Installation(id: id, org: org, allRepositories: true, permissions: permissions, isOrganization: isOrganization)
}

@Suite struct EditPermissionTests {
    @Test func appInstallWithWriteIsReady() {
        let writable = install(["issues": "write", "organization_projects": "write"])
        for field in [EditField.status, .labels, .assignees] {
            #expect(EditPermission.of(
                field, account: app, boardOwner: .org("acme"), installation: writable, ghAccounts: []) == .ready)
        }
        let admin = install(["issues": "admin", "organization_projects": "admin"])
        #expect(EditPermission.of(.status, account: app, boardOwner: .org("acme"), installation: admin, ghAccounts: [])
            == .ready)
    }

    @Test func appInstallStillReadOnlyNeedsApproval() {
        let readOnly = install(["issues": "read", "organization_projects": "read"])
        let permission = EditPermission.of(
            .labels, account: app, boardOwner: .org("acme"), installation: readOnly, ghAccounts: [])
        #expect(permission == .needsAppApproval(
            owner: "acme", isOrganization: true,
            url: URL(string: "https://github.com/organizations/acme/settings/installations/9")))
        #expect(permission.note
            == "Editing needs PullBull's new permissions for acme. An org owner accepts them on GitHub.")
    }

    @Test func issuesWriteDoesNotCoverStatus() {
        let issuesOnly = install(["issues": "write", "organization_projects": "read"])
        #expect(EditPermission.of(.labels, account: app, boardOwner: .org("acme"), installation: issuesOnly, ghAccounts: [])
            == .ready)
        #expect(EditPermission.of(.assignees, account: app, boardOwner: .org("acme"), installation: issuesOnly, ghAccounts: [])
            == .ready)
        guard case .needsAppApproval = EditPermission.of(
            .status, account: app, boardOwner: .org("acme"), installation: issuesOnly, ghAccounts: [])
        else { Issue.record("Status needs Projects write"); return }
    }

    @Test func personalInstallNote() {
        let personal = install(["issues": "read"], org: "me", isOrganization: false)
        let permission = EditPermission.of(.labels, account: app, boardOwner: nil, installation: personal, ghAccounts: [])
        #expect(permission == .needsAppApproval(
            owner: "me", isOrganization: false, url: URL(string: "https://github.com/settings/installations/9")))
        #expect(permission.note == "Editing needs PullBull's new permissions. Accept them on GitHub.")
    }

    @Test func installationWithoutIdHasNoReviewURL() {
        let noId = install(["issues": "read"], id: nil)
        #expect(EditPermission.of(.labels, account: app, boardOwner: .org("acme"), installation: noId, ghAccounts: [])
            == .needsAppApproval(owner: "acme", isOrganization: true, url: nil))
    }

    @Test func appAccountCannotEditAPersonalBoardsStatus() {
        let personal = install(["issues": "write"], org: "me", isOrganization: false)
        let permission = EditPermission.of(
            .status, account: app, boardOwner: .user("me"), installation: personal, ghAccounts: [])
        #expect(permission == .unavailable)
        #expect(permission.note == nil)
    }

    @Test func noInstallationIsUnavailable() {
        #expect(EditPermission.of(.labels, account: app, boardOwner: nil, installation: nil, ghAccounts: [])
            == .unavailable)
    }

    @Test func ghLoginWithReadProjectNeedsProjectScope() {
        let gh = [GhAccount(login: "me", scopes: ["repo", "read:org", "read:project"], active: true)]
        let permission = EditPermission.of(.status, account: ghMe, boardOwner: .org("acme"), installation: nil, ghAccounts: gh)
        #expect(permission == .needsGhScope(command: "gh auth refresh -s project"))
        #expect(permission.note == "Setting Status needs the project scope. Run: gh auth refresh -s project")
    }

    @Test func ghLoginLabelsAndAssigneesNeedOnlyRepo() {
        let gh = [GhAccount(login: "me", scopes: ["repo", "read:org", "read:project"], active: true)]
        #expect(EditPermission.of(.labels, account: ghMe, boardOwner: .org("acme"), installation: nil, ghAccounts: gh)
            == .ready)
        #expect(EditPermission.of(.assignees, account: ghMe, boardOwner: .org("acme"), installation: nil, ghAccounts: gh)
            == .ready)
    }

    @Test func ghLoginWithProjectScopeIsReady() {
        let gh = [GhAccount(login: "me", scopes: ["repo", "read:org", "project"], active: true)]
        #expect(EditPermission.of(.status, account: ghMe, boardOwner: .org("acme"), installation: nil, ghAccounts: gh)
            == .ready)
    }

    /// Not yet listed by `gh auth status`: assumed able, as for reading.
    @Test func unlistedGhLoginIsAssumedReady() {
        #expect(EditPermission.of(.status, account: ghMe, boardOwner: .org("acme"), installation: nil, ghAccounts: [])
            == .ready)
    }

    @Test func ghCommandSwitchesToAnInactiveLogin() {
        let gh = [
            GhAccount(login: "me", scopes: ["repo", "read:project"]),
            GhAccount(login: "work", scopes: ["repo", "project"], active: true),
        ]
        #expect(EditPermission.of(.status, account: ghMe, boardOwner: .org("acme"), installation: nil, ghAccounts: gh)
            == .needsGhScope(command: "gh auth switch --user me && gh auth refresh -s project && gh auth switch --user work"))
    }

    @Test func writeAccessFlags() {
        #expect(install(["issues": "write"]).canWriteIssues)
        #expect(!install(["issues": "read"]).canWriteIssues)
        #expect(install(["organization_projects": "admin"]).canWriteProjects)
        #expect(!install([:]).canWriteProjects)
        #expect(GhAccount(login: "me", scopes: ["project"]).canWriteProjects)
        #expect(!GhAccount(login: "me", scopes: ["read:project"]).canWriteProjects)
    }
}
