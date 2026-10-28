import AppKit
import PullBullKit
import SwiftUI

/// "Choose the repositories PullBull can see": a signed-in user with no org installs PullBull on their own
/// account. Shown in the sign-in window, the popover's empty state and Settings. While it shows, the
/// model re-checks the installations on a timer after Choose Repositories on GitHub.
struct PersonalInstallView: View {
    let model: AppModel
    let target: PersonalInstallTarget
    var alignment: HorizontalAlignment = .leading
    /// The sign-in window's Not Now; nil elsewhere.
    var onNotNow: (() -> Void)?
    /// The step found PullBull installed (the sign-in window closes).
    var onInstalled: (() -> Void)?

    var body: some View {
        let step = model.personalInstallStep ?? .intro
        PersonalInstallContent(
            target: target, step: step, ownerURL: model.installURL, checking: model.checkingAccess,
            alignment: alignment, onNotNow: onNotNow,
            choose: { model.chooseRepositoriesOnGitHub(target.installURL) },
            checkAgain: { Task { await model.checkPersonalInstallAgain() } })
        .onAppear { model.personalInstallStepAppeared() }
        .onDisappear { model.personalInstallStepDisappeared() }
        .onChange(of: step.isFinished, initial: true) { _, finished in
            if finished { onInstalled?() }
        }
    }
}

/// The step's layout for a given state, apart from the model (previews).
struct PersonalInstallContent: View {
    let target: PersonalInstallTarget
    let step: PersonalInstallStep
    let ownerURL: URL
    let checking: Bool
    let alignment: HorizontalAlignment
    let onNotNow: (() -> Void)?
    let choose: () -> Void
    let checkAgain: () -> Void

    private var notice: OrgAccessNotice {
        .personalInstall(login: target.login, installURL: target.installURL, ownerURL: ownerURL)
    }

    private var textAlignment: TextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            if step.isFinished {
                finished
            } else {
                Text(notice.title).font(.system(size: 13, weight: .semibold))
                if let body = notice.body { secondary(body) }
                statusLine
                buttons.padding(.top, 6)
                footer.padding(.top, 10)
            }
        }
        .multilineTextAlignment(textAlignment)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: step) { old, new in
            guard old != new, let line = new.line else { return }
            AccessibilityNotification.Announcement(line).post()
        }
    }

    @ViewBuilder private var finished: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(.green)
            .accessibilityHidden(true)
        if let line = step.line { Text(line) }
    }

    @ViewBuilder private var statusLine: some View {
        switch step {
        case .waiting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(step.line ?? "")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            if let detail = step.detail { secondary(detail) }
        case .checkFailedWhileWaiting, .checkFailed:
            Label(step.line ?? "", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Palette.amberGlyph)
                .padding(.top, 4)
        case .waitedOut:
            secondary(step.line ?? "").padding(.top, 4)
        case .intro, .installedAll, .installedSelected, .installedOnOrg:
            EmptyView()
        }
    }

    /// One row when it fits, else Choose Repositories above the others.
    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                chooseButton
                checkAgainButton
                notNowButton
            }
            VStack(alignment: alignment, spacing: 8) {
                chooseButton
                HStack(spacing: 8) {
                    checkAgainButton
                    notNowButton
                }
            }
        }
    }

    private var chooseButton: some View {
        Button("Choose Repositories on GitHub", action: choose)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }

    private var checkAgainButton: some View {
        Button(action: checkAgain) {
            HStack(spacing: 4) {
                if checking { ProgressView().controlSize(.mini) }
                Text("Check Again")
            }
        }
        .disabled(checking)
        .accessibilityLabel(checking ? "Checking" : "Check Again")
    }

    @ViewBuilder private var notNowButton: some View {
        if let onNotNow {
            Button("Not Now", action: onNotNow)
                .keyboardShortcut(.cancelAction)
        }
    }

    /// The org path stays reachable: the plain install page, for an owner.
    private var footer: some View {
        VStack(alignment: alignment, spacing: 6) {
            secondary(OrgAccessNotice.personalFooter)
            Button("Copy Link for an Owner") { PasteboardCopy.copyPlain(ownerURL.absoluteString) }
                .controlSize(.small)
                .help("Copies the install link for an organization owner")
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
private let previewTarget = PersonalInstallTarget(
    login: "rustycamper",
    installURL: URL(string: "https://github.com/apps/pullbull-for-macos/installations/new/permissions?target_id=1")!,
    installationID: 42)
private let previewOwnerURL = URL(string: "https://github.com/apps/pullbull-for-macos/installations/new")!

@MainActor private func previewStep(_ step: PersonalInstallStep, alignment: HorizontalAlignment = .center) -> some View {
    PersonalInstallContent(
        target: previewTarget, step: step, ownerURL: previewOwnerURL, checking: false, alignment: alignment,
        onNotNow: alignment == .center ? {} : nil, choose: {}, checkAgain: {})
        .padding(24)
        .frame(width: 360)
}

#Preview("Intro") { previewStep(.intro) }
#Preview("Waiting") { previewStep(.waiting) }
#Preview("Waited 10 min") { previewStep(.waitedOut) }
#Preview("Offline") { previewStep(.checkFailedWhileWaiting(.offline)) }
#Preview("Unreachable") { previewStep(.checkFailed(.offline)) }
#Preview("Refused, waiting") { previewStep(.checkFailedWhileWaiting(.forbidden)) }
#Preview("Secure connection failed") { previewStep(.checkFailed(.unreachable(.secureConnectionFailed))) }
#Preview("Installed, all") { previewStep(.installedAll) }
#Preview("Installed, selected") { previewStep(.installedSelected(count: 3)) }
#Preview("Installed on an org") { previewStep(.installedOnOrg("initech")) }
#Preview("Settings, intro") { previewStep(.intro, alignment: .leading).frame(width: 480) }
#endif
