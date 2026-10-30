import AppKit
import SwiftUI
import PullBullKit

/// The PR and issue actions shared by the row context menus and the detail views.
enum PRActions {
    static func copyBranch(_ pr: PullRequest) {
        copy(pr.headRef)
    }

    static func copyLink(_ pr: PullRequest) {
        copy(pr.url.absoluteString)
    }

    /// Whether the click being handled held ⌘: a ⌘-click on a row opens its page on GitHub instead of
    /// its detail, as ⌘↩ does. Only a mouse click counts: `currentEvent` outlives its dispatch, so a
    /// VoiceOver or keyboard press could otherwise read an earlier ⌘ shortcut's key event.
    @MainActor static var commandClicked: Bool {
        guard let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown else {
            return false
        }
        return event.modifierFlags.contains(.command)
    }

    static func openOnGitHub(_ pr: PullRequest) {
        NSWorkspace.shared.open(pr.url)
    }

    static func copyLink(_ issue: BoardIssue) {
        copy(issue.url.absoluteString)
    }

    static func openOnGitHub(_ issue: BoardIssue) {
        NSWorkspace.shared.open(issue.url)
    }

    @MainActor static func copyMarkdownLink(_ pr: PullRequest) {
        copyMarkdownLink(title: pr.title, key: pr.key, url: pr.url)
    }

    @MainActor static func copyMarkdownLink(_ issue: BoardIssue) {
        copyMarkdownLink(title: issue.title, key: issue.key, url: issue.url)
    }

    /// ⌥⌘C: the Markdown link as text, and the page as a URL for the apps that take one; then the quiet
    /// "Copied" where the popover shows it.
    @MainActor static func copyMarkdownLink(title: String?, key: PRKey, url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MarkdownLink.item(title: title, key: key, url: url), forType: .string)
        pasteboard.setString(url.absoluteString, forType: .URL)
        CopyConfirmation.shared.show("Copied Markdown link")
    }

    /// `gh pr checkout N -R owner/repo`, then the quiet "Copied" where the popover shows it.
    @MainActor static func copyCheckoutCommand(_ key: PRKey) {
        copy(CheckoutCommand.text(for: key))
        CopyConfirmation.shared.show("Copied checkout command")
    }

    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

/// The repo focus item at the top of a list row's or repo header's context menu: "Show Only <name>",
/// or "Show All Repositories" on the focused repository.
struct FocusMenuItem {
    let title: String
    let action: () -> Void
}

extension FocusMenuItem {
    /// Choosing it focuses `repo` (`owner/name`), or clears the focus when `repo` is the one focused.
    @MainActor init(model: AppModel, repo: String) {
        let focused = model.repoFocus?.repo.caseInsensitiveCompare(repo) == .orderedSame
        self.init(title: focused ? "Show All Repositories" : "Show Only \(model.displayName(of: repo))") {
            model.focus(on: focused ? nil : repo)
        }
    }
}

extension FocusMenuItem {
    /// "Search @login" on a list row: searches for everything `login` is on. Nil for a missing author
    /// and for GitHub's deleted-account placeholder, "ghost".
    @MainActor static func person(model: AppModel, login: String?) -> FocusMenuItem? {
        guard let login, login.caseInsensitiveCompare("ghost") != .orderedSame else { return nil }
        return FocusMenuItem(title: "Search @\(login)") { model.searchForPerson(login) }
    }
}

extension View {
    /// Right-click: the repo focus and person search items (list and search rows), Copy Branch Name, Copy
    /// Checkout Command, Copy Link, Copy as Markdown Link, Open on GitHub, the files item (`files.menuTitle`)
    /// and, on a PR whose checks failed, Open Failing Check. VoiceOver gets Copy as Markdown Link as an
    /// action too.
    func prContextMenu(
        _ pr: PullRequest, focus: FocusMenuItem? = nil, time: TimeFocusMenu? = nil, person: FocusMenuItem? = nil,
        files: FilesLink? = nil, failingCheck: (() -> Void)? = nil
    ) -> some View {
        contextMenu {
            if focus != nil || time != nil || person != nil {
                if let focus { FocusMenuButton(item: focus) }
                if let time { time }
                if let person { PersonMenuButton(item: person) }
                Divider()
            }
            Button("Copy Branch Name", systemImage: "arrow.triangle.branch") { PRActions.copyBranch(pr) }
            Button("Copy Checkout Command", systemImage: "terminal") { PRActions.copyCheckoutCommand(pr.key) }
            Button("Copy Link", systemImage: "link") { PRActions.copyLink(pr) }
            Button("Copy as Markdown Link", systemImage: "link.badge.plus") { PRActions.copyMarkdownLink(pr) }
            Divider()
            Button("Open on GitHub", systemImage: "arrow.up.right.square") { PRActions.openOnGitHub(pr) }
            if let files {
                Button(files.menuTitle, systemImage: "doc.text.magnifyingglass") { NSWorkspace.shared.open(files.url) }
            }
            if pr.ci == .failure, let failingCheck {
                Button("Open Failing Check", systemImage: "xmark.octagon", action: failingCheck)
            }
        }
        .accessibilityAction(named: "Copy as Markdown Link") { PRActions.copyMarkdownLink(pr) }
    }

    /// Right-click on an issue: the repo focus and person search items (list and search rows), Copy Link,
    /// Copy as Markdown Link, Open on GitHub. VoiceOver gets Copy as Markdown Link as an action too.
    func issueContextMenu(
        _ issue: BoardIssue, focus: FocusMenuItem? = nil, time: TimeFocusMenu? = nil, person: FocusMenuItem? = nil
    ) -> some View {
        contextMenu {
            if focus != nil || time != nil || person != nil {
                if let focus { FocusMenuButton(item: focus) }
                if let time { time }
                if let person { PersonMenuButton(item: person) }
                Divider()
            }
            Button("Copy Link", systemImage: "link") { PRActions.copyLink(issue) }
            Button("Copy as Markdown Link", systemImage: "link.badge.plus") { PRActions.copyMarkdownLink(issue) }
            Divider()
            Button("Open on GitHub", systemImage: "arrow.up.right.square") { PRActions.openOnGitHub(issue) }
        }
        .accessibilityAction(named: "Copy as Markdown Link") { PRActions.copyMarkdownLink(issue) }
    }

    /// Right-click on a repo group header or a list's background: the repo focus and Show Only Updated
    /// items; no menu without either.
    @ViewBuilder func focusContextMenu(_ focus: FocusMenuItem? = nil, time: TimeFocusMenu? = nil) -> some View {
        if focus != nil || time != nil {
            contextMenu {
                if let focus { FocusMenuButton(item: focus) }
                if let time { time }
            }
        } else {
            self
        }
    }
}

/// "Show Only Updated" on a list's context menus: the four steps with a checkmark on the active one,
/// and Show All while a time focus is on. Search rows don't offer it.
struct TimeFocusMenu: View {
    let model: AppModel

    var body: some View {
        Menu("Show Only Updated", systemImage: "clock") {
            ForEach(TimeStep.allCases, id: \.self) { step in
                Toggle(step.menuTitle, isOn: Binding(
                    get: { model.timeFocus?.step == step },
                    set: { _ in model.focus(time: step) }))
            }
            if model.timeFocus != nil {
                Divider()
                Button("Show All") { model.focus(time: nil) }
            }
        }
    }
}

private struct FocusMenuButton: View {
    let item: FocusMenuItem

    var body: some View {
        Button(item.title, systemImage: "line.3.horizontal.decrease", action: item.action)
    }
}

private struct PersonMenuButton: View {
    let item: FocusMenuItem

    var body: some View {
        Button(item.title, systemImage: "person", action: item.action)
    }
}
