import AppKit
import PullBullKit
import SwiftUI

/// Which events post a banner, grouped by how the pull request or issue is mine, and a pointer to System
/// Settings when macOS has notifications off.
struct NotificationSettingsTab: View {
    @Bindable var model: AppModel
    let permission: NotificationPermission

    var body: some View {
        Form {
            if permission.state == .denied {
                Section { notificationsOffRow }
            }
            Group {
                Section("My pull requests") {
                    Toggle("Approved", isOn: $model.settings.notify.approved)
                    Toggle("Changes requested", isOn: $model.settings.notify.changesRequested)
                    Toggle("CI failed", isOn: $model.settings.notify.ciFailed)
                    Toggle("New comment", isOn: $model.settings.notify.newComment)
                    Toggle(isOn: $model.settings.notify.readyToMerge) {
                        RowLabel("Ready to merge", note: "Approved, checks green, no conflicts")
                    }
                    Toggle(isOn: $model.settings.notify.merged) {
                        RowLabel("Merged", note: "When someone else merges it")
                    }
                }
                Section("Pull requests I review") {
                    Toggle(isOn: $model.settings.notify.reviewRequested) {
                        RowLabel("Review requested", note: "Also re-requests, and new commits since your review")
                    }
                    Toggle(isOn: $model.settings.notify.commentAfterMyReview) {
                        RowLabel("New comment", note: "On a pull request you reviewed")
                    }
                }
                Section("Issues assigned to me") {
                    Toggle(isOn: $model.settings.notify.issueAssigned) {
                        RowLabel("Newly assigned", note: issueAssignedNote)
                    }
                    Toggle("New comment", isOn: $model.settings.notify.assignedIssueComment)
                    Toggle(isOn: $model.settings.notify.assignedIssueStatus) {
                        RowLabel("Status changed", note: statusNote)
                    }
                    Toggle("Closed or reopened", isOn: $model.settings.notify.assignedIssueClosed)
                }
                Section("Issues I created") {
                    Toggle("New comment", isOn: $model.settings.notify.createdIssueComment)
                    Toggle(isOn: $model.settings.notify.createdIssueStatus) {
                        RowLabel("Status changed", note: statusNote)
                    }
                    Toggle("Closed or reopened", isOn: $model.settings.notify.createdIssueClosed)
                }
            }
            .disabled(permission.state == .denied)
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

    /// Status moves count only on the board the Board tab shows.
    private var statusNote: String {
        guard let title = model.snapshot?.boardTitle else { return "On the board shown on the Board tab" }
        return "On \(title)"
    }

    private var issueAssignedNote: String {
        if model.settings.account != nil, model.settings.org == nil { return "When someone else assigns you, any repo" }
        return "When someone else assigns you, any repo in \(model.snapshot?.scope.org ?? model.settings.org ?? "your organization")"
    }
}
