import Foundation
import Observation
import PullBullKit

/// Loads what the Settings pickers offer (orgs, boards) and lists the orgs an account switch loads.
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

    /// Switches account through `AppModel.selectAccount`, then lists the orgs it loaded.
    func selectAccount(_ account: AccountRef, model: AppModel, personal: Bool = false) async {
        guard let loaded = await model.selectAccount(account, personal: personal) else { return }
        orgs = loaded.installed
        memberOrgs = loaded.members
        orgsError = nil
    }
}

/// The orgs an account switch loaded: for `gh` every org of the login, for an app account the orgs that
/// installed PullBull and its other orgs.
struct AccountOrgs {
    let installed: [String]
    let members: [String]
}
