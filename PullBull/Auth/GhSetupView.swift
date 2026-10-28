import AppKit
import PullBullKit
import SwiftUI

/// The GitHub CLI setup checklist: each step with its state, a note, and the command to run with Copy.
/// The steps tick themselves off as the model's passes see them done.
struct GhSetupView: View {
    let model: GhSetupModel
    /// Nil in previews.
    let app: AppModel?
    let onClose: () -> Void

    var body: some View {
        let checklist = model.checklist
        VStack(alignment: .leading, spacing: 16) {
            Text(checklist.intro)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(checklist.steps) { step in
                GhSetupStepRow(step: step)
            }
            Divider()
            action(checklist)
            statusLine
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
    }

    @ViewBuilder private func action(_ checklist: GhSetupChecklist) -> some View {
        if let login = checklist.login, checklist.isUsed(by: app?.settings.accountRef) {
            HStack {
                Label("PullBull is using \(login) from GitHub CLI.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.primary)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        } else {
            let login = checklist.login
            let use = app?.ghUse
            let using = use != nil && use?.failure == nil
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let login { model.use(login) }
                } label: {
                    HStack(spacing: 6) {
                        if using { ProgressView().controlSize(.small) }
                        Text(login.map { using ? FirstRunChoice.usingTitle($0) : FirstRunChoice.useTitle($0) }
                            ?? "Use GitHub CLI")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!checklist.canUse || using)
                if let use, let failure = use.failure, use.login == login {
                    Text(FirstRunChoice.failure(use.login, message: failure))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if model.checking {
                ProgressView().controlSize(.small)
                Text("Checking…")
            } else if let checkedAt = model.checkedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(GhSetupChecklist.checkedText(at: checkedAt, now: context.date))
                }
            }
            Spacer()
            Button("Check Now") { model.checkNow() }
                .controlSize(.small)
                .disabled(model.checking)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

/// One step: a glyph and a word for its state, the title, its notes and the command to copy.
private struct GhSetupStepRow: View {
    let step: GhSetupChecklist.Step
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(step.done ? Color.green : Color.secondary)
                Text("\(step.number). \(step.title)").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(step.done ? "Done" : "To do")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.accessibilityLabel)
            Group {
                if let subtitle = step.subtitle { secondary(subtitle) }
                if let note = step.note { secondary(note) }
                if let warning = step.warning {
                    Label {
                        Text(warning).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.amberGlyph)
                    }
                    .font(.system(size: 12))
                }
                if !step.done, let command = step.command { commandBox(command) }
                if !step.done, let link = step.link {
                    Button(link.title) { NSWorkspace.shared.open(link.url) }
                        .controlSize(.small)
                }
            }
            .padding(.leading, 24)
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The command, selectable, with Copy. Commands only: nothing secret.
    private func commandBox(_ command: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                PasteboardCopy.copyPlain(command)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.small)
            .accessibilityLabel("Copy command: \(command)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator, lineWidth: 0.5))
    }
}

#if DEBUG
@MainActor private func previewChecklist(_ status: GhStatus?, purpose: GhSetupChecklist.Purpose = .firstRun,
                                         homebrew: Bool = true) -> some View {
    GhSetupView(model: GhSetupModel(previewing: status, purpose: purpose, homebrew: homebrew), app: nil, onClose: {})
}

private let previewPath = "/opt/homebrew/bin/gh"

#Preview("No gh") { previewChecklist(.notInstalled) }
#Preview("No gh, no Homebrew") { previewChecklist(.notInstalled, homebrew: false) }
#Preview("Installed, no login") { previewChecklist(.logins(gh: previewPath, [])) }
#Preview("Logged in") {
    previewChecklist(.logins(gh: previewPath, [
        GhLogin(login: "rustycamper", active: true, health: .ok, scopes: ["repo", "read:project"]),
    ]))
}
#Preview("Expired") {
    previewChecklist(.logins(gh: previewPath, [
        GhLogin(login: "rustycamper", active: true, health: .invalid, scopes: []),
    ]))
}
#Preview("Board, other login active") {
    previewChecklist(.logins(gh: previewPath, [
        GhLogin(login: "devon", active: true, health: .ok, scopes: ["repo"]),
        GhLogin(login: "rustycamper", active: false, health: .ok, scopes: ["repo"]),
    ]), purpose: .board(login: "rustycamper"))
}
#Preview("gh auth status failed") { previewChecklist(.failed(gh: previewPath, message: "error connecting to keyring")) }
#endif
