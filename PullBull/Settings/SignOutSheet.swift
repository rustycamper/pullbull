import PullBullKit
import SwiftUI

/// Confirms Sign Out for an app account or a `gh` login, runs it, and says so if an app account's
/// Keychain item couldn't be deleted. A `gh` login stays logged in to GitHub CLI; the sheet shows the
/// command that logs it out there.
struct SignOutSheet: View {
    enum Phase: Equatable {
        case confirming, signingOut, keychainFailed
    }

    let account: AccountRef
    let phase: Phase
    let cancel: () -> Void
    let signOut: () -> Void

    private var login: String { account.login }

    private var ghLogoutCommand: String { "gh auth logout --user \(login)" }

    /// Markdown: for an app account "GitHub settings" is a link to the app authorizations page; for a
    /// `gh` login the command is code.
    private var explanation: LocalizedStringKey {
        switch account.source {
        case .gitHubApp:
            LocalizedStringKey(
                "PullBull forgets this account and its cached pull requests and issues on this Mac. To revoke PullBull's "
                    + "access entirely, open [GitHub settings](https://github.com/settings/apps/authorizations).")
        case .gh:
            LocalizedStringKey(
                "PullBull stops using \(login) and forgets its cached pull requests and issues on this Mac. GitHub CLI "
                    + "stays signed in; to sign out there too, run:")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch phase {
            case .confirming, .signingOut:
                Text("Sign out of \(login)?")
                    .font(.headline)
                Text(explanation)
                    .fixedSize(horizontal: false, vertical: true)
                if account.source == .gh {
                    CopyableCommand(command: ghLogoutCommand)
                }
                HStack {
                    if phase == .signingOut { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Sign Out", role: .destructive, action: signOut)
                        .keyboardShortcut(.defaultAction)
                }
                .disabled(phase == .signingOut)
                .padding(.top, 6)
            case .keychainFailed:
                Label("Couldn't remove the sign-in from the Keychain", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                HStack {
                    Spacer()
                    Button("OK", action: cancel)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

#if DEBUG
private let previewApp = AccountRef(login: "devon", source: .gitHubApp)

#Preview("Confirm") {
    SignOutSheet(account: previewApp, phase: .confirming, cancel: {}, signOut: {})
}

#Preview("Confirm, gh") {
    SignOutSheet(account: AccountRef(login: "devon", source: .gh), phase: .confirming, cancel: {}, signOut: {})
}

#Preview("Signing out") {
    SignOutSheet(account: previewApp, phase: .signingOut, cancel: {}, signOut: {})
}

#Preview("Keychain failed") {
    SignOutSheet(account: previewApp, phase: .keychainFailed, cancel: {}, signOut: {})
}
#endif
