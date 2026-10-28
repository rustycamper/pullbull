import AppKit
import PullBullKit
import SwiftUI

/// An app account's org hasn't approved PullBull (or needs SSO): what to do about it. Shown in Settings
/// under the org picker, in the popover's empty state and in the sign-in window.
struct OrgApprovalView: View {
    let notice: OrgAccessNotice
    let checking: Bool
    let checkAgain: () -> Void
    let alignment: HorizontalAlignment

    init(
        notice: OrgAccessNotice, checking: Bool, alignment: HorizontalAlignment = .leading,
        checkAgain: @escaping () -> Void
    ) {
        self.notice = notice
        self.checking = checking
        self.alignment = alignment
        self.checkAgain = checkAgain
    }

    init(org: String, installURL: URL, checking: Bool, checkAgain: @escaping () -> Void) {
        self.init(notice: .notApproved(org: org, installURL: installURL), checking: checking, checkAgain: checkAgain)
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
            switch notice {
            case .notApproved(_, let url), .personalInstall(_, let url, _):
                Text(notice.title).font(.system(size: 13, weight: .semibold))
                if let body = notice.body { note(body) }
                approvalButtons(installURL: url)
                    .padding(.top, 6)
            case .ssoRequired(_, let url):
                Text(notice.title).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    if let url {
                        Button("Open SSO Page") { NSWorkspace.shared.open(url) }
                    }
                    checkAgainButton
                }
                .padding(.top, 6)
            case .selectedRepositoriesOnly:
                note(notice.title)
            case .personalSelectedRepositories(let changeURL):
                note(notice.title)
                if let changeURL {
                    Button("Change Repositories…") { NSWorkspace.shared.open(changeURL) }
                        .padding(.top, 4)
                }
            }
        }
        .multilineTextAlignment(textAlignment)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    /// One row when it fits, else Request Approval above the other two.
    private func approvalButtons(installURL: URL) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                requestButton(installURL)
                copyButton(installURL)
                checkAgainButton
            }
            VStack(alignment: alignment, spacing: 8) {
                requestButton(installURL)
                HStack(spacing: 8) {
                    copyButton(installURL)
                    checkAgainButton
                }
            }
        }
    }

    private func requestButton(_ url: URL) -> some View {
        Button("Request Approval") { NSWorkspace.shared.open(url) }
            .buttonStyle(.borderedProminent)
    }

    /// The install link, for sending to an owner. A plain URL, nothing secret.
    private func copyButton(_ url: URL) -> some View {
        Button("Copy Link for an Owner") { PasteboardCopy.copyPlain(url.absoluteString) }
    }

    private var checkAgainButton: some View {
        Button(action: checkAgain) {
            HStack(spacing: 4) {
                if checking { ProgressView().controlSize(.mini) }
                Text("Check Again")
            }
        }
        .disabled(checking)
    }
}

#if DEBUG
private let previewInstallURL = URL(string: "https://github.com/apps/pullbull-for-macos/installations/new")!

#Preview("Not approved") {
    OrgApprovalView(org: "initech", installURL: previewInstallURL, checking: false, checkAgain: {})
        .padding()
        .frame(width: 480)
}

#Preview("Not approved, checking, centered") {
    OrgApprovalView(
        notice: .notApproved(org: "initech", installURL: previewInstallURL), checking: true, alignment: .center,
        checkAgain: {})
        .padding()
        .frame(width: 312)
}

#Preview("Selected repositories, personal") {
    OrgApprovalView(
        notice: .personalSelectedRepositories(changeURL: URL(string: "https://github.com/settings/installations/42")),
        checking: false, checkAgain: {})
        .padding()
        .frame(width: 480)
}

#Preview("SSO required") {
    OrgApprovalView(
        notice: .ssoRequired(org: "initech", url: URL(string: "https://github.com/orgs/initech/sso")),
        checking: false, checkAgain: {})
        .padding()
        .frame(width: 480)
}

#Preview("SSO required, no URL") {
    OrgApprovalView(notice: .ssoRequired(org: "initech", url: nil), checking: false, checkAgain: {})
        .padding()
        .frame(width: 480)
}

#Preview("Selected repositories") {
    OrgApprovalView(notice: .selectedRepositoriesOnly, checking: false, checkAgain: {})
        .padding()
        .frame(width: 480)
}
#endif
