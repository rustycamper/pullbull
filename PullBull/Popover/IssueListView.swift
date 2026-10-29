import AppKit
import SwiftUI
import PullBullKit

/// The scrollable list for one Issues tab: its groups (Status columns, Not on board, or repos), an
/// empty state, and the folded "Done" group (Board: the last 14 days; Assigned: still open).
struct IssueListView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var compact: Bool { model.settings.compact }
    let tab: IssueTab
    let scoped: ScopedIssueTab
    /// Every issue of the tab, in any repository, Done included.
    let total: Int
    let now: Date
    @Binding var doneExpanded: Bool

    private var contents: IssueTabContents { scoped.contents }
    private var focus: RepoFocus? { model.repoFocus }
    private var listed: [IssueGroup] { contents.groups.filter { $0.kind != .done } }
    private var done: IssueGroup? { contents.groups.first { $0.kind == .done } }
    /// Board and Assigned lanes folded to their header; none while a search is active.
    private var foldedLanes: Set<IssueGroupKind> { model.foldedLanes(listed, on: tab) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                list
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.listSelection) { _, key in
                guard let key else { return }
                proxy.scrollTo(key)
            }
        }
    }

    /// Board folds what was done lately; Assigned folds what is done on the board but still open.
    private var doneNote: String { tab == .assigned ? "still open" : "last 14 days" }

    private var list: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if listed.isEmpty {
                Group {
                    if let focus, total > contents.issues.count {
                        FocusedEmptyView(
                            model: model, repoName: model.displayName(of: focus.repo), tabTitle: tab.title, hiddenCount: scoped.hiddenCount)
                    } else {
                        IssueEmptyView(model: model, tab: tab, now: now)
                    }
                }
                .frame(height: done == nil ? 400 : 260)
            } else {
                let folded = foldedLanes
                ForEach(listed) { group in
                    // Under a focus the kit merges repo groups into one untitled group.
                    if group.title.isEmpty {
                        Color.clear.frame(height: 6)
                        // No header pins above it, so there is none to clear.
                        rows(group.issues, inRepoGroup: group.isRepo, clearance: 0)
                    } else {
                        Section {
                            if !folded.contains(group.kind) {
                                rows(group.issues, inRepoGroup: group.isRepo)
                            }
                        } header: {
                            IssueGroupHeader(
                                model: model, group: group,
                                fold: foldState(group, folded: folded)
                            ) {
                                model.toggleLane(group.kind, on: tab, doneExpanded: doneExpanded)
                            }
                            .pinnedHeaderBackground()
                        }
                    }
                }
                if scoped.hiddenCount > 0 {
                    OtherReposLine(model: model, count: scoped.hiddenCount)
                }
            }
            if let done {
                doneSection(done)
            }
        }
        .padding(.horizontal, Metrics.rowInset)
        .padding(.bottom, 6)
    }

    /// Only lanes fold here (Status, No status, Not on board); nil for repo headers.
    private func foldState(_ group: IssueGroup, folded: Set<IssueGroupKind>) -> IssueGroupHeader.Fold? {
        guard model.settings.board != nil, LaneFolds.laneID(group.kind) != nil else { return nil }
        return folded.contains(group.kind) ? .folded : .open
    }

    private func rows(
        _ issues: [BoardIssue], inRepoGroup: Bool = false, clearance: CGFloat = PinnedHeader.clearance
    ) -> some View {
        let wantedLabels = model.searchQuery.labels
        return ForEach(issues) { issue in
            IssueRow(model: model, issue: issue, tab: tab, now: now, selected: model.listSelection == issue.key,
                     inRepoGroup: inRepoGroup || focus != nil, wantedLabels: wantedLabels)
                .scrollTarget(issue.key, clearance: clearance)
        }
    }

    private func doneSection(_ group: IssueGroup) -> some View {
        Section {
            if doneExpanded {
                rows(group.issues)
            }
        } header: {
            doneHeader(group)
                .pinnedHeaderBackground()
        }
    }

    private func doneHeader(_ group: IssueGroup) -> some View {
        Button {
            doneExpanded.toggle()
        } label: {
            // Laid out like a lane header: the chevron hangs in the leading inset, the checkmark sits in
            // the rows' icon column and the title on the row title edge.
            HStack(spacing: compact ? 8 : 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: compact ? 10 : 11))
                    .frame(width: compact ? 16 : 20)
                HStack(spacing: 6) {
                    Text("Done")
                    Text("\(group.issues.count)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                    Text("· \(doneNote)")
                        .fontWeight(.regular)
                }
                Spacer(minLength: 0)
            }
            .overlay(alignment: .leading) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(doneExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: doneExpanded)
                    .frame(width: 8)
                    .offset(x: -8)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel("Done, \(group.issues.count), \(doneNote)")
        .accessibilityValue(doneExpanded ? "expanded" : "collapsed")
    }
}

private extension IssueGroup {
    /// A repo group, whose header names the repo its rows are in.
    var isRepo: Bool {
        if case .repo = kind { return true }
        return false
    }
}

private struct IssueGroupHeader: View {
    let model: AppModel
    let group: IssueGroup
    /// A lane's fold; nil for headers that don't fold.
    var fold: Fold? = nil
    var onToggle: () -> Void = {}

    enum Fold { case open, folded }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Only a repo group's header offers the repo focus.
    private var focusItem: FocusMenuItem? {
        guard case .repo(let repo) = group.kind else { return nil }
        return FocusMenuItem(model: model, repo: repo)
    }

    private var compact: Bool { model.settings.compact }

    var body: some View {
        if let fold {
            // The whole header toggles, like Done's; the chevron hangs in the leading inset, left of the
            // icon column, so the glyph and title keep their columns.
            Button(action: onToggle) {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(fold == .open ? 90 : 0))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: fold == .open)
                            .frame(width: 8)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)
            .accessibilityValue(fold == .open ? "expanded" : "collapsed")
            .accessibilityAddTraits(.isHeader)
            .focusContextMenu(focusItem)
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .focusContextMenu(focusItem)
        }
    }

    private var accessibilityTitle: String {
        group.counted ? "\(group.title), \(group.issues.count)" : group.title
    }

    /// The glyph sits in the rows' icon column, so header and row circles share one axis and the title
    /// starts on the row titles' edge. At 11pt the SF circle matches the 13pt issue glyph's diameter.
    private var label: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 10 : 11))
                .foregroundStyle(symbolColor)
                .frame(width: compact ? 16 : 20)
            HStack(spacing: 6) {
                Text(group.title)
                if group.counted {
                    Text("\(group.issues.count)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }

    /// Status lanes take the owner's Status colour; the colour is decorative, the title names the status.
    private var symbolColor: Color {
        guard case .status(let option) = group.kind, let color = option.color else { return .secondary }
        return Palette.statusOptionColor(color)
    }

    private var symbol: String {
        switch group.kind {
        case .status(let option): return BoardStatusGlyph.symbol(forStatusNamed: option.name)
        case .noStatus: return "circle.dotted"
        case .notOnBoard: return BoardStatusGlyph.notOnBoard
        case .repo: return "book.closed"
        case .all: return "list.bullet"
        case .done: return "checkmark.circle"
        }
    }
}

/// An Issues tab with nothing to list, or the Assigned and Created lists that never loaded.
private struct IssueEmptyView: View {
    @Bindable var model: AppModel
    let tab: IssueTab
    let now: Date

    /// " in <org>"; empty in no-org mode, where the lists cover any repo.
    private var inOrg: String { model.settings.org.map { " in \($0)" } ?? "" }
    private var login: String { model.snapshot?.org.viewer ?? model.settings.account ?? "you" }
    private var boardTitle: String { model.snapshot?.boardTitle ?? "Board" }
    /// This tab's issue search failed; an empty Assigned or Created list may just not have loaded.
    private var loadError: String? { model.snapshot?.issuesError(for: tab) }

    var body: some View {
        ListStateView(
            symbol: loadError == nil ? "pullbull.issue" : "exclamationmark.triangle",
            tone: loadError == nil ? .neutral : .warning, title: title, detail: subtitle, action: action)
    }

    private var action: ListStateView<EmptyView>.Action? {
        if loadError != nil {
            return .init(title: "Retry", help: "Retry (⌘R)", disabled: model.status.isRefreshing) { model.refresh() }
        }
        if tab == .assigned, model.settings.org != nil {
            return .init(title: "Browse \(boardTitle)", symbol: "rectangle.split.3x1") { model.selectedIssueTab = .board }
        }
        return nil
    }

    private var title: String {
        if loadError != nil { return "Issues couldn't load" }
        switch tab {
        case .assigned: return "No issues assigned to you"
        case .created: return "No open issues you created"
        case .board: return "No open issues on \(boardTitle)"
        }
    }

    private var subtitle: String? {
        if let loadError { return loadError }
        if tab == .assigned, let cleared = model.assignedCleared.clearedAt {
            return ClearedTracker.subtitle(clearedAt: cleared, now: now)
        }
        switch tab {
        case .assigned: return "Open issues\(inOrg) assigned to \(login) show up here."
        case .created: return "Open issues you opened\(inOrg) show up here."
        case .board: return nil
        }
    }
}

/// Assigned or Created before its search has ever succeeded for this account and org (including a
/// cache from before the Issues mode): skeleton rows while a refresh runs, else why it failed, with Retry.
/// Never the empty state, which would claim there are no issues.
struct IssueListNotLoadedView: View {
    @Bindable var model: AppModel
    let tab: IssueTab

    private var error: String? {
        guard !model.status.isRefreshing else { return nil }
        return model.snapshot?.issuesError(for: tab) ?? model.status.error.map(model.message(for:))
    }

    var body: some View {
        Group {
            if let error {
                ListStateView(
                    symbol: model.status.error == .offline ? "wifi.slash" : "exclamationmark.triangle", tone: .warning,
                    title: "Issues couldn't load", detail: error,
                    action: .init(title: "Retry", help: "Retry (⌘R)") { model.refresh() })
            } else {
                SkeletonList.issues(model, tab: tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Board while its items are not available: no-org mode without board access (personal boards need a
/// GitHub CLI login with the project scope), a missing project scope, another board error, or no board
/// chosen.
struct BoardUnavailableView: View {
    @Bindable var model: AppModel
    @State private var copied = false

    private var boardTitle: String { model.snapshot?.boardTitle ?? "Board" }
    private var login: String? { model.snapshot?.org.viewer ?? model.settings.account }
    private var missingScope: Bool {
        !model.canReadProjects || model.snapshot?.boardError == RefreshError(APIError.insufficientScopes).message
    }
    /// An app account: access comes from the org's grant to PullBull, not from a `gh` scope.
    private var isAppAccount: Bool { model.settings.accountRef?.source == .gitHubApp }

    var body: some View {
        Group {
            // While Check again runs the scopes may already be back but the board not yet fetched; keep this
            // screen (and its Checking… button) until the refresh settles it.
            if let access = model.personalBoardAccess, access != .ready {
                personalBody(access)
            } else if missingScope || model.checkingAccess {
                scopeBody
            } else if let error = model.snapshot?.boardError {
                errorBody(error)
            } else if model.settings.board != nil {
                SkeletonList.issues(model, tab: .board)
            } else if case .loaded(let boards) = model.boardListState, boards.isEmpty,
                      let owner = model.settings.boardOwner {
                placeholder("No Projects boards for \(owner.login)")
            } else {
                placeholder("No board chosen", detail: "Pick one from the menu above.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ title: String, detail: String? = nil) -> some View {
        ListStateView(symbol: "rectangle.split.3x1", title: title, detail: detail)
    }

    /// No-org mode: GitHub gives apps no access to personal boards, so the board needs a GitHub CLI login
    /// with the project scope. Set Up GitHub CLI… opens the checklist for this login, or one click
    /// switches to it when GitHub CLI already has it. Never an empty board or "not found".
    private func personalBody(_ access: PersonalBoardAccess) -> some View {
        let login = model.settings.account ?? "you"
        return VStack(spacing: 0) {
            Image(systemName: "lock")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text(isAppAccount ? "Personal boards need a GitHub CLI login" : "Needs the read:project scope")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Group {
                switch access {
                case .useGhLogin(let ghLogin):
                    Text("GitHub doesn't let PullBull's own sign-in read them. GitHub CLI has \(ghLogin) with "
                        + "board access.")
                case .addScope, .logIn, .ready:
                    Text(isAppAccount
                        ? "GitHub doesn't let PullBull's own sign-in read them. A GitHub CLI login for \(login) can."
                        : "GitHub CLI's login for \(login) can't read Projects boards yet.")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
            personalAction(access)
                .padding(.top, 14)
            Text("Assigned and Created still work.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    @ViewBuilder private func personalAction(_ access: PersonalBoardAccess) -> some View {
        if case .useGhLogin(let ghLogin) = access {
            let use = model.ghUse
            let using = use != nil && use?.failure == nil
            VStack(spacing: 6) {
                Button {
                    Task { await model.useGhLogin(ghLogin, personal: true) }
                } label: {
                    Label(using ? FirstRunChoice.usingTitle(ghLogin) : FirstRunChoice.useTitle(ghLogin),
                          systemImage: "terminal")
                }
                .buttonStyle(IssueStateButtonStyle())
                .disabled(using)
                if let use, let failure = use.failure, use.login == ghLogin {
                    Text(FirstRunChoice.failure(ghLogin, message: failure))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Button {
                guard let login = model.settings.account else { return }
                GhSetupWindowController.shared.show(app: model, purpose: .board(login: login))
            } label: {
                Label("Set Up GitHub CLI…", systemImage: "terminal")
            }
            .buttonStyle(IssueStateButtonStyle())
        }
    }

    private var scopeBody: some View {
        VStack(spacing: 0) {
            Image(systemName: "lock")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text("\(boardTitle) needs project access")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            accessHint
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if !isAppAccount {
                commandBox(model.addProjectScopeCommand)
                    .padding(.top, 14)
            }
            Button {
                Task {
                    if isAppAccount { await model.checkOrgAccessAgain() } else { await model.checkAccessAgain() }
                }
            } label: {
                Label(model.checkingAccess ? "Checking…" : "Check again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(IssueStateButtonStyle())
            .disabled(model.checkingAccess || model.status.isRefreshing)
            .padding(.top, 14)
            Text("Assigned and Created still work. Board status is hidden until access is granted.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private var accessHint: Text {
        if isAppAccount {
            let org = model.settings.org ?? "the organization"
            return Text("An owner of \(org) needs to accept PullBull's Projects permission. Then check again.")
        }
        return Text("The gh token\(login.map { " for \($0)" } ?? "") is missing the ")
            + Text("read:project").font(.system(size: 11, design: .monospaced))
            + Text(" scope. Run this in Terminal, then refresh.")
    }

    /// The command to run; a click anywhere on it copies it.
    private func commandBox(_ command: String) -> some View {
        Button { copy(command) } label: {
            HStack(spacing: 8) {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.fill))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy command")
        .accessibilityLabel("Copy command: \(command)")
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func errorBody(_ error: String) -> some View {
        ListStateView(
            symbol: "exclamationmark.triangle", tone: .warning, title: "\(boardTitle) couldn't load", detail: error,
            action: .init(title: "Retry", help: "Retry (⌘R)", disabled: model.status.isRefreshing) { model.refresh() })
    }
}
