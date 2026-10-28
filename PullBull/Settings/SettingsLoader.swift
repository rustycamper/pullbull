import Foundation
import Observation
import PullBullKit

/// Loads what the Settings pickers offer (orgs, boards) and runs the account switch.
/// Settings themselves stay in `AppModel.settings`.
@Observable @MainActor
final class SettingsLoader {
    /// For `gh`, every org of the login; for an app account, the orgs that installed PullBull.
    private(set) var orgs: [String] = []
    /// An app account's other orgs, offered disabled as "Not approved"; empty for `gh`.
    private(set) var memberOrgs: [String] = []
    private(set) var orgsError: String?
    /// The current scope's owner's boards (the org's, or in no-org mode the user's own); `nil` until
    /// loaded, or when the token cannot read projects.
    private(set) var boards: [BoardSummary]?
    private(set) var boardsError: String?
    private(set) var accountError: String?
    private(set) var isSwitchingAccount = false

    func loadOrgs(_ model: AppModel) async {
        guard let account = model.settings.accountRef else {
            orgs = []
            memberOrgs = []
            orgsError = nil
            return
        }
        do {
            let loaded = try await model.organizations(for: account)
            // Best effort: without it the picker lists only the installed orgs.
            let members = account.source == .gitHubApp
                ? ((try? await model.memberOrganizations(for: account)) ?? []) : []
            // A late result for the previous account must not overwrite the new account's orgs.
            guard !Task.isCancelled else { return }
            orgs = loaded
            memberOrgs = members
            orgsError = nil
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            orgsError = RefreshError(error).message(org: nil, source: account.source)
        }
    }

    func loadBoards(_ model: AppModel, canReadProjects: Bool) async {
        boards = nil
        boardsError = nil
        guard canReadProjects, let account = model.settings.accountRef, let owner = model.settings.boardOwner
        else { return }
        do {
            let loaded = try await model.projects(for: account, owner: owner)
            // A late result for the previous owner must not overwrite the new owner's state.
            guard !Task.isCancelled else { return }
            boards = loaded
            // No board yet (the owner changed while its boards couldn't be read): take the first.
            if model.settings.board == nil, model.settings.boardOwner == owner,
               let first = BoardSummary.first(of: loaded) {
                model.settings.board = first.board
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            boardsError = RefreshError(error).message(org: model.settings.org, source: account.source)
        }
    }

    /// Switches to `account` with the org last chosen for it, else the current org if that account is
    /// in it, else its first org (`AppSettings.preferredOrg`). An app account chooses among its
    /// installed orgs and then its other orgs, so a remembered org that hasn't approved PullBull comes
    /// back with its approval message.
    /// An account without an org is switched to with no org: no-org mode.
    /// A signed-out app account is switched to with its remembered org.
    /// `personal` keeps no-org mode, for the personal board's "Use X from GitHub CLI".
    func selectAccount(_ account: AccountRef, model: AppModel, personal: Bool = false) async {
        guard account != model.settings.accountRef, !isSwitchingAccount else { return }
        isSwitchingAccount = true
        defer { isSwitchingAccount = false }
        accountError = nil
        do {
            let orgs = try await model.organizations(for: account)
            let members = account.source == .gitHubApp
                ? ((try? await model.memberOrganizations(for: account)) ?? []) : []
            let candidates = account.source == .gitHubApp
                ? OrgPicker.candidates(installed: orgs, memberOrgs: members) : orgs
            let org = personal ? nil : model.settings.preferredOrg(for: account.login, among: candidates)
            self.orgs = orgs
            memberOrgs = members
            orgsError = nil
            model.switchAccount(to: account, org: org)
        } catch is CancellationError {
        } catch AuthError.signedOut(let signedOut) where signedOut == account {
            // A signed-out app account is still reachable: with its remembered org, the popover offers
            // Sign In and Settings offers Sign Out….
            orgs = []
            memberOrgs = []
            orgsError = nil
            model.switchAccount(to: account, org: model.settings.orgByAccount[account.login])
        } catch {
            accountError = "Couldn't load \(account.login)'s organizations: \(RefreshError(error).message(org: nil, source: account.source))"
        }
    }
}
