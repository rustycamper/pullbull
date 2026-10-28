import PullBullKit
import SwiftUI

struct SignInView: View {
    let model: SignInModel
    let app: AppModel
    let onClose: () -> Void
    /// The personal install step found PullBull installed; the window closes shortly after.
    let onInstalled: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            content
        }
        .padding(24)
        .frame(width: 360)
        .frame(minHeight: 300)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .requesting(let unreachable):
            ProgressView().controlSize(.small)
            Text("Getting a code…").foregroundStyle(.secondary)
            if unreachable { offlineNotice }
            cancelButton
        case .code(let userCode, _, let expiresAt, let unreachable):
            codeContent(userCode: userCode, expiresAt: expiresAt, unreachable: unreachable)
        case .finishing:
            ProgressView().controlSize(.small)
            Text("Finishing sign-in…").foregroundStyle(.secondary)
        case .signedIn(let outcome):
            signedIn(outcome)
        case .expired:
            Text("That code expired.")
            Button("Get a New Code") { model.start() }.keyboardShortcut(.defaultAction)
        case .denied:
            Text("Sign-in was cancelled on GitHub.")
            HStack {
                Button("Try Again") { model.start() }.keyboardShortcut(.defaultAction)
                Button("Close", action: onClose)
            }
        case .tooManyCodes:
            message("GitHub has issued too many codes. Try again in a few minutes.")
            Button("Close", action: onClose)
        case .misconfigured:
            message("PullBull can't sign in right now (app misconfigured).")
            Button("Close", action: onClose)
        }
    }

    private func codeContent(userCode: String, expiresAt: Date, unreachable: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text(userCode)
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                Button { model.copyCode() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy code")
                    .accessibilityLabel("Copy code")
            }
            Button("Copy Code and Open GitHub") { model.copyCodeAndOpenGitHub() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            if unreachable {
                offlineNotice
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to approve PullBull on github.com…")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text("Code expires in \(Self.minutesLeft(until: expiresAt, now: context.date)) min")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("Only enter a code PullBull is showing you right now.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
            cancelButton
        }
    }

    @ViewBuilder private func signedIn(_ outcome: SignInOutcome) -> some View {
        switch outcome {
        case .ready(let identity):
            Image(systemName: "checkmark.circle.fill").font(.system(size: 28)).foregroundStyle(.green)
            AvatarView(login: identity.login, url: identity.avatarURL, size: 48)
            Text("Signed in as \(Text(identity.login).bold())")
        case .needsApproval(_, let org, let installURL):
            OrgApprovalView(
                notice: .notApproved(org: org, installURL: installURL), checking: model.checking, alignment: .center
            ) {
                Task { await model.checkAgain() }
            }
            Button("Close", action: onClose)
        case .needsPersonalInstall(let identity):
            if let target = app.personalInstallTarget, target.login == identity.login {
                PersonalInstallView(
                    model: app, target: target, alignment: .center, onNotNow: onClose, onInstalled: onInstalled)
            } else {
                Text("Signed in as \(Text(identity.login).bold())")
                Button("Close", action: onClose)
            }
        case .differentLogin(let identity, let stillSignedOut):
            AvatarView(login: identity.login, url: identity.avatarURL, size: 48)
            message("You signed in as \(identity.login). \(stillSignedOut) is still signed out.")
            Button("Close", action: onClose)
        case .unreachable:
            message("Couldn't reach GitHub to finish signing in. Check your connection and try again.")
            retryButtons
        case .saveFailed(let needsSignedBuild):
            if needsSignedBuild {
                message("Couldn't save your sign-in. Sign in with GitHub needs a team-signed build; use a gh CLI login.")
                Button("Close", action: onClose)
            } else {
                message("Couldn't save your sign-in to the Keychain.")
                retryButtons
            }
        }
    }

    /// Try Again starts over with a new code: the granted pair is not kept.
    private var retryButtons: some View {
        HStack {
            Button("Close", action: onClose)
            Button("Try Again") { model.start() }.keyboardShortcut(.defaultAction)
        }
    }

    private var offlineNotice: some View {
        Label("Can't reach GitHub. Still trying…", systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(Palette.amberGlyph)
    }

    private var cancelButton: some View {
        Button("Cancel") {
            model.cancel()
            onClose()
        }
        .keyboardShortcut(.cancelAction)
    }

    private func message(_ text: String) -> some View {
        Text(text).multilineTextAlignment(.center)
    }

    static func minutesLeft(until expiresAt: Date, now: Date) -> Int {
        max(0, Int((expiresAt.timeIntervalSince(now) / 60).rounded(.up)))
    }
}

#if DEBUG
private let previewURL = URL(string: "https://github.com/login/device")!
private let previewIdentity = GitHubIdentity(login: "devon", userID: 1, avatarURL: nil)

@MainActor private func previewView(_ phase: SignInModel.Phase) -> some View {
    SignInView(
        model: SignInModel(previewing: phase), app: AppModel(preview: PreviewData.snapshot), onClose: {},
        onInstalled: {})
}

@MainActor private func codePhase(unreachable: Bool) -> SignInModel.Phase {
    .code(userCode: "WDJB-MJHT", url: previewURL, expiresAt: .now.addingTimeInterval(14 * 60), unreachable: unreachable)
}

#Preview("Requesting") { previewView(.requesting(unreachable: false)) }
#Preview("Requesting, offline") { previewView(.requesting(unreachable: true)) }
#Preview("Code") { previewView(codePhase(unreachable: false)) }
#Preview("Code, offline") { previewView(codePhase(unreachable: true)) }
#Preview("Finishing") { previewView(.finishing) }
#Preview("Signed in") { previewView(.signedIn(.ready(previewIdentity))) }
#Preview("Needs approval") {
    previewView(.signedIn(.needsApproval(previewIdentity, org: "initech", installURL: previewURL)))
}
#Preview("Different login") {
    previewView(.signedIn(.differentLogin(previewIdentity, stillSignedOut: "old-login")))
}
#Preview("Unreachable") { previewView(.signedIn(.unreachable)) }
#Preview("Save failed") { previewView(.signedIn(.saveFailed(needsSignedBuild: false))) }
#Preview("Save failed, unsigned") { previewView(.signedIn(.saveFailed(needsSignedBuild: true))) }
#Preview("Expired") { previewView(.expired) }
#Preview("Denied") { previewView(.denied) }
#Preview("Too many codes") { previewView(.tooManyCodes) }
#Preview("Misconfigured") { previewView(.misconfigured) }
#endif
