import AppKit
import PullBullKit
import SwiftUI

/// The GitHub account, its organization and Projects board, and what is wrong with their access.
struct AccountSettingsTab: View {
    @Bindable var model: AppModel
    let loader: SettingsLoader
    /// The account the Sign Out sheet is for, and where that sheet is; the sheet lives in `SettingsView`.
    @Binding var signOutTarget: AccountRef?
    @Binding var signOutPhase: SignOutSheet.Phase

    var body: some View {
        Form {
            accountSection
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accountSection: some View {
        Section("Account") {
            LabeledContent {
                HStack(spacing: 8) {
                    accountPicker
                    if let account = model.settings.accountRef {
                        Button("Sign Out…") {
                            signOutPhase = .confirming
                            signOutTarget = account
                        }
                        .disabled(model.isSwitchingAccount)
                    }
                }
            } label: {
                RowLabel("GitHub account", note: model.accountSwitchError ?? accountSourceNote,
                         isWarning: model.accountSwitchError != nil)
            }
            if AccountPicker.offersSignIn(current: model.settings.accountRef, canSignIn: model.canSignInWithGitHub) {
                MutedLine("Sign in with GitHub to stop depending on gh.")
            } else if model.needsTeamSignedBuild {
                MutedLine("Sign in with GitHub needs a team-signed build; use a gh CLI login")
            }

            Picker(selection: orgSelection) {
                if model.settings.org == nil {
                    Text("None").tag("")
                }
                ForEach(orgChoices) { item in
                    Text(item.label).tag(item.org)
                }
            } label: {
                RowLabel("Organization", note: loader.orgsError ?? orgNote, isWarning: loader.orgsError != nil)
            }
            .disabled(model.isSwitchingAccount || model.settings.account == nil)
            if case .personalInstall = model.orgAccessNotice, let target = model.personalInstallTarget {
                PersonalInstallView(model: model, target: target)
            } else if let notice = model.orgAccessNotice {
                OrgApprovalView(notice: notice, checking: model.checkingAccess) {
                    Task { await model.checkOrgAccessAgain() }
                }
            }

            boardRow
        }
    }

    /// Signed-in app accounts, then the `gh` CLI logins, then Add Account… when sign-in works.
    private var accountPicker: some View {
        let sections = AccountPicker.sections(
            appAccounts: model.appAccounts, ghLogins: model.accounts.map(\.login), current: model.settings.accountRef)
        return Picker("GitHub account", selection: accountSelection) {
            if model.settings.accountRef == nil {
                Text("None").tag(AccountChoice.none)
            }
            ForEach(sections.app, id: \.self) { Text($0.login).tag(AccountChoice.account($0)) }
            if !sections.gh.isEmpty {
                Section("gh CLI") {
                    ForEach(sections.gh, id: \.self) { Text($0.login).tag(AccountChoice.account($0)) }
                }
            }
            if model.canSignInWithGitHub {
                Divider()
                Text("Add Account…").tag(AccountChoice.addAccount)
            }
        }
        .labelsHidden()
        .fixedSize()
        .disabled(model.isSwitchingAccount)
    }

    @ViewBuilder private var boardRow: some View {
        if canReadProjects {
            Picker(selection: $model.settings.board) {
                if model.settings.board == nil {
                    Text("None").tag(BoardRef?.none)
                }
                ForEach(boardChoices, id: \.board) { board in
                    Text(board.title).tag(BoardRef?.some(board.board))
                }
            } label: {
                let warning = loader.boardsError ?? boardFetchError.map { "Couldn't load this board: \($0)" }
                RowLabel("Projects board", note: warning ?? "Board tab, and Status groups on Assigned",
                         isWarning: warning != nil)
            }
        } else {
            LabeledContent {
                boardSetupAction
            } label: {
                RowLabel("Projects board", note: projectAccessNote)
                    .textSelection(.enabled)
            }
            if model.settings.org != nil, !isAppAccount {
                CopyableCommand(command: model.addProjectScopeCommand)
            }
        }
    }

    /// No-org mode: Set Up… opens the GitHub CLI checklist for this login, or, when GitHub CLI already
    /// has it with board access, one click switches to it. Otherwise the board is just off.
    @ViewBuilder private var boardSetupAction: some View {
        switch model.personalBoardAccess {
        case .useGhLogin(let ghLogin):
            Button("Use \(ghLogin) from GitHub CLI") {
                Task { await loader.selectAccount(AccountRef(login: ghLogin, source: .gh), model: model, personal: true) }
            }
            .disabled(model.isSwitchingAccount)
        case .addScope, .logIn:
            Button("Set Up…") {
                guard let login = model.settings.account else { return }
                GhSetupWindowController.shared.show(app: model, purpose: .board(login: login))
            }
            .disabled(model.isSwitchingAccount)
        case .ready, nil:
            Label("Disabled", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    private var canReadProjects: Bool { model.canReadProjects }

    private var isAppAccount: Bool { model.settings.accountRef?.source == .gitHubApp }

    private var accountSourceNote: String {
        isAppAccount ? "Signed in with GitHub" : "From your gh CLI logins"
    }

    /// No-org mode ("None") says what it leaves out.
    private var orgNote: String {
        model.settings.account != nil && model.settings.org == nil
            ? "Team and org search need an organization"
            : "Team = every other member of this org"
    }

    /// Why the board is off. No org: a personal board needs a GitHub CLI login with the project scope
    /// (GitHub gives apps no access to personal boards). An org: its permission for an app account, the
    /// `gh` scope otherwise.
    private var projectAccessNote: String {
        guard let org = model.settings.org else {
            return isAppAccount ? "Personal boards need a GitHub CLI login" : "Needs the read:project scope"
        }
        if isAppAccount {
            return "An owner of \(org) needs to accept PullBull's Projects permission"
        }
        return "Needs the read:project scope. Run this in Terminal:"
    }

    private var orgChoices: [OrgPickerItem] {
        OrgPicker.items(
            source: model.settings.accountRef?.source ?? .gh, installed: loader.orgs, memberOrgs: loader.memberOrgs,
            current: model.settings.org, currentAccess: model.settings.org.flatMap { model.orgAccess[$0] })
    }

    private var boardChoices: [BoardSummary] {
        BoardSummary.choices(loader.boards ?? [], current: model.settings.board)
    }

    /// Why the last poll couldn't load the chosen board.
    private var boardFetchError: String? {
        guard let snapshot = model.snapshot, let board = model.settings.board, board.matches(snapshot.board)
        else { return nil }
        return snapshot.boardError
    }

    private var accountSelection: Binding<AccountChoice> {
        Binding(
            get: { model.settings.accountRef.map(AccountChoice.account) ?? .none },
            set: { choice in
                switch choice {
                case .none: break
                case .addAccount: model.showSignIn()
                case .account(let account): Task { await loader.selectAccount(account, model: model) }
                }
            })
    }

    private var orgSelection: Binding<String> {
        Binding(
            get: { model.settings.org ?? "" },
            set: { org in
                // A not-approved org can be chosen too; the approval message then shows below.
                guard !org.isEmpty else { return }
                model.settings.org = org
            })
    }
}

/// The account picker's entries: an account, or the Add Account… item that opens sign-in.
private enum AccountChoice: Hashable {
    case none
    case account(AccountRef)
    case addAccount
}

/// A one-line muted note as its own row.
private struct MutedLine: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
