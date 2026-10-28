import AppKit
import PullBullKit
import SwiftUI

/// Which events post a banner, and a pointer to System Settings when macOS has notifications off.
struct NotificationSettingsTab: View {
    @Bindable var model: AppModel
    let permission: NotificationPermission

    var body: some View {
        Form {
            Section("Notifications") {
                if permission.state == .denied { notificationsOffRow }
                notificationToggles
                    .disabled(permission.state == .denied)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        // It always fits; without this a scroller can flash in after the window resizes for this tab.
        .scrollDisabled(true)
    }

    private var notificationsOffRow: some View {
        LabeledContent {
            Button("Open System Settings…") { NSWorkspace.shared.open(NotificationPermission.systemSettingsURL) }
        } label: {
            Label("Notifications are off for PullBull in System Settings", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder private var notificationToggles: some View {
        Group {
            Toggle("Review requested from me", isOn: $model.settings.notify.reviewRequested)
            Toggle("My pull request approved", isOn: $model.settings.notify.approved)
            Toggle("Changes requested on my pull request", isOn: $model.settings.notify.changesRequested)
            Toggle("CI failed on my pull request", isOn: $model.settings.notify.ciFailed)
            Toggle("New comment on my pull request", isOn: $model.settings.notify.newComment)
            Toggle(isOn: $model.settings.notify.merged) {
                RowLabel("My pull request merged", note: "When someone else merges it")
            }
            Toggle(isOn: $model.settings.notify.issueAssigned) {
                RowLabel("Issue assigned to me", note: issueAssignedNote)
            }
        }
    }

    private var issueAssignedNote: String {
        if model.settings.account != nil, model.settings.org == nil { return "When someone else assigns you, any repo" }
        return "When someone else assigns you, any repo in \(model.snapshot?.scope.org ?? model.settings.org ?? "your organization")"
    }
}
