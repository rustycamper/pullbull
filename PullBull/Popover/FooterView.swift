import SwiftUI
import PullBullKit

/// The account, then the age (only once stale), refresh (a spinner while refreshing), the link for the tab on
/// screen and Settings; or the amber error state with Retry.
/// In the first-run and signed-out layout, only the gear. A muted line above it says when a renewed
/// sign-in couldn't be saved to the Keychain.
struct FooterView: View {
    let model: AppModel
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            if model.isSignInUnsaved, !model.showsFirstRun { unsavedLine }
            bar
        }
    }

    private var unsavedLine: some View {
        Text("Couldn't save your sign-in; you'll be asked again next launch.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.listGutter)
            .padding(.vertical, 6)
            .overlay(alignment: .top) { Hairline() }
    }

    @ViewBuilder private var bar: some View {
        if model.showsFirstRun {
            gearOnlyBody
        } else if let error = model.status.error, model.snapshot != nil {
            errorBody(error)
        } else if let issuesError {
            let title = "\(model.selectedIssueTab.title) didn't update"
            warningBody(
                symbol: "exclamationmark.triangle",
                message: Text(title).fontWeight(.semibold).foregroundColor(.primary)
                    + Text(" · \(issuesStaleDetail ?? issuesError)").foregroundColor(.primary),
                // The line shows the age when known, so the tooltip adds the reason.
                help: issuesStaleDetail.map { "\(title) · \($0)\n\(issuesError)" } ?? "\(title) · \(issuesError)")
        } else {
            normalBody
        }
    }

    private var gearOnlyBody: some View {
        HStack {
            Spacer()
            SettingsGearButton()
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .overlay(alignment: .top) { Hairline() }
    }

    private var normalBody: some View {
        let link = footerLink
        return HStack(spacing: 4) {
            if let login = model.settings.account {
                AccountButton(login: login, scope: model.settings.org ?? "personal")
            }
            Spacer(minLength: 8)
            // The age shows only once the data is stale; "Copied" takes its place for a moment.
            if let copied = CopyConfirmation.shared.message {
                CopiedNote(message: copied)
                    .layoutPriority(1)
            } else if let staleText {
                Text(staleText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if model.status.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 24, height: 24)
                    .help(refreshHelp)
                    .accessibilityLabel("Refreshing")
            } else {
                FooterIconButton(symbol: "arrow.clockwise", help: refreshHelp) { model.refresh() }
            }
            FooterIconButton(symbol: "arrow.up.right.square", help: "\(link.title) (\(link.url.absoluteString))") {
                NSWorkspace.shared.open(link.url)
            }
            .accessibilityLabel("Open \(link.title)")
            SettingsGearButton()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.listGutter)
        .padding(.trailing, 8)
        .frame(height: 34)
        .overlay(alignment: .top) { Hairline() }
    }

    /// The focused repo's PRs or issues, else the tab's page on GitHub (`GitHubLinks.footer`).
    private var footerLink: (title: String, url: URL) {
        GitHubLinks.footer(
            mode: model.mode, prTab: model.selectedTab, issueTab: model.selectedIssueTab, org: model.settings.org,
            board: model.settings.board, boardTitle: model.snapshot?.boardTitle,
            focus: model.repoFocus, choices: model.repoChoices)
    }

    /// The poll succeeded but the search of the Assigned or Created tab on screen did not (its list is
    /// the previous one); never on Board, which has its own state. Not while the list is empty or never
    /// loaded: the list itself then shows the error with Retry.
    private var issuesError: String? {
        guard model.mode == .issues, let issueTabs = model.issueTabs else { return nil }
        let tab = model.selectedIssueTab
        guard issueTabs.isLoaded(tab), issueTabs.contents(tab)?.groups.isEmpty == false else { return nil }
        return model.snapshot?.issuesError(for: tab)
    }

    /// "showing results from 12m ago" for the list on screen, when its fetch time is known.
    private var issuesStaleDetail: String? {
        guard let fetched = model.snapshot?.issuesFetchedAt(for: model.selectedIssueTab) else { return nil }
        return "showing results from \(RelativeAge.ago(fetched, now: now))"
    }

    private func errorBody(_ error: RefreshError) -> some View {
        warningBody(
            symbol: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            message: Text(model.message(for: error)).fontWeight(.semibold).foregroundColor(.primary)
                + Text(lastUpdatedSuffix).foregroundColor(.primary),
            help: model.message(for: error) + lastUpdatedSuffix)
    }

    /// One line at the normal bar's 34pt, so a warning changes the colour, not the height: the message
    /// truncates, with the full text in the tooltip and in VoiceOver.
    private func warningBody(symbol: String, message: Text, help: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Palette.amberGlyph)
            message
                .lineLimit(1)
                .truncationMode(.tail)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(help)
            Button("Retry") { model.refresh() }
                .buttonStyle(FooterButtonStyle())
                .help("Retry (⌘R)")
                .disabled(model.status.isRefreshing)
            // The header has no gear, so Settings stays reachable while the bar shows an error.
            SettingsGearButton()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.listGutter)
        .padding(.trailing, 8)
        .frame(height: 34)
        .background(Palette.amberFill)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    /// "Refresh (⌘R)", with when the data was last updated.
    private var refreshHelp: String {
        guard let last = model.status.lastSuccess else { return "Refresh (⌘R)" }
        return "Refresh (⌘R) · Updated \(RelativeAge.ago(last, now: now))"
    }

    /// "15m ago" once the data is older than two poll intervals (the menu bar icon's stale rule); nil while fresh.
    private var staleText: String? {
        let interval = Duration.seconds(max(1, model.settings.refreshMinutes) * 60)
        guard let last = model.status.lastSuccess, model.status.isStale(now: now, interval: interval) else { return nil }
        return RelativeAge.ago(last, now: now)
    }

    private var lastUpdatedSuffix: String {
        guard let last = model.status.lastSuccess else { return "" }
        return ", last updated \(RelativeAge.ago(last, now: now))"
    }
}

private struct FooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.strongFill.opacity(configuration.isPressed ? 1.6 : 1)))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Who PullBull reads GitHub as, with the org or "personal"; opens Settings › Account. When the bar is tight
/// the scope goes first, then the whole label.
private struct AccountButton: View {
    let login: String
    let scope: String

    var body: some View {
        Button {
            UserDefaults.standard.set(SettingsTab.account.rawValue, forKey: "settings.tab")
            SettingsOpener.open()
        } label: {
            ViewThatFits(in: .horizontal) {
                label("\(login) · \(scope)")
                label(login)
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .buttonStyle(.plain)
        .help("Account settings")
        .accessibilityLabel("Signed in as \(login), \(scope)")
    }

    private func label(_ text: String) -> some View {
        HStack(spacing: 5) {
            AvatarView(login: login, url: CachedAvatars.profileImageURL(login), size: 14)
            Text(text).lineLimit(1)
        }
        .fixedSize()
    }
}

private struct FooterIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            FooterGlyph(systemName: symbol)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering && isEnabled ? Palette.fill : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A footer icon drawn in a fixed 12pt box rather than at a font size, so glyphs of different shapes
/// (refresh, link, gear) share one visual size and centre line.
struct FooterGlyph: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(.medium)
            .frame(width: 12, height: 12)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
    }
}
