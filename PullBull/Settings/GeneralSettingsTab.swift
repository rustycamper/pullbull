import AppKit
import PullBullKit
import SwiftUI

/// How PullBull shows and refreshes its lists, plus the app-level rows.
struct GeneralSettingsTab: View {
    @Bindable var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemNote: String?
    private let updater = Updater.shared
    /// Owned by `SettingsView`, which stops it when the tab changes.
    let shortcutRecorder: KeyRecorder

    private static let refreshChoices = [1, 2, 5, 10]
    private static let activityRefreshNote = "Also refreshes on new activity, and on open if data is older than 30s"

    /// Names new activity only while the activity check works for this sign-in.
    private var refreshNote: String {
        model.status.activity == .active
            ? Self.activityRefreshNote : "Also refreshes on open if data is older than 30s"
    }

    var body: some View {
        Form {
            overviewSection
            filtersSection
            menuBarSection
            appSection
        }
        .formStyle(.grouped)
        .settingsTabHeight()
        .onAppear { syncLaunchAtLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncLaunchAtLogin()
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            Picker(selection: $model.settings.grouping) {
                Text("Repository").tag(Grouping.repository)
                Text("None").tag(Grouping.none)
            } label: {
                RowLabel("Group pull requests and created issues by", note: "Assigned and Board group by board Status")
            }
            .pickerStyle(.segmented)
            Toggle(isOn: $model.settings.groupTeamByAuthor) {
                RowLabel("Group Team by author", note: "Team only; other lists follow the setting above")
            }
            Toggle(isOn: $model.settings.reviewOldestFirst) {
                RowLabel("Oldest review request first", note: "By when each pull request was opened")
            }
            Toggle(isOn: $model.settings.compact) {
                RowLabel("Compact cards", note: "One line per pull request or issue")
            }
            Toggle(isOn: $model.settings.solidBackground) {
                RowLabel("Solid background", note: "Hide what’s behind the popover")
            }
        }
    }

    private var filtersSection: some View {
        Section {
            Toggle("Hide pull requests older than 2 months", isOn: $model.settings.hideOlderThanTwoMonths)
            Toggle(isOn: $model.settings.hideApprovedByMe) {
                RowLabel("Hide pull requests I’ve approved",
                         note: "When off, they stay in Review dimmed and are not counted")
            }
            Toggle("Hide drafts", isOn: $model.settings.hideDrafts)
        } header: {
            Text("Filters · Review and Team")
        }
    }

    private var menuBarSection: some View {
        Section("Menu bar") {
            Picker(selection: $model.settings.badge) {
                Text("Needs my review").tag(BadgeSource.review)
                Text("Mine").tag(BadgeSource.mine)
                Text("Review + Mine").tag(BadgeSource.reviewAndMine)
                Text("All").tag(BadgeSource.all)
            } label: {
                RowLabel("Count shows", note: "The badge uses the same filters as the tab it counts")
            }
            Toggle(isOn: $model.settings.countAssignedIssues) {
                RowLabel("Also count assigned issues", note: "Adds open issues assigned to you")
            }
        }
    }

    private var appSection: some View {
        Section("App") {
            Picker(selection: $model.settings.refreshMinutes) {
                ForEach(Self.refreshChoices, id: \.self) { minutes in
                    Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                }
            } label: {
                // The longer note reserves its height, so the row doesn't move when the check turns on.
                RowLabel("Refresh every", note: Self.activityRefreshNote)
                    .hidden()
                    .overlay(alignment: .topLeading) { RowLabel("Refresh every", note: refreshNote) }
            }
            Toggle(isOn: $model.settings.followPendingCI) {
                RowLabel("Check my pending CI more often",
                         note: "Every 30 s while checks run on up to 5 of your pull requests")
            }
            LabeledContent {
                ShortcutRecorderField(
                    recorder: shortcutRecorder, combo: model.settings.toggleHotkey,
                    onRecord: setToggleShortcut, onClear: { setToggleShortcut(nil) })
            } label: {
                let warning = shortcutRecorder.hint ?? GlobalHotkey.shared.error
                RowLabel("Toggle PullBull", note: warning ?? "Shows or hides PullBull from any app",
                         isWarning: warning != nil)
            }
            if LaunchAtLogin.isInstalled {
                Toggle(isOn: launchAtLoginBinding) {
                    RowLabel("Launch at login", note: loginItemNote, isWarning: LaunchAtLogin.lastError != nil)
                }
            } else {
                // Only the switch is disabled, so the caption isn't dimmed below `.secondary`.
                LabeledContent {
                    Toggle("Launch at login", isOn: .constant(launchAtLogin))
                        .labelsHidden()
                        .disabled(true)
                } label: {
                    RowLabel("Launch at login", note: "Move PullBull to Applications to launch at login")
                }
            }
            LabeledContent {
                HStack {
                    if updater.isAvailable {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                            .disabled(!updater.canCheckForUpdates)
                    }
                    Button("Quit PullBull") { NSApp.terminate(nil) }
                }
            } label: {
                Text("PullBull \(BuildInfo.version)\(BuildInfo.isLocalBuild ? " · local build" : "")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                LaunchAtLogin.isEnabled = enabled
                syncLaunchAtLogin()
            })
    }

    /// Saves the shortcut only once it is registered; on failure the previous one stays and the row
    /// shows why.
    private func setToggleShortcut(_ combo: KeyCombo?) {
        if GlobalHotkey.shared.apply(combo) { model.settings.toggleHotkey = combo }
    }

    private func syncLaunchAtLogin() {
        launchAtLogin = LaunchAtLogin.isEnabled
        if let error = LaunchAtLogin.lastError {
            loginItemNote = error
        } else if LaunchAtLogin.needsApproval {
            loginItemNote = "Allow PullBull in System Settings › General › Login Items"
        } else {
            loginItemNote = nil
        }
    }
}
