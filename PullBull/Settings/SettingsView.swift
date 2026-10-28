import AppKit
import PullBullKit
import SwiftUI

/// The tabs of the Settings window.
enum SettingsTab: String {
    case general, account, notifications, search, ask
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var loader = SettingsLoader()
    @State private var permission: NotificationPermission
    /// The account the Sign Out sheet is for, and where that sheet is.
    @State private var signOutTarget: AccountRef?
    @State private var signOutPhase = SignOutSheet.Phase.confirming
    /// The last tab the user picked; a per-viewer preference, not part of the saved settings.
    @AppStorage("settings.tab") private var rememberedTab = SettingsTab.general.rawValue
    @State private var tab: SettingsTab
    @State private var shortcutRecorder = KeyRecorder()

    init(model: AppModel, permission: NotificationPermission = NotificationPermission()) {
        self.model = model
        _permission = State(initialValue: permission)
        _tab = State(initialValue: Self.openingTab(model: model))
    }

    var body: some View {
        TabView(selection: tabSelection) {
            GeneralSettingsTab(model: model, shortcutRecorder: shortcutRecorder)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AccountSettingsTab(
                model: model, loader: loader, signOutTarget: $signOutTarget, signOutPhase: $signOutPhase)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag(SettingsTab.account)
            NotificationSettingsTab(model: model, permission: permission)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            SearchSettingsTab(model: model)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(SettingsTab.search)
            AskSettingsTab(model: model)
                .tabItem { Label("Ask", systemImage: "text.magnifyingglass") }
                .tag(SettingsTab.ask)
        }
        .frame(width: 520)
        .navigationTitle("PullBull Settings")
        .background(WindowTitle("PullBull Settings"))
        .onAppear {
            SettingsOpener.settingsDidAppear()
            model.reloadAccounts()
            tab = Self.openingTab(model: model)
        }
        .task { await permission.refresh() }
        .onDisappear {
            shortcutRecorder.stop()
            SettingsOpener.settingsDidDisappear()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permission.refresh() }
        }
        .task(id: model.settings.accountRef) { await loader.loadOrgs(model) }
        .sheet(isPresented: signOutSheetShown) {
            if let target = signOutTarget {
                SignOutSheet(
                    account: target, phase: signOutPhase, cancel: { signOutTarget = nil },
                    signOut: { signOut(target) })
                    .interactiveDismissDisabled(signOutPhase == .signingOut)
            }
        }
        .task(id: BoardsKey(
            account: model.settings.accountRef, owner: model.settings.boardOwner, canRead: model.canReadProjects
        )) {
            await loader.loadBoards(model, canReadProjects: model.canReadProjects)
        }
    }

    /// Picking a tab remembers it; opening on Account because it needs attention does not.
    private var tabSelection: Binding<SettingsTab> {
        Binding(
            get: { tab },
            set: { picked in
                shortcutRecorder.stop()
                tab = picked
                rememberedTab = picked.rawValue
            })
    }

    /// Account when it needs attention, else the last tab picked.
    private static func openingTab(model: AppModel) -> SettingsTab {
        needsAccountAttention(model)
            ? .account : SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general
    }

    /// What the popover shows in place of the lists: the first-run or signed-out layout, an org that
    /// hasn't approved PullBull, or SSO to authorize. Settings then opens on Account.
    private static func needsAccountAttention(_ model: AppModel) -> Bool {
        if model.showsFirstRun || model.orgAccessNotice?.blocksPolling == true { return true }
        if case .ssoRequired = model.status.error { return true }
        return false
    }

    private var signOutSheetShown: Binding<Bool> {
        Binding(
            get: { signOutTarget != nil },
            set: { shown in
                if !shown, signOutPhase != .signingOut { signOutTarget = nil }
            })
    }

    /// Runs Sign Out from the sheet; it closes when done, or stays to say the Keychain item is left.
    private func signOut(_ account: AccountRef) {
        signOutPhase = .signingOut
        Task {
            let removed = await model.signOut(account)
            if removed {
                signOutTarget = nil
                signOutPhase = .confirming
            } else {
                signOutPhase = .keychainFailed
            }
        }
    }
}

private struct BoardsKey: Equatable {
    let account: AccountRef?
    let owner: BoardOwner?
    let canRead: Bool
}

/// A setting's title with an optional secondary line, as in the Settings artboard.
struct RowLabel: View {
    let title: String
    let note: String?
    let isWarning: Bool

    init(_ title: String, note: String? = nil, isWarning: Bool = false) {
        self.title = title
        self.note = note
        self.isWarning = isWarning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            if let note {
                HStack(spacing: 3) {
                    if isWarning {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Text(note)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Sets the hosting window's title; the Settings scene leaves it empty.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    init(_ title: String) { self.title = title }

    func makeNSView(context: Context) -> NSView { TitleView(title) }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class TitleView: NSView {
        let title: String

        init(_ title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            window?.title = title
        }
    }
}
