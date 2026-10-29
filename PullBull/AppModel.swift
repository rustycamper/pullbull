import AppKit
import Foundation
import Network
import Observation
import PullBullKit

enum Route: Equatable {
    case list, search, ask, detail(PRKey), issueDetail(PRKey)
}

/// A tab in either mode, such as the one type-anywhere started a search on.
enum ShownTab: Hashable {
    case pullRequests(PRTab)
    case issues(IssueTab)

    var title: String {
        switch self {
        case .pullRequests(let tab): tab.title
        case .issues(let tab): tab.title
        }
    }
}

extension SearchScope {
    /// The search narrowed to `tab`.
    init(_ tab: ShownTab) {
        switch tab {
        case .pullRequests(let tab): self = .pullRequests(tab)
        case .issues(let tab): self = .issues(tab)
        }
    }
}

@Observable @MainActor
final class AppModel {
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            var reconciled = settings
            let boardCleared = reconciled.reconcileBoard()
            reconciled.rememberOrg()
            reconciled.reconcileTab()
            if reconciled != settings { settings = reconciled }
            settingsStore.save(settings)
            if selectedTab != settings.lastTab { selectedTab = settings.lastTab }
            if mode != settings.mode { mode = settings.mode }
            if selectedIssueTab != settings.lastIssueTab { selectedIssueTab = settings.lastIssueTab }
            rebuildTabs()
            rebuildOrgAccess()
            checkInstallationsIfUnknown()
            startCoordinatorIfNeeded()
            if boardCleared { pickFirstBoard() }
        }
    }

    private(set) var snapshot: Snapshot?
    private(set) var tabs: BuiltTabs? {
        didSet { refreshRepoChoices() }
    }
    /// The Issues tabs, built from the same snapshot as `tabs`.
    private(set) var issueTabs: BuiltIssueTabs? {
        didSet { refreshRepoChoices() }
    }
    private(set) var status = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false)
    /// Review PRs hidden because "hide PRs I've approved" is on.
    private(set) var hiddenApprovedCount = 0
    /// When Review, and Assigned, last went from some items to none during this session.
    private(set) var reviewCleared = ClearedTracker(since: Date())
    private(set) var assignedCleared = ClearedTracker(since: Date())

    var selectedTab: PRTab {
        didSet { if settings.lastTab != selectedTab { settings.lastTab = selectedTab } }
    }
    /// Pull Requests or Issues; remembered across launches, as is the tab of each mode.
    var mode: PopoverMode {
        didSet {
            if settings.mode != mode { settings.mode = mode }
            guard mode != oldValue else { return }
            // The other mode's tabs don't narrow this mode's search.
            let wasNarrowed = searchScope.isNarrowed
            searchScope = .everything
            // Type-anywhere's tab is no way back from the other mode: Esc then clears as usual.
            if let tab = searchStartedOnTab, SearchScope(tab).mode != mode { searchStartedOnTab = nil }
            // An open search stays and shows this mode's results: a narrowed one held only the tab's
            // items, so it searches everything again.
            guard route == .search, let results = searchResults else { return }
            if wasNarrowed { runSearch(searchQuery, debounced: false) } else { setSearchResults(results) }
        }
    }
    var selectedIssueTab: IssueTab {
        didSet { if settings.lastIssueTab != selectedIssueTab { settings.lastIssueTab = selectedIssueTab } }
    }
    /// The tab showing in the current mode.
    var shownTab: ShownTab {
        switch mode {
        case .pullRequests: .pullRequests(selectedTab)
        case .issues: .issues(selectedIssueTab)
        }
    }
    var route: Route = .list
    /// The repository every list and search is narrowed to; counts, the badge and notifications ignore
    /// it. Never persisted. A selection the new focus hides is dropped, and search results on screen are
    /// searched again.
    private(set) var repoFocus: RepoFocus? {
        didSet {
            guard repoFocus != oldValue else { return }
            refreshRepoChoices()
            listSelections = listSelections.filter { tab, key in
                navigationKeys(for: tab, closedExpanded: true, doneExpanded: true).contains(key)
            }
            if route == .search { runSearch(searchQuery, debounced: false) }
        }
    }
    /// The field's text, its "@user", "~label" or "is:" completion and the query searched for
    /// (`SearchFieldState`).
    private var searchField = SearchFieldState()
    var searchText: String { searchField.text }
    /// The query last searched for: `searchText` parsed, without the token being completed.
    var searchQuery: SearchQuery { searchField.query }
    /// Everyone the current snapshot can name; completion candidates come from here.
    private(set) var people: PeopleIndex = .empty
    /// Every label the current snapshot holds; "~label" candidates come from here.
    private(set) var labels: LabelIndex = .empty
    /// The selected board's Status columns; "status:" candidates come from here.
    private(set) var statuses: StatusIndex = .empty
    /// The open "@user", "~label", "is:" or "status:" completion; nil when no token ends at the caret or the user closed it.
    var completion: SearchCompletion? { searchField.searchCompletion }
    /// Bumped to ask the search field to take focus.
    private(set) var searchFieldFocusRequest = 0
    /// Results for `searchText`; nil when the text is empty or there is no snapshot to search yet.
    private(set) var searchResults: SearchResults?
    /// The tab that was showing when typing anywhere opened the search; nil when opened another way.
    private(set) var searchStartedOnTab: ShownTab?
    /// The tab a search is narrowed to by clicking it; `.everything` until then, and again once the field
    /// is cleared. Read `shownSearchScope`, which drops a tab the current mode doesn't show.
    private var searchScope: SearchScope = .everything
    /// Each tab's matches for `searchQuery` (`SearchNarrowing.counts`), kept until the query, the focus
    /// or the lists change; empty without a query.
    private(set) var searchMatchCounts: [SearchScope: IssueTabCount] = [:]
    /// The highlighted result (Return opens it).
    var searchSelection: PRKey?
    /// The highlighted row of each list tab (↑/↓; Return opens it), kept while switching tabs.
    private(set) var listSelections: [ShownTab: PRKey] = [:]
    /// The list or search row chosen to open, highlighted for a moment before its detail opens.
    private(set) var rowFlash = RowFlash<RowFlashContext>()
    /// Counts the popover's openings, so a row chosen before a close and reopen doesn't open later.
    private var popoverOpens = 0
    var accounts: [GhAccount] = []
    /// "Check again" on the Board's project access screen is running.
    private(set) var checkingAccess = false
    /// GitHub App accounts' sign-in states, as the broker reports them.
    private(set) var authStates: [AccountRef: AuthState] = [:]
    /// The GitHub App's access for the current app account, by org; empty for a `gh` account.
    private(set) var orgAccess: [String: OrgAccess] = [:]
    /// The current app account's installation on its own account, for no-org mode; nil for `gh` and
    /// until the installations load.
    private(set) var personalAccess: OrgAccess?
    /// What no-org mode covers for that installation (all owned repos, the selected ones, or unreadable);
    /// nil until read. Read only in no-org mode.
    private(set) var personalRepos: PersonalRepos?
    /// Launch, or the switch after a sign-out, is still choosing an account: no first-run state yet.
    private(set) var resolvingAccount = true
    /// Whether the Keychain can hold a sign-in; nil until launch has checked.
    private(set) var storageAvailable: Bool?
    /// False when launch's last look found no `gh` at all; nil until it has looked.
    private(set) var ghInstalled: Bool?
    /// The first-run screen's "Use X from GitHub CLI" (or the checklist's) is running, or failed.
    private(set) var ghUse: GhUse?
    /// Choose Repositories on GitHub was clicked: the personal install step's timed re-checks.
    private(set) var installWait: InstallWait = .notStarted
    /// Why the personal install step's last check failed; nil when it succeeded or none ran.
    private(set) var installCheckError: RefreshError?

    @ObservationIgnored private let settingsStore: SettingsStore
    @ObservationIgnored let snapshotStore: SnapshotStore
    @ObservationIgnored private let gh: GhCLI
    @ObservationIgnored private let transport: any GraphQLTransport
    @ObservationIgnored private let httpTransport: any HTTPTransport
    @ObservationIgnored private let broker: TokenBroker
    @ObservationIgnored private let appConfig: GitHubAppConfig?
    /// The preview model: it has no app config on purpose.
    @ObservationIgnored private var previewing = false
    @ObservationIgnored private var statesTask: Task<Void, Never>?
    /// Trims the detail and avatar disk caches a minute after launch, then once a day.
    @ObservationIgnored private var cacheTrimTask: Task<Void, Never>?
    /// What `GET /user/installations` last returned per app account; the source of `orgAccess`.
    @ObservationIgnored private var installations: [AccountRef: InstallationsState] = [:]
    /// The last read of each app account's own-account repository list; the source of `personalRepos`.
    @ObservationIgnored private var personalRepoReads: [AccountRef: PersonalRepos] = [:]
    @ObservationIgnored private var personalReposTask: (account: AccountRef, task: Task<Void, Never>)?
    @ObservationIgnored private var installationsTask: (account: AccountRef, task: Task<Void, Never>)?
    @ObservationIgnored private var coordinator: RefreshCoordinator?
    /// Accounts whose token can't read notifications (the activity check), until they sign in or out
    /// again or the app restarts; their loops poll without the check.
    @ObservationIgnored private var activityUnsupported: Set<AccountRef> = []
    @ObservationIgnored private var running: RunConfig? {
        didSet { reconcileAsk() }
    }
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    // Ask (see Ask/AppModel+Ask.swift).
    /// The Ask index's progress for Settings → Ask; nil while no index is open.
    var askProgress: AskSyncProgress?
    /// The Anthropic key's state for Settings → Ask.
    var askKeyState: AskKeyState = .none
    /// Why the Ask index couldn't open; nil after a successful open and while Ask is off.
    var askOpenError: String?
    /// Opens and closes the Ask index; created on first use.
    @ObservationIgnored var askLifecycle: AskLifecycle<AskRuntime>?
    /// The Ask behind the search field: the question in flight, its outcome and the no-key notice.
    private(set) var askState = AskState()
    /// The highlighted row of the Ask screen (↑/↓; Return opens it).
    var askSelection: PRKey?
    /// Where Back lands from each detail opened from the Ask screen, innermost last.
    private(set) var askReturn = AskReturn()
    @ObservationIgnored var askTask: Task<Void, Never>?
    /// Watches connectivity so a refresh runs as soon as the network is back (see `NetworkRecovery`);
    /// started by the main init only, cancelled in deinit.
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    /// The last path the monitor reported (satisfied or not); nil before the first. Each new
    /// coordinator is told it, so its first offline failure knows the network is up.
    @ObservationIgnored private var networkSatisfied: Bool?
    @ObservationIgnored private var installWaitStarted: Date?
    @ObservationIgnored private var installWaitTask: Task<Void, Never>?
    /// Personal install steps on screen (sign-in window, popover, Settings); timed re-checks run only
    /// while there is one.
    @ObservationIgnored private var installStepViewers = 0
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchGeneration = 0
    /// The account, scope, focus and query the results on screen were searched for; nil without an account.
    @ObservationIgnored private var searchedFor: SearchCache.Key?
    /// The result highlighted when Back searched again, kept highlighted if a later answer of that search
    /// still has it; nil once the search is done or the user moves on.
    @ObservationIgnored private var keptSearchSelection: PRKey?
    /// GitHub's recent search answers for the running account and scope.
    @ObservationIgnored private let searchCache = SearchCache()
    @ObservationIgnored private var boardPickTask: Task<Void, Never>?
    private enum PersonalBoardPick: Equatable {
        case picking(AccountRef)
        case picked(AccountRef)

        var account: AccountRef {
            switch self {
            case .picking(let account), .picked(let account): account
            }
        }
    }

    /// No-org mode's first-board pick: running, or done (a board picked, or the account has none) so it
    /// isn't asked again. A failed fetch clears it, and the next refresh tries again.
    @ObservationIgnored private var personalBoardPick: PersonalBoardPick?
    @ObservationIgnored private var accountsTask: Task<Void, Never>?
    @ObservationIgnored private var accountsCheckedAt: Date?
    /// Orders start and update calls to the coordinator.
    @ObservationIgnored private var coordinatorCommand: Task<Void, Never>?
    /// The stopped state showing (no account, org not approved, app installed nowhere), so other settings
    /// writes don't redo it.
    @ObservationIgnored private var stoppedState: String?
    /// The signed-out app account whose cached data was deleted, so repeated updates don't delete again.
    @ObservationIgnored private var signedOutDropped: AccountRef?
    /// `signOut` is running: no bootstrap may start meanwhile, so none can pick the account again
    /// before it is forgotten or show the first-run state on the way.
    @ObservationIgnored private var signingOut = false
    /// A finished device flow is being saved and switched to; launch's account search waits.
    @ObservationIgnored private var signingIn = false

    // PR detail (see the "PR detail" extension below).
    /// Details for the running account, loaded from disk or fetched; keyed by PR.
    private(set) var details: [PRKey: PRDetail] = [:]
    /// The fetch for the detail on screen; nil once it succeeded.
    private(set) var detailFetch: DetailFetch?
    /// Where Back returns to from the detail view.
    private(set) var detailReturnRoute: Route = .list
    /// A notification opened a detail while the popover was closed; the next open shows it as it is.
    @ObservationIgnored var detailOpenedWhileClosed = false
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    /// The PR as it was when its detail was opened, for PRs that later leave the lists and results.
    @ObservationIgnored private var openedPR: PullRequest?
    /// A refresh started since the last prefetch; its successful end triggers the next prefetch.
    @ObservationIgnored private var refreshSeenSincePrefetch = false

    // Issue detail (see the "Issue detail" extension below).
    /// Issue details for the running account, loaded from disk or fetched; keyed by issue.
    private(set) var issueDetails: [PRKey: IssueDetail] = [:]
    /// The fetch for the issue detail on screen; nil once it succeeded.
    private(set) var issueDetailFetch: DetailFetch?
    /// Where Back returns to from the issue detail view (`.list` or `.search`).
    private(set) var issueDetailReturnRoute: Route = .list
    @ObservationIgnored private var issueDetailTask: Task<Void, Never>?
    /// The issue as it was when its detail was opened, for issues that later leave the lists and results.
    @ObservationIgnored private var openedIssue: BoardIssue?

    private struct RunConfig: Equatable {
        let account: String
        let source: AccountSource
        let scope: FetchScope
        let board: BoardRef?
        let refreshMinutes: Int
        let canReadProjects: Bool

        var ref: AccountRef { AccountRef(login: account, source: source) }
    }

    /// The running account and scope, which Ask indexes while it is on.
    var runningAskTarget: AskTarget? { running.map { AskTarget(account: $0.ref, scope: $0.scope) } }

    /// "Use X from GitHub CLI": running, or the message of its failure.
    struct GhUse: Equatable {
        let login: String
        var failure: String?
    }

    private enum InstallationsState: Equatable {
        case loaded([Installation])
        case ssoRequired(URL?)
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        snapshotStore: SnapshotStore = SnapshotStore(directory: AppModel.cacheDirectory),
        gh: GhCLI = GhCLI(),
        transport: any GraphQLTransport = URLSessionTransport(),
        httpTransport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.settingsStore = settingsStore
        self.snapshotStore = snapshotStore
        self.gh = gh
        self.transport = transport
        self.httpTransport = httpTransport
        let config = GitHubAppConfig.current
        appConfig = config
        broker = TokenBroker(
            store: KeychainCredentialStore(),
            deviceFlow: DeviceFlowClient(clientID: config?.clientID ?? "", transport: httpTransport),
            gh: gh)
        var loaded = settingsStore.load()
        loaded.reconcileTab()
        // Settings saved in no-org mode before personal boards have a board number with no owner.
        _ = loaded.reconcileBoard()
        self.settings = loaded
        self.selectedTab = loaded.lastTab
        self.mode = loaded.mode
        self.selectedIssueTab = loaded.lastIssueTab

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Wi-Fi is usually still reconnecting: the path coming back refreshes again.
                await self?.coordinator?.didWake()
                self?.refresh()
                await self?.coordinator?.checkActivitySoon()
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            MainActor.assumeIsolated { self?.networkPathChanged(satisfied: satisfied) }
        }
        pathMonitor.start(queue: .main)
        // Back from the browser: the personal install step checks at once.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheckPersonalInstallOnActivation() }
        }
        let states = broker.states
        statesTask = Task { [weak self] in
            for await (account, state) in states {
                guard let self else { return }
                self.authStates[account] = state
                switch state {
                case .signedOut: self.dropSignedOutData(account)
                case .valid, .unsaved: if self.signedOutDropped == account { self.signedOutDropped = nil }
                }
                self.reconcileAsk()
            }
        }
        cacheTrimTask = Self.trimCaches(snapshotStore)
        bootstrap()
    }

    /// A model that shows a fixed snapshot and never talks to GitHub (previews).
    init(preview snapshot: Snapshot, settings: AppSettings = AppSettings(), status: RefreshStatus? = nil) {
        settingsStore = SettingsStore(defaults: UserDefaults(suiteName: "io.github.rustycamper.pullbull.preview") ?? .standard)
        snapshotStore = SnapshotStore(directory: FileManager.default.temporaryDirectory)
        gh = GhCLI()
        transport = URLSessionTransport()
        httpTransport = URLSessionHTTPTransport()
        appConfig = nil
        previewing = true
        broker = TokenBroker(
            store: PreviewCredentialStore(), deviceFlow: DeviceFlowClient(clientID: "", transport: httpTransport),
            gh: gh)
        resolvingAccount = false
        storageAvailable = false
        self.settings = settings
        self.selectedTab = settings.lastTab
        self.mode = settings.mode
        self.selectedIssueTab = settings.lastIssueTab
        self.snapshot = snapshot
        self.status = status ?? RefreshStatus(lastSuccess: snapshot.fetchedAt, error: nil, isRefreshing: false)
        rebuildTabs()
    }

    deinit {
        pathMonitor.cancel()
    }

    /// Off the main thread: the detail trim runs on the store's actor, between its reads and saves, and
    /// the avatar trim on this detached task. Sign Out still clears an account's caches at once.
    private static func trimCaches(_ store: SnapshotStore) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await store.trimDetails(now: Date())
                AvatarCache.shared.trim(now: Date())
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }

    static var cacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.rustycamper.pullbull/cache", isDirectory: true)
    }

    // MARK: Actions

    func popoverDidOpen() {
        popoverOpens += 1
        reloadAccounts()
        // The ⌥⌘↩ hint shows once a key is saved; reading the Keychain sends nothing.
        if settings.askEnabled { loadAskKeyState() }
        if case .detail(let key) = route { loadDetail(key) }
        if case .issueDetail(let key) = route { loadIssueDetail(key) }
        if route == .search, searchResults == nil || searchResults?.phase != .done || searchField.isStale {
            updateSearch(searchText)
        }
        guard let coordinator else {
            if running == nil { bootstrap() }
            return
        }
        Task { await coordinator.refreshIfOlderThan(.seconds(30)) }
    }

    func refresh() {
        guard let coordinator else {
            bootstrap()
            return
        }
        Task { await coordinator.refreshNow() }
    }

    /// In order with the other coordinator calls; the coordinator decides whether it refreshes.
    private func networkPathChanged(satisfied: Bool) {
        networkSatisfied = satisfied
        guard let coordinator else { return }
        command { await coordinator.networkPathChanged(satisfied: satisfied) }
    }

    func badgeCount() -> Int {
        tabs.map { Badge.count(prs: $0, issues: issueTabs, settings: settings) } ?? 0
    }

    /// The badge adds an Assigned count whose latest search failed or never ran.
    var badgeIssuesIncomplete: Bool {
        Badge.issuesIncomplete(issues: issueTabs, settings: settings)
    }

    /// The PR tabs shown: Team needs an org.
    var prTabs: [PRTab] { settings.scope.map(PRTab.shown) ?? PRTab.allCases }

    func contents(of tab: PRTab) -> TabContents? {
        guard let tabs else { return nil }
        switch tab {
        case .review: return tabs.review
        case .mine: return tabs.mine
        case .team: return tabs.team
        }
    }

    /// Nil before the first snapshot, and for Board while the board is unavailable.
    func contents(of tab: IssueTab) -> IssueTabContents? {
        issueTabs?.contents(tab)
    }

    /// Focuses `repo` (`owner/name`), or clears the focus for nil. Idempotent: the repository already
    /// focused stays focused. Callers that toggle pass nil themselves.
    func focus(on repo: String?) {
        guard let repo else {
            repoFocus = nil
            return
        }
        guard repoFocus?.repo.caseInsensitiveCompare(repo) != .orderedSame else { return }
        repoFocus = RepoFocus(repo: repo)
    }

    /// `contents(of:)` narrowed to the focus; unchanged, with nothing in other repositories, without one.
    func scopedContents(of tab: PRTab) -> ScopedTab? {
        guard let contents = contents(of: tab) else { return nil }
        return repoFocus?.scope(contents) ?? ScopedTab(unscoped: contents)
    }

    func scopedContents(of tab: IssueTab) -> ScopedIssueTab? {
        guard let contents = contents(of: tab) else { return nil }
        return repoFocus?.scope(contents) ?? ScopedIssueTab(unscoped: contents)
    }

    var scopedRecentlyClosed: [PullRequest] {
        let closed = tabs?.recentlyClosed ?? []
        return repoFocus?.scope(closed) ?? closed
    }

    /// PR tabs show repo group headers: Group by Repository is on and no focus merges them into one list.
    var listGroupedByRepo: Bool { settings.grouping == .repository && repoFocus == nil }

    /// Rows name their repository (`repo #num`) unless a repo header or the focus already does.
    var rowsShowRepo: Bool { settings.grouping != .repository && repoFocus == nil }

    /// The focus menu's repositories; empty before the first snapshot. Kept current as the tabs and the
    /// focus change, as every row's context menu names its repository from them.
    private(set) var repoChoices: [RepoChoice] = []

    private func refreshRepoChoices() {
        repoChoices = tabs.map { RepoFocus.choices(prs: $0, issues: issueTabs, current: repoFocus) } ?? []
    }

    /// How the focus UI names `repo` (`owner/name`): the bare name unless another listed repository shares
    /// it or the owner is not the org (in no-org mode, not the user: the snapshot's `org` is the login).
    func displayName(of repo: String) -> String {
        RepoFocus(repo: repo).displayName(among: repoChoices, org: snapshot?.org.org ?? settings.org ?? "")
    }

    // MARK: Board menu

    /// The boards the Board tab's menu lists, per account and owner: loaded when the menu opens, and
    /// warmed by every other boards fetch. This session only; dropped with the account's data.
    private(set) var boardList = BoardList()

    /// The Board tab's filter row names the board: there is a scope with boards, and the tab isn't explaining
    /// missing access instead.
    var offersBoardMenu: Bool {
        settings.accountRef != nil && settings.boardOwner != nil && BoardPicker.isOffered(
            canReadProjects: canReadProjects, personalAccess: personalBoardAccess,
            boardError: snapshot?.boardError, checkingAccess: checkingAccess)
    }

    /// The current owner's boards as the menu shows them; nil when never loaded.
    var boardListState: BoardList.State? {
        guard let account = settings.accountRef, let owner = settings.boardOwner else { return nil }
        return boardList.state(account: account, owner: owner)
    }

    var boardMenuItems: [BoardMenuItem] {
        guard let owner = settings.boardOwner else { return [] }
        return BoardPicker.items(boardListState, current: settings.board, owner: owner)
    }

    /// The filter row's name for the chosen board, or "Choose a Board".
    var boardMenuTitle: String {
        let fetched = snapshot.flatMap { settings.board?.matches($0.board) == true ? $0.boardTitle : nil }
        return BoardPicker.title(current: settings.board, state: boardListState, fetchedTitle: fetched)
    }

    /// Loads the current owner's boards unless they are loading or loaded in the last five minutes.
    func loadBoardListIfNeeded() {
        guard let account = settings.accountRef, let owner = settings.boardOwner, canReadProjects,
              boardList.needsLoad(account: account, owner: owner, now: Date())
        else { return }
        boardList.began(account: account, owner: owner)
        let org = settings.org
        Task { [weak self] in
            do {
                // `projects(for:owner:)` keeps the result in `boardList`.
                _ = try await self?.projects(for: account, owner: owner)
            } catch {
                self?.boardList.failed(
                    RefreshError(error).message(org: org, source: account.source), account: account, owner: owner)
            }
        }
    }

    /// The board menu's choice: the same change as Settings' board picker.
    func chooseBoard(_ board: BoardRef) {
        guard !board.matches(settings.board) else { return }
        settings.board = board
    }

    // MARK: Search

    /// Whether the selected account's token can read the Projects board: the `read:project` scope for a
    /// `gh` login (an org's board or, in no-org mode, the user's own), the org's Projects permission for
    /// an app account (assumed until installations load). An app account can't read a personal board:
    /// GitHub gives apps no permission for user-owned boards.
    var canReadProjects: Bool {
        guard let account = settings.accountRef else { return false }
        switch account.source {
        case .gh:
            return accounts.canReadProjects(for: account.login)
        case .gitHubApp:
            guard let org = settings.org else { return false }
            switch orgAccess[org] {
            case .ok(_, let canReadProjects): return canReadProjects
            case nil: return true
            case .notInstalled, .ssoRequired: return false
            }
        }
    }

    /// In no-org mode, what the account needs before PullBull can read its personal board (`.ready` when
    /// nothing); nil in org mode, which has no personal boards.
    var personalBoardAccess: PersonalBoardAccess? {
        guard settings.org == nil, let account = settings.accountRef else { return nil }
        return PersonalBoardAccess.of(login: account.login, source: account.source, ghAccounts: accounts)
    }

    /// The command that adds `read:project` to the current account's `gh` login, leaving gh's active
    /// login as it was.
    var addProjectScopeCommand: String {
        GhCommands.addProjectScope(login: settings.account, activeLogin: accounts.first(where: \.active)?.login)
    }

    /// `error`'s message for the current account and org: no `gh` instructions for an app account.
    func message(for error: RefreshError) -> String {
        error.message(org: settings.org, source: settings.accountRef?.source)
    }

    /// Local results (or GitHub's answer from the last 10 minutes) show at once; the GitHub lookup starts
    /// 250ms after the last change, at once when not `debounced` (a query applied whole), and not at all
    /// while that answer is under 2 minutes old. With a `caret` (UTF-16 offset) the "@user" and "~label"
    /// completions follow it. Typing inside the pending token leaves the query, and so the results, as
    /// they are; the same text without a caret searches again.
    func updateSearch(_ text: String, caret: Int? = nil, startedOnTab: ShownTab? = nil, debounced: Bool = true) {
        // Opening a detail unfocuses the field, which pushes its unchanged text back; that must not close the detail.
        if text == searchText, route != .list, route != .search { return }
        // Editing or emptying the field cancels a running Ask and drops its line: back to normal search.
        if text != searchText { clearAsk() }
        if let startedOnTab, route != .search { searchStartedOnTab = startedOnTab }
        // Whitespace-only text clears the origin; a bare "#" keeps it for the number that follows.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { searchStartedOnTab = nil }
        // A cleared field leaves the narrowed tab selected, and the next query searches everything.
        searchScope = searchScope.edited(to: text)
        if let query = searchField.edit(text, caret: caret, people: people, labels: labels, statuses: statuses) {
            runSearch(query, debounced: debounced)
        }
    }

    /// The caret moved without a text change: the list may close (the token then counts as typed), never open.
    func searchCaretMoved(to caret: Int) {
        guard route == .list || route == .search, caret <= searchText.utf16.count else { return }
        if let query = searchField.caretMoved(to: caret, people: people, labels: labels, statuses: statuses) { runSearch(query) }
    }

    func moveCompletion(by offset: Int) {
        searchField.move(by: offset)
    }

    /// Tab / Return: the text and caret after inserting the selection, which the view must apply.
    func acceptCompletion() -> Int? {
        guard let open = completion, let accepted = open.accepted(in: searchText) else {
            dismissCompletion()
            return nil
        }
        // No more typing follows a completed token, so GitHub is asked at once.
        updateSearch(accepted.text, caret: accepted.caret, debounced: false)
        return accepted.caret
    }

    /// The rest of the qualifier the word at the caret starts, drawn after it in the field; nil while a
    /// list is open or off the list and search routes.
    var qualifierGhost: QualifierGhost? {
        guard route == .list || route == .search else { return nil }
        return searchField.ghost(statuses: statuses)
    }

    /// Text is selected in the field: no caret, so no ghost until it moves again.
    func searchTextSelected() {
        searchField.forgetCaret()
    }

    /// Tab on a ghost: writes the qualifier, which opens its list, and returns the caret for the view to
    /// apply; nil without a ghost.
    func acceptQualifierGhost() -> Int? {
        guard let accepted = qualifierGhost?.accepted(in: searchText) else { return nil }
        updateSearch(accepted.text, caret: accepted.caret)
        return accepted.caret
    }

    /// Esc, or Return with no candidate: the token stays as typed and counts as a name to filter by.
    func dismissCompletion() {
        guard route == .list || route == .search else {
            closeCompletion()
            return
        }
        if let query = searchField.dismiss() { runSearch(query) }
    }

    /// The popover closing or a detail opening: the list closes and nothing is searched on the way out.
    /// A lone pending token (`@ge`) so keeps no search route and is dropped like a bare "#"; with other
    /// terms, the next search (on reopen or Back) counts the token as typed.
    func closeCompletion() {
        searchField.close()
    }

    /// A search hint was picked: the field holds `sigil` alone with the caret after it, so an `@`, `~` or
    /// `is:` opens its list at once. The view puts the caret there.
    func startToken(_ sigil: String) {
        searchField.forgetCompletion()
        searchStartedOnTab = nil
        updateSearch(sigil, caret: sigil.utf16.count)
    }

    /// Searches for everything involving `login` and puts the caret after it.
    func searchForPerson(_ login: String) {
        let text = "@\(login) "
        searchField.forgetCompletion()
        searchStartedOnTab = nil
        updateSearch(text, caret: text.utf16.count)
        searchField.forgetCompletion()
        searchFieldFocusRequest += 1
    }

    /// A saved search picked under the empty field: the field holds its query and a space, the caret at
    /// the end, and it searches as if typed. The view puts the caret there.
    func applySavedSearch(_ saved: SavedSearch) {
        searchStartedOnTab = nil
        if let query = searchField.apply(saved, people: people, labels: labels, statuses: statuses) { runSearch(query, debounced: false) }
    }

    /// The field's query, trimmed, is one of the saved searches: the bookmark shows filled.
    var searchIsSaved: Bool { settings.savedSearches.contains(query: searchText) }

    /// Saves the field's query as `name`; false when either is invalid.
    @discardableResult
    func saveSearch(named name: String) -> Bool {
        settings.savedSearches.add(name: name, query: searchText) != nil
    }

    /// The query, focus and account to search for now; nil without an account.
    private func searchKey(for query: SearchQuery) -> SearchCache.Key? {
        running.map { SearchCache.Key(account: $0.ref, scope: $0.scope, query: query, focus: repoFocus) }
    }

    /// Back in the search: searches again, keeping the highlighted result, when the list was closed without
    /// searching (the token now counts as typed), or the results are gone or were searched for another
    /// focus or account (changed while a detail was open).
    private func searchAgainIfStale() {
        let fieldStale = searchField.isStale
        // Back to the list with text in the field (a tab row was opened while picking) searches it too.
        guard route == .search || (route == .list && !searchText.isEmpty && fieldStale) else { return }
        // A narrowed search costs nothing to run again, and the lists may have changed under the detail.
        guard fieldStale || searchResults == nil || searchKey(for: searchQuery) != searchedFor
            || shownSearchScope.isNarrowed
        else { return }
        let query = fieldStale ? searchField.edit(searchText, caret: nil, people: people, labels: labels, statuses: statuses) : searchQuery
        if let query { runSearch(query, debounced: false, keeping: searchSelection) }
    }

    /// `query` is already `searchField.query`. `debounced` waits 250ms before asking GitHub, for typing.
    /// `keeping` stays highlighted whenever an answer has it; a rerun of the same search keeps the one kept.
    private func runSearch(_ query: SearchQuery, debounced: Bool = true, keeping: PRKey? = nil) {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration += 1
        let key = searchKey(for: query)
        keptSearchSelection = keeping ?? (key == searchedFor ? keptSearchSelection : nil)
        searchedFor = key
        refreshSearchMatchCounts(for: query)
        guard query != .empty else {
            searchResults = nil
            searchSelection = nil
            if route == .search { route = .list }
            return
        }
        route = .search
        guard let snapshot else {
            searchResults = nil
            return
        }
        if let narrowed = SearchNarrowing.results(
            query, scope: shownSearchScope, tabs: tabs, issueTabs: issueTabs, focus: repoFocus,
            viewer: snapshot.org.viewer, snap: snapshot)
        {
            // The tab's lists are already fetched: nothing to ask GitHub.
            setSearchResults(narrowed)
            return
        }
        guard let account = running?.ref else {
            // Previews: no account to ask GitHub with, so local results are final.
            var local = SearchEngine(api: api(for: AccountRef(login: "", source: .gh)))
                .local(query, in: snapshot, focus: repoFocus)
            local.phase = .done
            setSearchResults(local)
            return
        }
        let engine = SearchEngine(api: api(for: account))
        let search = engine.results(
            query, snap: snapshot, account: account, cache: searchCache, focus: repoFocus,
            debounce: debounced ? .milliseconds(250) : .zero)
        setSearchResults(search.first)
        let generation = searchGeneration
        searchTask = Task { [weak self] in
            for await results in search.updates {
                guard let self, !Task.isCancelled, self.searchGeneration == generation,
                      self.searchQuery == query else { return }
                self.setSearchResults(results)
            }
        }
    }

    /// The search's scope in the current mode; a tab no longer shown is everything.
    var shownSearchScope: SearchScope { searchScope.valid(in: mode, prTabs: prTabs) }

    /// A tab clicked while results are on screen: the same query narrowed to that tab, which becomes the
    /// selected tab, or back to everything when it is the narrowed tab already.
    func pickSearchScope(_ tab: ShownTab) {
        searchScope = shownSearchScope.picking(SearchScope(tab))
        switch tab {
        case .pullRequests(let tab): selectedTab = tab
        case .issues(let tab): selectedIssueTab = tab
        }
        runSearch(searchQuery, debounced: false)
    }

    /// "Search everything" from a narrowed search's empty state: the same query over everything.
    func searchEverything() {
        guard shownSearchScope.isNarrowed else { return }
        searchScope = .everything
        runSearch(searchQuery, debounced: false)
    }

    /// `searchMatchCounts` for `query`, from the current lists and focus.
    private func refreshSearchMatchCounts(for query: SearchQuery) {
        searchMatchCounts = SearchNarrowing.counts(
            query, prTabs: prTabs, tabs: tabs, issueTabs: issueTabs, focus: repoFocus,
            viewer: snapshot?.org.viewer ?? "", snap: snapshot)
    }

    /// Esc / Cancel: clears the query and returns to the tabs.
    func cancelSearch() {
        updateSearch("")
        searchField.forgetCompletion()
    }

    /// The current mode's results in display order: pull requests in PR mode, issues in Issues mode.
    var searchItemKeys: [PRKey] {
        searchResults?.orderedKeys(mode: mode) ?? []
    }

    /// The line pointing to the other mode when only its kind matches; nil while searching, and in a
    /// narrowed search, which has its own empty state.
    var searchFallback: CrossModeFallback? {
        guard !shownSearchScope.isNarrowed else { return nil }
        return searchResults?.crossModeFallback(mode: mode, query: searchQuery)
    }

    /// The fallback line clicked, or Return on it: the other mode, keeping the query.
    func followSearchFallback() {
        guard let target = searchFallback?.target else { return }
        mode = target
    }

    func moveSearchSelection(by offset: Int) {
        let keys = searchItemKeys
        guard !keys.isEmpty else { return }
        keptSearchSelection = nil
        let current = searchSelection.flatMap { keys.firstIndex(of: $0) } ?? (offset > 0 ? -1 : keys.count)
        searchSelection = keys[min(max(current + offset, 0), keys.count - 1)]
    }

    /// Return: the selected result's detail view; with no result, the fallback line's mode.
    func openSearchSelection() {
        guard let key = searchSelection, let results = searchResults else {
            followSearchFallback()
            return
        }
        if let pr = (results.openPRs + results.closedPRs).first(where: { $0.key == key }) {
            openSearchResult(pr)
        } else if let issue = results.issues.first(where: { $0.key == key }) {
            openSearchResult(issue)
        }
    }

    /// ⌘Return: the selected result on GitHub.
    func openSearchSelectionOnGitHub() {
        guard let key = searchSelection, let results = searchResults else { return }
        if let pr = (results.openPRs + results.closedPRs).first(where: { $0.key == key }) {
            PRActions.openOnGitHub(pr)
        } else if let issue = results.issues.first(where: { $0.key == key }) {
            PRActions.openOnGitHub(issue)
        }
    }

    func openSearchResult(_ pr: PullRequest) {
        keptSearchSelection = nil
        searchSelection = pr.key
        openRowDetail(pr.key)
    }

    func openSearchResult(_ issue: BoardIssue) {
        keptSearchSelection = nil
        searchSelection = issue.key
        openRowIssueDetail(issue.key)
    }

    /// ⌘-click on a result: its page on GitHub, leaving the results on screen with it highlighted.
    func openSearchResultOnGitHub(_ pr: PullRequest) {
        keptSearchSelection = nil
        searchSelection = pr.key
        PRActions.openOnGitHub(pr)
    }

    func openSearchResultOnGitHub(_ issue: BoardIssue) {
        keptSearchSelection = nil
        searchSelection = issue.key
        PRActions.openOnGitHub(issue)
    }

    private func setSearchResults(_ results: SearchResults) {
        searchResults = results
        let keys = searchItemKeys
        if let kept = keptSearchSelection, keys.contains(kept) {
            searchSelection = kept
        } else if searchSelection.map({ !keys.contains($0) }) ?? true {
            searchSelection = keys.first
        }
        if results.phase == .done { keptSearchSelection = nil }
    }

    // MARK: Launch

    /// Resolves the account and org (picking defaults on first launch), then starts polling.
    private func bootstrap() {
        guard bootstrapTask == nil, !signingOut, !signingIn else { return }
        bootstrapTask = Task { [weak self] in
            await self?.runBootstrap()
            guard let self else { return }
            // Probed once: each probe writes a Keychain item, and the answer can't change while the app runs.
            if self.storageAvailable == nil { self.storageAvailable = await self.broker.isStorageAvailable() }
            self.bootstrapTask = nil
            self.resolvingAccount = false
        }
    }

    private func runBootstrap() async {
        // The broker finds an app account's Keychain item by the user ID in settings.
        await broker.register(settings.appAccounts)
        // A saved account and org start polling right away, so cached data and the badge show at once
        // even when `gh auth status` is slow or offline.
        startCoordinatorIfNeeded()
        accountsCheckedAt = Date()
        var ghError: (any Error)?
        do {
            let loaded = try await gh.accounts()
            ghInstalled = true
            // Offline at login, `gh auth status` validates nothing; a known list is kept.
            if !loaded.isEmpty || accounts.isEmpty { accounts = loaded }
        } catch {
            ghError = error
            ghInstalled = (error as? GhError) != .notInstalled
        }

        if let saved = settings.accountRef, saved.source == .gitHubApp {
            await resumeAppAccount(saved)
            return
        }
        if let saved = settings.accountRef {
            if let ghError {
                if running == nil { status.error = RefreshError(ghError) }
                return
            }
            if running != nil, settings.org != nil {
                // Scopes are known now; restarts only if project access differs from the assumption.
                startCoordinatorIfNeeded()
                return
            }
            if accounts.contains(where: { $0.login == saved.login }) {
                do {
                    // An account still in no org stays in no-org mode, which startCoordinatorIfNeeded
                    // already polls; one that has joined an org moves to it.
                    guard let org = try await api(for: saved).organizations().first else { return }
                    status.error = nil
                    switchAccount(to: saved, org: org)
                    return
                } catch {
                    // No-org mode keeps polling; its own fetch reports the failure.
                    if running != nil { return }
                    await findAccount(ghError: nil, lastError: error)
                    return
                }
            }
        }
        // A fresh install leaves the choice of `gh` login to the first-run screen, and so does a Sign Out.
        if FirstRunPolicy.waitsForChoice(
            saved: settings.accountRef, appAccounts: settings.appAccounts, ghLogins: accounts.map(\.login),
            signedOutByUser: settings.signedOutByUser) {
            // After a Sign Out nothing is picked, but a failed `gh` lookup shows as it does when launch
            // finds no account (no gh at all is not an error).
            if settings.signedOutByUser, let ghError, !Self.meansNoGh(ghError) { status.error = RefreshError(ghError) }
            return
        }
        await findAccount(ghError: ghError, lastError: nil)
    }

    /// No usable saved account: the first app account with an installed org, else the first `gh`
    /// account with an org, else an app account whose org hasn't approved PullBull (so the approval
    /// state shows). Then no-org mode: an app account installed on its own account, else the first
    /// `gh` account in no org, else an app account installed nowhere. With no account at all this
    /// sets no error: that is the first-run state. After the user's Sign Out it picks nothing: the
    /// first-run state stays until the user chooses an account.
    private func findAccount(ghError: (any Error)?, lastError: (any Error)?) async {
        guard !settings.signedOutByUser else { return }
        var lastError = lastError
        var waitingForApproval: (account: AccountRef, org: String)?
        var appWithoutOrg: AccountRef?
        var installedNowhere: AccountRef?
        var ghWithoutOrg: GhAccount?
        for summary in settings.appAccounts {
            do {
                let choice = try await appOrgChoice(for: summary.ref, preferring: settings)
                switch (choice.org, choice.installed) {
                case (let org?, true):
                    status.error = nil
                    switchAccount(to: summary.ref, org: org)
                    return
                case (let org?, false):
                    if waitingForApproval == nil { waitingForApproval = (summary.ref, org) }
                case (nil, true):
                    if appWithoutOrg == nil { appWithoutOrg = summary.ref }
                case (nil, false):
                    if installedNowhere == nil { installedNowhere = summary.ref }
                }
            } catch is AuthError {
                // Signed out: not a candidate. The first-run state offers Sign In.
            } catch {
                lastError = error
            }
        }
        if let ghError {
            // No gh at all is not an error now that Sign in with GitHub exists.
            if !Self.meansNoGh(ghError) { lastError = ghError }
        } else if !accounts.isEmpty {
            let search = await firstAccountWithOrg()
            if let found = search.found {
                status.error = nil
                switchAccount(to: AccountRef(login: found.account.login, source: .gh), org: found.org)
                return
            }
            ghWithoutOrg = search.withoutOrg
            lastError = search.lastError ?? lastError
        }
        // Every account with an org comes first; then no-org mode, app accounts before `gh` logins;
        // last an app account installed nowhere, for its install message.
        if let waitingForApproval {
            status.error = nil
            switchAccount(to: waitingForApproval.account, org: waitingForApproval.org)
            return
        }
        let noOrg = appWithoutOrg ?? ghWithoutOrg.map { AccountRef(login: $0.login, source: .gh) } ?? installedNowhere
        if let noOrg {
            status.error = nil
            switchAccount(to: noOrg, org: nil)
            return
        }
        // A failed lookup (offline, gh error) is reported as itself.
        if let lastError { status.error = RefreshError(lastError) }
    }

    private static func meansNoGh(_ error: any Error) -> Bool {
        switch error as? GhError {
        case .notInstalled, .notLoggedIn: true
        case .failed, nil: false
        }
    }

    /// A saved app account at launch: reads its installations (project access, approval), picks an
    /// installed org when none is saved, and lets polling follow.
    private func resumeAppAccount(_ account: AccountRef) async {
        do {
            let list = try await loadInstallations(for: account)
            if settings.accountRef == account, settings.org == nil,
               let org = settings.preferredOrg(for: account.login, among: Self.installedOrgs(list)) {
                settings.org = org
            }
        } catch {
            // Polling, when it runs, reports the failure itself; the next reload checks again.
            if running == nil, settings.accountRef == account { status.error = RefreshError(error) }
        }
        startCoordinatorIfNeeded()
    }

    /// The first account with an org whose context loads, else the first account GitHub lists in no
    /// org (`withoutOrg`), and the last error thrown while looking.
    private func firstAccountWithOrg() async
        -> (found: (account: GhAccount, org: String)?, withoutOrg: GhAccount?, lastError: (any Error)?) {
        var lastError: (any Error)?
        var withoutOrg: GhAccount?
        for account in accounts {
            let api = api(for: AccountRef(login: account.login, source: .gh))
            do {
                guard let org = try await api.organizations().first else {
                    if withoutOrg == nil { withoutOrg = account }
                    continue
                }
                _ = try await api.orgContext(org: org)
                return ((account, org), nil, nil)
            } catch {
                lastError = error
            }
        }
        return (nil, withoutOrg, lastError)
    }

    /// The org to select for an app account: an installed org (`preferredOrg` among them), else the
    /// user's first org that hasn't installed PullBull, for the approval state; nil when there is none.
    /// With no org at all, `installed` says whether PullBull is installed on the user's own account; that
    /// is known only when the org list loaded, so a failed list is never taken for no org.
    private func appOrgChoice(
        for account: AccountRef, preferring settings: AppSettings
    ) async throws -> (org: String?, installed: Bool) {
        let list = try await loadInstallations(for: account)
        let installed = Self.installedOrgs(list)
        if let org = settings.preferredOrg(for: account.login, among: installed) { return (org, true) }
        guard let orgs = try? await api(for: account).organizations() else { return (nil, false) }
        let waiting = orgs.first { org in !installed.contains { $0.caseInsensitiveCompare(org) == .orderedSame } }
        if let waiting { return (waiting, false) }
        let personal = AccessChecker.access(
            for: .personal(login: account.login), in: list, appSlug: appConfig?.appSlug ?? "")
        if case .ok = personal { return (nil, true) }
        return (nil, false)
    }

    private static func installedOrgs(_ list: [Installation]) -> [String] {
        list.filter(\.isOrganization).map(\.org)
    }

    /// Reads the app account's installations and keeps them for `orgAccess`. For the current account,
    /// polling follows at once (an org approved, or no longer installed).
    @discardableResult
    private func loadInstallations(for account: AccountRef) async throws -> [Installation] {
        let checker = AccessChecker(
            transport: httpTransport, auth: broker.source(for: account), appSlug: appConfig?.appSlug ?? "")
        do {
            let list = try await checker.installations()
            // In no-org mode the own-account repository list is read with the installations every time
            // (launch, reload, Check Again), so a repository added on GitHub shows without a relaunch.
            // Its failure never fails this load; org mode never reads it.
            if settings.accountRef == account, settings.org == nil {
                await readPersonalRepos(for: account, in: list, checker: checker)
            }
            setInstallations(.loaded(list), for: account)
            return list
        } catch APIError.ssoRequired(let url) {
            setInstallations(.ssoRequired(url), for: account)
            throw APIError.ssoRequired(url)
        }
    }

    /// Reads the repositories `account`'s own-account installation covers (`PersonalRepos`), keeping the
    /// last set read when this read fails.
    private func readPersonalRepos(for account: AccountRef, in list: [Installation], checker: AccessChecker) async {
        let previous = personalRepoReads[account]?.repos
        personalRepoReads[account] = await checker.personalRepos(of: account.login, in: list, previous: previous)
    }

    /// No-org mode found the repository list unread (e.g. the account was chosen after its installations
    /// loaded): reads it, then lets polling follow.
    private func readPersonalReposIfNeeded(_ account: AccountRef) {
        guard personalReposTask?.account != account, case .loaded(let list) = installations[account] else { return }
        let checker = AccessChecker(
            transport: httpTransport, auth: broker.source(for: account), appSlug: appConfig?.appSlug ?? "")
        personalReposTask = (account, Task { [weak self] in
            await self?.readPersonalRepos(for: account, in: list, checker: checker)
            guard let self else { return }
            if self.personalReposTask?.account == account { self.personalReposTask = nil }
            guard self.settings.accountRef == account else { return }
            self.rebuildOrgAccess()
            self.startCoordinatorIfNeeded()
        })
    }

    private func setInstallations(_ state: InstallationsState, for account: AccountRef) {
        installations[account] = state
        guard settings.accountRef == account else { return }
        rebuildOrgAccess()
        startCoordinatorIfNeeded()
    }

    /// `orgAccess` from the current app account's installations: every installed org, plus the
    /// selected org (installed or not, matched without regard to case). `personalAccess` from the
    /// installation on the user's own account, `personalRepos` from the last read of its list.
    private func rebuildOrgAccess() {
        var access: [String: OrgAccess] = [:]
        var personal: OrgAccess?
        var repos: PersonalRepos?
        if let account = settings.accountRef, account.source == .gitHubApp, let state = installations[account] {
            repos = personalRepoReads[account]
            switch state {
            case .loaded(let list):
                for item in list where item.isOrganization {
                    access[item.org] = .ok(allRepos: item.allRepositories, canReadProjects: item.canReadProjects)
                }
                if let org = settings.org {
                    access[org] = AccessChecker.access(for: org, in: list, appSlug: appConfig?.appSlug ?? "")
                }
                personal = AccessChecker.access(
                    for: .personal(login: account.login), in: list, appSlug: appConfig?.appSlug ?? "")
            case .ssoRequired(let url):
                if let org = settings.org { access[org] = .ssoRequired(url) }
            }
        }
        if access != orgAccess { orgAccess = access }
        if personal != personalAccess { personalAccess = personal }
        if repos != personalRepos { personalRepos = repos }
    }

    /// The app account's access for what it polls: its org's, or in no-org mode its own account's.
    private var scopeAccess: OrgAccess? {
        guard let org = settings.org else { return personalAccess }
        return orgAccess[org]
    }

    /// An app account became current without known installations (e.g. chosen in Settings): reads them,
    /// then lets polling pick up the project access and approval.
    private func checkInstallationsIfUnknown() {
        guard let account = settings.accountRef, account.source == .gitHubApp, installations[account] == nil,
              installationsTask?.account != account, bootstrapTask == nil
        else { return }
        installationsTask = (account, Task { [weak self] in
            _ = try? await self?.loadInstallations(for: account)
            guard let self else { return }
            if self.installationsTask?.account == account { self.installationsTask = nil }
            self.startCoordinatorIfNeeded()
        })
    }

    /// Reads `gh` logins and scopes again, at most once a minute, so `gh auth login` or
    /// `gh auth refresh -s read:project` take effect without a relaunch. A login whose scopes changed
    /// gets a fresh token before the coordinator picks up the new project access. For an app account it
    /// reads the installations again too (an owner approved PullBull, or granted Projects). `force`
    /// skips the once-a-minute limit, for an explicit "Check again".
    func reloadAccounts(force: Bool = false) {
        // While signing out, a reload could store installations again for the account being forgotten.
        guard bootstrapTask == nil, accountsTask == nil, !signingOut else { return }
        if !force, let last = accountsCheckedAt, Date().timeIntervalSince(last) < 60 { return }
        accountsCheckedAt = Date()
        accountsTask = Task { [weak self] in
            defer { self?.accountsTask = nil }
            if let self, let account = self.settings.accountRef, account.source == .gitHubApp {
                let couldReadProjects = self.canReadProjects
                if let list = try? await self.loadInstallations(for: account), !Task.isCancelled,
                   self.settings.accountRef == account {
                    if self.settings.org == nil,
                       let org = self.settings.preferredOrg(for: account.login, among: Self.installedOrgs(list)) {
                        self.settings.org = org
                    }
                    self.startCoordinatorIfNeeded()
                    if !couldReadProjects, self.canReadProjects, self.settings.projectNumber == nil {
                        self.pickFirstBoard()
                    }
                }
            }
            guard let loaded = try? await self?.gh.accounts(), let self, !Task.isCancelled else { return }
            await self.adoptGhAccounts(loaded)
        }
    }

    /// A fresh `gh` login list: a login whose scopes changed gets a fresh token before the coordinator
    /// picks up the new project access. An empty answer (offline) never wipes a known list.
    private func adoptGhAccounts(_ loaded: [GhAccount]) async {
        guard !loaded.isEmpty || accounts.isEmpty else { return }
        let before = Dictionary(accounts.map { ($0.login, $0.scopes) }, uniquingKeysWith: { a, _ in a })
        // Scopes not known before (e.g. offline at launch) may have changed too.
        let changed = loaded.filter { account in
            before[account.login].map { $0 != account.scopes } ?? true
        }.map(\.login)
        for login in changed {
            await broker.invalidate(AccountRef(login: login, source: .gh))
            activityUnsupported.remove(AccountRef(login: login, source: .gh))
        }
        guard !Task.isCancelled else { return }
        let couldReadProjects = canReadProjects
        accounts = loaded
        startCoordinatorIfNeeded()
        // Project access just arrived after an org change left no board: pick one now.
        if !couldReadProjects, canReadProjects, settings.projectNumber == nil { pickFirstBoard() }
    }

    /// "Check again" after `gh auth refresh`: waits for any reload already running (it may have read
    /// the old scopes), reads the logins and scopes again, lets the coordinator pick up the new project
    /// access, then refreshes. `checkingAccess` is true meanwhile.
    func checkAccessAgain() async {
        guard !checkingAccess else { return }
        checkingAccess = true
        defer { checkingAccess = false }
        await bootstrapTask?.value
        await accountsTask?.value
        reloadAccounts(force: true)
        await accountsTask?.value
        await coordinatorCommand?.value
        if let coordinator { await coordinator.refreshNow() } else { refresh() }
    }

    /// "Check Again" after an owner approved PullBull or granted a permission: reads the app account's
    /// installations again (with the `gh` scopes, as `checkAccessAgain`), then refreshes.
    func checkOrgAccessAgain() async {
        await checkAccessAgain()
    }

    /// Where an org owner installs PullBull, or a member requests it.
    var installURL: URL { AccessChecker.installURL(appSlug: appConfig?.appSlug ?? "") }

    /// What to say about the current app account's org access (in no-org mode, its own account's);
    /// nil for `gh` and while no account is chosen.
    var orgAccessNotice: OrgAccessNotice? {
        guard let account = settings.accountRef else { return nil }
        return OrgAccessNotice.notice(
            source: account.source, org: settings.org, access: scopeAccess, installURL: installURL,
            personal: personalInstallTarget(for: account))
    }

    /// The current app account's install on its own account: the install page with the account
    /// preselected, and the installation once there is one.
    var personalInstallTarget: PersonalInstallTarget? {
        guard let account = settings.accountRef, account.source == .gitHubApp else { return nil }
        return personalInstallTarget(for: account)
    }

    private func personalInstallTarget(for account: AccountRef) -> PersonalInstallTarget {
        let slug = appConfig?.appSlug ?? ""
        let userID = settings.appAccounts.first { $0.ref == account }?.userID
        var installationID: Int64?
        if case .loaded(let list) = installations[account] {
            installationID = AccessChecker.personalInstallation(of: account.login, in: list)?.id
        }
        return PersonalInstallTarget(
            login: account.login,
            installURL: userID.map { AccessChecker.installURL(appSlug: slug, targetID: $0) } ?? installURL,
            installationID: installationID)
    }

    func api(for account: AccountRef) -> GitHubAPI {
        GitHubAPI(transport: transport, auth: broker.source(for: account))
    }

    // MARK: Polling

    private func startCoordinatorIfNeeded() {
        guard let account = settings.accountRef else {
            // No account (first run, or the last one signed out): nothing polls and nothing shows. An
            // error launch found stays.
            showStopped("none", error: nil, keepingError: true)
            return
        }
        let key = "\(account.source.rawValue):\(account.login)"
        // No org is no-org mode: the user's own repositories (for an app account, once PullBull is
        // installed on its own account, and only those its installation covers).
        let scope = settings.org.map(FetchScope.org)
            ?? .personal(login: account.login, repos: account.source == .gitHubApp ? personalRepos?.repos : nil)
        if account.source == .gitHubApp {
            switch scopeAccess {
            case .ok(false, _) where settings.org == nil:
                // Limited to selected repos: polling waits for their list rather than show every owned
                // repo. Unreadable, it shows why with Retry (which reads it again), and posts nothing.
                switch personalRepos {
                case .selected:
                    break
                case .unreadable(let error):
                    showStopped("\(key)|repos-unreadable", error: error)
                    return
                case .all, nil:
                    readPersonalReposIfNeeded(account)
                    showStopped("\(key)|repos-loading", error: nil)
                    return
                }
            case .notInstalled(let url):
                if let org = settings.org {
                    showStopped(
                        "\(key)@\(org)|not-approved",
                        error: .other(OrgAccessNotice.notApproved(org: org, installURL: url).title))
                } else {
                    let notice = OrgAccessNotice.personalInstall(login: account.login, installURL: url, ownerURL: url)
                    showStopped("\(key)|no-org", error: .other(notice.title))
                }
                return
            case .ssoRequired(let url):
                showStopped("\(key)@\(settings.org ?? "")|sso", error: .ssoRequired(url))
                return
            case .ok, nil:
                break
            }
        }
        stoppedState = nil
        pickPersonalBoardIfNeeded()
        let config = RunConfig(
            account: account.login, source: account.source, scope: scope, board: settings.board,
            refreshMinutes: max(1, settings.refreshMinutes), canReadProjects: canReadProjects)
        guard config != running else { return }
        let interval = Duration.seconds(config.refreshMinutes * 60)
        if let coordinator, running?.ref == account, running?.scope == scope {
            // Same account and scope: change the running loop in place, keeping its data and error.
            running = config
            command {
                await coordinator.update(
                    board: config.board, canReadProjects: config.canReadProjects, interval: interval)
            }
            return
        }
        running = config

        updatesTask?.cancel()
        if let old = coordinator { Task { await old.stop() } }
        clearAccountData()
        status = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false)

        // An app account's cache shows only once its sign-in is known not to have ended, so a revoked
        // sign-in found at launch never flashes its old numbers. Offline, the cache still shows.
        let tokens = broker.source(for: account)
        let isApp = account.source == .gitHubApp
        let showsCache: @Sendable () async -> Bool = { @Sendable in
            guard isApp else { return true }
            do {
                _ = try await tokens.token()
                return true
            } catch is AuthError {
                return false
            } catch {
                return true
            }
        }
        // A fresh checker per loop, so an account or scope change starts from no `Last-Modified`.
        let activity = activityUnsupported.contains(account)
            ? nil : NotificationsActivityChecker(transport: httpTransport, auth: tokens)
        let coordinator = RefreshCoordinator(
            fetcher: LiveSnapshotFetcher(api: api(for: account)), store: snapshotStore, showsCache: showsCache)
        self.coordinator = coordinator
        updatesTask = Task { [weak self] in
            for await (snapshot, status) in coordinator.updates {
                guard let self, !Task.isCancelled else { return }
                self.apply(snapshot, status)
            }
        }
        command {
            await coordinator.start(
                account: account.login, scope: scope, board: config.board,
                canReadProjects: config.canReadProjects, interval: interval, activity: activity)
            // The last path seen: on its own it refreshes nothing (nothing has failed yet).
            if let satisfied = self.networkSatisfied { await coordinator.networkPathChanged(satisfied: satisfied) }
        }
    }

    /// Runs coordinator calls in the order they were made.
    private func command(_ body: @escaping @MainActor () async -> Void) {
        let previous = coordinatorCommand
        coordinatorCommand = Task {
            await previous?.value
            await body()
        }
    }

    /// The scope's owner changed and its board was cleared, or no-org mode has none: selects the
    /// owner's first board (the lowest number), if any. `fetched` hears whether the boards loaded.
    private func pickFirstBoard(fetched: ((Bool) -> Void)? = nil) {
        boardPickTask?.cancel()
        guard let account = settings.accountRef, let owner = settings.boardOwner, canReadProjects else {
            fetched?(false)
            return
        }
        boardPickTask = Task { [weak self] in
            let boards = try? await self?.projects(for: account, owner: owner)
            guard let self else { return }
            guard let boards, !Task.isCancelled else {
                fetched?(false)
                return
            }
            fetched?(true)
            guard let first = BoardSummary.first(of: boards), self.settings.accountRef == account,
                  self.settings.boardOwner == owner, self.settings.board == nil
            else { return }
            self.settings.board = first.board
        }
    }

    /// No-org mode with no board picks the user's first, once per account (they may have none). Done
    /// only once the boards loaded, so a failed fetch (offline, a 5xx) is retried on the next refresh.
    private func pickPersonalBoardIfNeeded() {
        guard let account = settings.accountRef, settings.org == nil, settings.board == nil,
              canReadProjects, personalBoardPick?.account != account
        else { return }
        personalBoardPick = .picking(account)
        pickFirstBoard { [weak self] loaded in
            guard let self, self.personalBoardPick == .picking(account) else { return }
            self.personalBoardPick = loaded ? .picked(account) : nil
        }
    }

    /// Polling can't run (no account, an org that hasn't approved PullBull, or an app account installed
    /// nowhere): stops it, shows nothing from the previous account, and shows `error`. `keepingError`
    /// leaves the error already showing (e.g. from launch) in place.
    private func showStopped(_ state: String, error: RefreshError?, keepingError: Bool = false) {
        guard stoppedState != state else { return }
        stoppedState = state
        updatesTask?.cancel()
        updatesTask = nil
        if let old = coordinator { Task { await old.stop() } }
        coordinator = nil
        running = nil
        clearAccountData()
        status = RefreshStatus(lastSuccess: nil, error: keepingError ? status.error : error, isRefreshing: false)
    }

    /// The running app account is signed out (revoked, refresh token expired or rejected): its lists,
    /// counts and search go, and its cached snapshot and details are deleted so a relaunch shows none
    /// either. The account stays in settings and its Keychain item stays, so Sign In returns to it.
    /// Polling is already paused by the coordinator.
    private func dropSignedOutData(_ account: AccountRef) {
        guard account.source == .gitHubApp, account == running?.ref else { return }
        searchCache.removeAll()
        if snapshot != nil || tabs != nil || searchResults != nil { clearAccountData() }
        guard signedOutDropped != account else { return }
        signedOutDropped = account
        let store = snapshotStore
        Task { [weak self] in
            await self?.settleAsk()
            try? await store.removeAll(account: account.login)
        }
    }

    /// Account or org changed: drops everything shown for the previous one.
    private func clearAccountData() {
        searchTask?.cancel()
        searchTask = nil
        searchResults = nil
        searchCache.removeAll()
        snapshot = nil
        people = .empty
        labels = .empty
        statuses = .empty
        searchField.refresh(people: people, labels: labels, statuses: statuses)
        tabs = nil
        issueTabs = nil
        hiddenApprovedCount = 0
        reviewCleared.reset()
        assignedCleared.reset()
        repoFocus = nil
        boardList = BoardList()
        resetDetails()
        NotificationService.shared.resetBaseline()
    }

    private func apply(_ snapshot: Snapshot?, _ status: RefreshStatus) {
        if case .signedOut(let account) = status.error, account == running?.ref {
            // The coordinator re-emits its last snapshot with the error; a signed-out account shows none.
            self.status = RefreshStatus(lastSuccess: nil, error: status.error, isRefreshing: status.isRefreshing)
            dropSignedOutData(account)
            return
        }
        if status.activity == .unsupported, let account = running?.ref { activityUnsupported.insert(account) }
        notifyChanges(snapshot, status)
        self.snapshot = snapshot
        var status = status
        if status.lastSuccess == nil, let current = self.snapshot { status.lastSuccess = current.fetchedAt }
        self.status = status
        rebuildTabs()
        if route == .search, searchResults == nil, snapshot != nil { updateSearch(searchText) }
        prefetchAfterSuccessfulRefresh(status)
        syncAskAfterRefresh(status)
        if !status.isRefreshing, status.error == nil { pickPersonalBoardIfNeeded() }
        // The token may lack the project scope that was assumed; scopes are read again (throttled).
        if snapshot?.boardError == RefreshError(APIError.insufficientScopes).message { reloadAccounts() }
    }

    private func rebuildTabs() {
        guard let snapshot else {
            tabs = nil
            issueTabs = nil
            hiddenApprovedCount = 0
            reviewCleared.reset()
            assignedCleared.reset()
            people = .empty
            labels = .empty
            statuses = .empty
            searchField.refresh(people: people, labels: labels, statuses: statuses)
            searchMatchCounts = [:]
            return
        }
        let index = PeopleIndex.build(snapshot)
        let labelIndex = LabelIndex.build(snapshot)
        let statusIndex = StatusIndex.build(snapshot)
        if index != people || labelIndex != labels || statusIndex != statuses {
            people = index
            labels = labelIndex
            statuses = statusIndex
            searchField.refresh(people: people, labels: labels, statuses: statuses)
        }
        let now = Date()
        let built = TabBuilder.build(snapshot, settings: settings, now: now)
        tabs = built
        issueTabs = IssueTabBuilder.build(snapshot, settings: settings, now: now)
        hiddenApprovedCount = built.hiddenApprovedCount
        reviewCleared.observe(count: built.review.rows.count, fetchedAt: snapshot.fetchedAt)
        // Assigned as its empty state sees it: the folded Done group doesn't count.
        if let issues = issueTabs, issues.assignedLoaded, let fetchedAt = issues.assignedFetchedAt {
            let listed = issues.assigned.groups.filter { $0.kind != .done }.reduce(0) { $0 + $1.issues.count }
            assignedCleared.observe(count: listed, fetchedAt: fetchedAt)
        }
        if let f = repoFocus, let tabs, !f.isValid(prs: tabs, issues: issueTabs, org: snapshot.org) { repoFocus = nil }
        refreshSearchMatchCounts(for: searchQuery)
        // A narrowed search is the lists' own items, so it follows them.
        if route == .search, shownSearchScope.isNarrowed {
            runSearch(searchQuery, debounced: false, keeping: searchSelection)
        }
    }
}

// MARK: - PR detail

/// What was on screen when a row was chosen. Its detail opens after the flash only if all of it is the
/// same: the route, the mode and tab, the account and org, the search query, and the popover still open
/// without having closed and opened again.
struct RowFlashContext: Equatable, Sendable {
    let route: Route
    let shownTab: ShownTab
    let account: String?
    let source: AccountSource?
    let org: String?
    let query: String
    let popoverShown: Bool
    let popoverOpens: Int
}

/// The state of the fetch for the detail on screen.
struct DetailFetch: Equatable {
    let key: PRKey
    var isLoading: Bool
    /// Why the last fetch failed; the cached detail, if any, stays on screen.
    var error: String?
}

extension AppModel {
    /// The cached detail for `key` (from disk or the last fetch); nil until one has loaded.
    func detail(for key: PRKey) -> PRDetail? {
        details[key]
    }

    /// The list data for `key`: the current lists first, then search results, then the PR as opened.
    func pullRequest(for key: PRKey) -> PullRequest? {
        if let snapshot {
            let lists = [snapshot.reviewCandidates, snapshot.mine, snapshot.team, snapshot.recentlyClosed]
            for list in lists {
                if let pr = list.first(where: { $0.key == key }) { return pr }
            }
        }
        if let results = searchResults, let pr = (results.openPRs + results.closedPRs).first(where: { $0.key == key }) {
            return pr
        }
        return openedPR?.key == key ? openedPR : nil
    }

    /// A PR row chosen in a list or search: the row flashes, then its detail opens.
    func openRowDetail(_ key: PRKey) {
        flashRow(key) { $0.openDetail(key) }
    }

    /// An issue row chosen in a list or search: the row flashes, then its detail opens.
    func openRowIssueDetail(_ key: PRKey) {
        flashRow(key) { $0.openIssueDetail(key) }
    }

    /// Highlights the row for `RowFlash.duration`, then runs `open`. A choice during the flash is
    /// ignored, and nothing opens if what's on screen changed meanwhile (`RowFlashContext`).
    private func flashRow(_ key: PRKey, then open: @escaping @MainActor (AppModel) -> Void) {
        guard rowFlash.begin(key, context: rowFlashContext) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: RowFlash<RowFlashContext>.duration)
            guard let self else { return }
            if rowFlash.end(context: rowFlashContext) { open(self) }
        }
    }

    private var rowFlashContext: RowFlashContext {
        RowFlashContext(
            route: route, shownTab: shownTab, account: settings.account, source: settings.accountSource,
            org: settings.org, query: searchText, popoverShown: MenuBarPopover.isShown, popoverOpens: popoverOpens)
    }

    /// Shows the detail view for `key` with the cached detail at once, then refreshes it in place.
    func openDetail(_ key: PRKey) {
        switch route {
        case .ask: askReturn.open(from: .ask)
        case .issueDetail: if !askReturn.isEmpty { askReturn.open(from: .issueDetail) }
        case .list, .search: leaveAsk()
        case .detail: break
        }
        if case .detail = route {} else { detailReturnRoute = route }
        openedPR = pullRequest(for: key)
        closeCompletion()
        route = .detail(key)
        loadDetail(key)
    }

    /// Back: the Ask screen when Ask opened the detail, the issue detail a linked PR was opened from
    /// (fetched again, since it may have changed while the PR was open), the search (query kept) when
    /// the detail was opened from it, else the list.
    func closeDetail() {
        detailTask?.cancel()
        detailTask = nil
        detailFetch = nil
        if !askReturn.isEmpty, askReturn.close() == .ask {
            route = .ask
        } else if case .issueDetail(let issue) = detailReturnRoute {
            route = detailReturnRoute
            loadIssueDetail(issue)
        } else {
            route = detailReturnRoute == .search && !searchText.isEmpty ? .search : .list
            searchAgainIfStale()
        }
    }

    /// Whether Back from the detail on screen (through an issue detail, for a linked PR) ends in the
    /// search, so its query is kept while the popover is closed.
    var detailReturnsToSearch: Bool {
        // Back through Ask ends in the search too: Esc on the Ask screen keeps the question.
        if !askReturn.isEmpty { return true }
        switch route {
        case .ask:
            return true
        case .detail:
            if case .issueDetail = detailReturnRoute { return issueDetailReturnRoute == .search }
            return detailReturnRoute == .search
        case .issueDetail:
            return issueDetailReturnRoute == .search
        case .list, .search:
            return false
        }
    }

    /// Fetches the detail on screen again (Refresh, Retry).
    func reloadDetail() {
        guard case .detail(let key) = route else { return }
        loadDetail(key)
    }

    /// A CI-failure notification's checks: one detail fetch, also kept for the detail view. Nil on error.
    func checksForNotification(_ key: PRKey) async -> [Check]? {
        guard let ref = running?.ref else { return nil }
        let account = ref.login
        guard let fresh = try? await api(for: ref).detail(key) else { return nil }
        if running?.account == account { details[key] = fresh }
        return fresh.checks
    }

    fileprivate func loadDetail(_ key: PRKey) {
        detailTask?.cancel()
        guard let ref = running?.ref else {
            detailFetch = DetailFetch(key: key, isLoading: false, error: "No GitHub account")
            return
        }
        let account = ref.login
        detailFetch = DetailFetch(key: key, isLoading: true, error: nil)
        let api = api(for: ref)
        let store = snapshotStore
        detailTask = Task { [weak self] in
            if self?.details[key] == nil, let cached = await store.loadDetail(key, account: account) {
                guard let self, !Task.isCancelled, self.running?.account == account else { return }
                if self.details[key] == nil { self.details[key] = cached }
            }
            do {
                let fresh = try await api.detail(key)
                guard let self, !Task.isCancelled, self.running?.account == account else { return }
                self.details[key] = fresh
                if self.detailFetch?.key == key { self.detailFetch = nil }
                try? await store.saveDetail(fresh, account: account)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.detailFetch?.key == key else { return }
                self.detailFetch = DetailFetch(key: key, isLoading: false, error: self.message(for: RefreshError(error)))
                if case APIError.notFound = error { self.askItemNotFound(key) }
            }
        }
    }

    /// After each successful refresh, fetches the detail of every counted Review PR, then of the
    /// first `BuiltIssueTabs.prefetchCap` counted Assigned issues, one at a time, skipping those whose
    /// cached detail is still current. Failures are silent and never retried here.
    fileprivate func prefetchAfterSuccessfulRefresh(_ status: RefreshStatus) {
        if status.isRefreshing {
            refreshSeenSincePrefetch = true
            return
        }
        guard refreshSeenSincePrefetch else { return }
        refreshSeenSincePrefetch = false
        guard status.error == nil, let ref = running?.ref, let review = tabs?.review else { return }
        let account = ref.login
        let prs = review.rows.filter(\.counted).map(\.pr)
        let issues = issueTabs?.assignedToPrefetch ?? []
        let api = api(for: ref)
        let store = snapshotStore
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            for pr in prs {
                var cached = self?.details[pr.key]
                if cached == nil { cached = await store.loadDetail(pr.key, account: account) }
                guard let self, !Task.isCancelled, self.running?.account == account else { return }
                if let cached, self.details[pr.key] == nil { self.details[pr.key] = cached }
                if cached?.isCurrent(for: pr) == true { continue }
                do {
                    let fresh = try await api.detail(pr.key)
                    guard !Task.isCancelled, self.running?.account == account else { return }
                    self.details[pr.key] = fresh
                    if self.detailFetch?.key == pr.key { self.detailFetch = nil }
                    try? await store.saveDetail(fresh, account: account)
                } catch {
                    if Self.stopsPrefetch(error) { return }
                }
            }
            // Issues after the PRs, never alongside them, to keep the request load low.
            for issue in issues {
                var cached = self?.issueDetails[issue.key]
                if cached == nil { cached = await store.loadIssueDetail(issue.key, account: account) }
                guard let self, !Task.isCancelled, self.running?.account == account else { return }
                if let cached, self.issueDetails[issue.key] == nil { self.issueDetails[issue.key] = cached }
                if cached?.isCurrent(for: issue) == true { continue }
                do {
                    let fresh = try await api.issueDetail(issue.key)
                    guard !Task.isCancelled, self.running?.account == account else { return }
                    self.issueDetails[issue.key] = fresh
                    if self.issueDetailFetch?.key == issue.key { self.issueDetailFetch = nil }
                    try? await store.saveIssueDetail(fresh, account: account)
                } catch {
                    if Self.stopsPrefetch(error) { return }
                }
            }
        }
    }

    /// Account-wide failures stop the prefetch; the next refresh's prefetch tries again. Others skip one item.
    private static func stopsPrefetch(_ error: any Error) -> Bool {
        switch error {
        case is CancellationError, is AuthError, is CredentialStoreError, is DeviceFlowError,
            APIError.unauthorized, APIError.network, APIError.unreachable, APIError.rateLimited,
            APIError.ssoRequired:
            return true
        default:
            return false
        }
    }

    /// Account or org changed: nothing from the previous account may show.
    fileprivate func resetDetails() {
        prefetchTask?.cancel()
        prefetchTask = nil
        detailTask?.cancel()
        detailTask = nil
        details = [:]
        detailFetch = nil
        openedPR = nil
        refreshSeenSincePrefetch = false
        detailReturnRoute = .list
        issueDetailTask?.cancel()
        issueDetailTask = nil
        issueDetails = [:]
        issueDetailFetch = nil
        openedIssue = nil
        issueDetailReturnRoute = .list
        switch route {
        case .detail, .issueDetail, .ask: route = .list
        case .list, .search: break
        }
        // Nothing the previous account asked about may show either.
        clearAsk()
        askReturn.reset()
    }
}

// MARK: - List keyboard

extension AppModel {
    /// The highlighted row of the tab on screen; it may be in a folded group or have left the list.
    var listSelection: PRKey? {
        get { listSelections[shownTab] }
        set { listSelections[shownTab] = newValue }
    }

    /// The rows of the tab on screen that ↑/↓ visit, in display order; none while it shows no list.
    func listKeys(closedExpanded: Bool, doneExpanded: Bool) -> [PRKey] {
        navigationKeys(for: shownTab, closedExpanded: closedExpanded, doneExpanded: doneExpanded)
    }

    private func navigationKeys(for tab: ShownTab, closedExpanded: Bool, doneExpanded: Bool) -> [PRKey] {
        switch tab {
        case .pullRequests(let prTab):
            guard let scoped = scopedContents(of: prTab) else { return [] }
            return ListNavigation.prKeys(
                tab: prTab, contents: scoped.contents, groupedByRepo: listGroupedByRepo,
                recentlyClosed: scopedRecentlyClosed, closedExpanded: closedExpanded)
        case .issues(let issueTab):
            guard let issueTabs, issueTabs.isLoaded(issueTab), let scoped = scopedContents(of: issueTab) else { return [] }
            return ListNavigation.issueKeys(
                scoped.contents, doneExpanded: doneExpanded, folded: foldedLanes(scoped.contents.groups, on: issueTab))
        }
    }

    /// The lanes among `groups` shown folded on `tab`; none while a search is active.
    func foldedLanes(_ groups: [IssueGroup], on tab: IssueTab) -> Set<IssueGroupKind> {
        settings.laneFolds.shownFolded(groups, tab: tab, board: settings.board, searching: route == .search)
    }

    /// Folds or opens a lane of the Issues tab on screen. A highlight in the lane moves to the next row
    /// still shown, or clears.
    func toggleLane(_ kind: IssueGroupKind, on tab: IssueTab, doneExpanded: Bool) {
        guard let board = settings.board else { return }
        let old = listKeys(closedExpanded: false, doneExpanded: doneExpanded)
        settings.laneFolds.toggle(kind, on: board, in: tab)
        let selection = ListNavigation.selection(
            listSelection, from: old, to: listKeys(closedExpanded: false, doneExpanded: doneExpanded))
        if selection != listSelection { listSelection = selection }
    }

    func moveListSelection(by offset: Int, in keys: [PRKey]) {
        listSelection = ListNavigation.move(listSelection, by: offset, in: keys)
    }

    /// ←/→: the neighboring sub-tab of the current mode.
    func moveTab(by offset: Int) {
        switch mode {
        case .pullRequests: selectedTab = ListNavigation.tab(selectedTab, movedBy: offset, among: prTabs)
        case .issues: selectedIssueTab = ListNavigation.tab(selectedIssueTab, movedBy: offset)
        }
    }

    /// Return: the highlighted row's detail; false when no shown row is highlighted.
    func openListSelection(in keys: [PRKey]) -> Bool {
        guard let key = ListNavigation.shown(listSelection, in: keys) else { return false }
        switch mode {
        case .pullRequests: openRowDetail(key)
        case .issues: openRowIssueDetail(key)
        }
        return true
    }

    /// The highlighted row and its GitHub page (⌘↩, ⌘C, ⌘⇧C); nil when no shown row is highlighted.
    func listSelectionLink(in keys: [PRKey]) -> (key: PRKey, url: URL)? {
        guard let key = ListNavigation.shown(listSelection, in: keys) else { return nil }
        switch mode {
        case .pullRequests: return (key, pullRequest(for: key)?.url ?? GitHubLinks.pullRequest(key))
        case .issues: return (key, issue(for: key)?.url ?? GitHubLinks.issue(key))
        }
    }

    /// The detail on screen and its GitHub page, as its Copy Link and Open on GitHub use it.
    var shownDetailLink: (key: PRKey, url: URL)? {
        switch route {
        case .detail(let key):
            return (key, pullRequest(for: key)?.url ?? GitHubLinks.pullRequest(key))
        case .issueDetail(let key):
            return (key, (issueDetails[key]?.issue ?? issue(for: key))?.url ?? GitHubLinks.issue(key))
        case .list, .search, .ask:
            return nil
        }
    }

    /// Esc, ← and ⌘[ in a detail.
    func closeShownDetail() {
        switch route {
        case .detail: closeDetail()
        case .issueDetail: closeIssueDetail()
        case .list, .search, .ask: break
        }
    }

    /// A reopen after a long while: drops the detail on screen, and any stacked under it, for the list
    /// (the search, query kept, when Back would end there). The Ask screen, and details opened from it,
    /// drop to the search with the question kept.
    func showListInsteadOfDetail() {
        let toSearch = detailReturnsToSearch && !searchText.isEmpty
        askReturn.reset()
        dropDetails()
        route = toSearch ? .search : .list
        searchAgainIfStale()
    }

    /// Stops the details' fetches and forgets where they return to.
    fileprivate func dropDetails() {
        detailTask?.cancel()
        detailTask = nil
        detailFetch = nil
        issueDetailTask?.cancel()
        issueDetailTask = nil
        issueDetailFetch = nil
        detailReturnRoute = .list
        issueDetailReturnRoute = .list
    }

    /// ⌘R in a detail: fetches it again unless a fetch is already running.
    func reloadShownDetail() {
        switch route {
        case .detail: if detailFetch?.isLoading != true { reloadDetail() }
        case .issueDetail: if issueDetailFetch?.isLoading != true { reloadIssueDetail() }
        case .list, .search, .ask: break
        }
    }
}

// MARK: - Ask screen

extension AppModel {
    /// ↩ or a click on an Ask row: switches to the item's mode and opens its detail, whose Back
    /// returns to the Ask screen.
    func openAskResult(_ key: PRKey) {
        guard route == .ask, let item = askRows.first(where: { $0.key == key }) else { return }
        askSelection = key
        switch item.kind {
        case .pr:
            mode = .pullRequests
            openDetail(key)
        case .issue:
            mode = .issues
            openIssueDetail(key)
        }
    }

    /// Return on the Ask screen: the highlighted row.
    func openAskSelection() {
        if let key = askSelection { openAskResult(key) }
    }

    /// Esc or ✕ on the Ask screen: the search field, with the question kept to edit and ask again. An
    /// Ask running again from here stops.
    func closeAsk() {
        guard route == .ask else { return }
        let landing = AskReturn.leavingAsk(question: askQuestion)
        cancelAsk()
        askReturn.reset()
        showSearch(landing)
    }

    /// The Ask screen is on screen, or under the detail on screen.
    var askOnScreen: Bool { route == .ask || !askReturn.isEmpty }

    /// The popover opening again on the Ask screen or a detail opened from it: `AskReturn.reopen` decides
    /// whether it stays or, after a long while, lands on the search with the question kept.
    func reopenAsk(closedAt: Date, now: Date) {
        guard askOnScreen else { return }
        let place: AskReturn.Place = switch route {
        case .detail: .pullRequestDetail
        case .issueDetail: .issueDetail
        case .list, .search, .ask: .ask
        }
        let landing = askReturn.reopen(at: place, question: askQuestion, closedAt: closedAt, now: now)
        if landing.place == .search { showSearch(landing) }
    }

    /// Ask turned off: no Ask runs, and the Ask screen (with any detail opened from it) gives way to the
    /// search with the question kept.
    func leaveAskForSearch() {
        let landing = AskReturn.leavingAsk(question: askQuestion)
        let shown = askOnScreen
        clearAsk()
        askReturn.reset()
        if shown { showSearch(landing) }
    }

    /// ⌥⌘↩ in the search field: asks the field's text.
    func ask() {
        guard route == .search else { return }
        startAsk(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Esc while asking, or a detail opening: the reply in flight is dropped.
    func cancelAsk() {
        askTask?.cancel()
        askTask = nil
        askState.cancel()
    }

    /// The field was edited or emptied: no Ask runs, and its line and notice go.
    func clearAsk() {
        askTask?.cancel()
        askTask = nil
        askState.clear()
    }

    /// A detail opening from the list or search: no Back leads to Ask, and a running Ask stops.
    fileprivate func leaveAsk() {
        askReturn.reset()
        cancelAsk()
    }

    /// Asks `question` over the open Ask index with the saved key and model: the only way anything
    /// reaches Anthropic's Messages API, and only from an explicit ⌥⌘↩. Without a key or an open index
    /// nothing is sent and a notice says why. A later Ask or an edit drops this one's reply.
    private func startAsk(_ question: String) {
        guard settings.askEnabled, !question.isEmpty, !askState.isAsking(question) else { return }
        askTask?.cancel()
        askTask = nil
        guard let key = (try? AnthropicKeyStore().load()) ?? nil else {
            askKeyState = .none
            refuseAsk(AskState.needsKeyNotice)
            return
        }
        guard let runtime = askRuntime else {
            refuseAsk(askOpenError ?? AskState.indexNotReadyNotice)
            return
        }
        let target = runtime.target
        let scopeName = switch target.scope {
        case .org(let org): org
        case .personal(let login, _): login
        }
        let model = AskModel.named(settings.askModel, in: askModelChoices)
        let session = AskSession(
            index: runtime.index,
            client: AskClient(apiKey: key, model: model),
            context: AskContext(scopeName: scopeName, isOrg: target.scope.org != nil, today: Date()),
            excluded: askExcludedRepos(), scope: target.scope)
        let focusedRepo = repoFocus?.repo
        let stillSyncing = askProgress.flatMap { $0.backfilling ? $0.indexed : nil }
        let token = askState.begin(question)
        askTask = Task { [weak self] in
            let outcome: AskOutcome?
            do {
                outcome = try await session.run(question, focusedRepo: focusedRepo, stillSyncing: stillSyncing)
            } catch {
                // `run` throws only cancellation; anything else would still be a failed Ask.
                outcome = AskGeneration.isCancellation(error) ? nil : .failed(question: question, .server(0))
            }
            guard let self else { return }
            if case .failed(_, .modelRetired) = outcome { self.retireAskModel(model.id) }
            if let outcome { self.landAsk(outcome, token: token) } else { self.askState.cancelled(token: token) }
        }
    }

    /// The notice shows over the search results, so from the Ask screen it goes back to the field first.
    private func refuseAsk(_ notice: String) {
        if route == .ask { closeAsk() }
        askState.refuse(notice)
    }

    /// A reply arrived. An answer opens the Ask screen with its first row highlighted; a failure stays as
    /// one line over the normal results (or in place of the answer on the Ask screen). Nothing lands once
    /// the search and the Ask screen were left.
    private func landAsk(_ outcome: AskOutcome, token: Int) {
        guard route == .search || route == .ask else {
            askState.cancelled(token: token)
            return
        }
        let arrival = askState.land(outcome, token: token)
        guard arrival != .ignored else { return }
        askTask = nil
        guard arrival == .screen else { return }
        askSelection = askRows.first?.key
        closeCompletion()
        route = .ask
    }

    /// Leaves Ask and any detail for the search with `landing`'s text. Opening a result may have switched
    /// the mode, which drops a narrowed tab, so the query is searched again for the scope shown.
    private func showSearch(_ landing: AskReturn.Landing) {
        dropDetails()
        guard !landing.searchText.isEmpty else {
            route = .list
            return
        }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines) != landing.searchText {
            updateSearch(landing.searchText, debounced: false)
        } else {
            route = .search
            runSearch(searchQuery, debounced: false, keeping: searchSelection)
        }
    }
}

// MARK: - Issue detail

extension AppModel {
    /// The list data for `key`: the board copy first (it carries the Status and board item), then
    /// Assigned, Created, search results, then the issue as opened.
    func issue(for key: PRKey) -> BoardIssue? {
        // The copy search shows: the newest of board, Assigned and Created, with the board's Status.
        if let snapshot, let issue = SearchEngine.cachedIssue(key, in: snapshot) { return issue }
        if let issue = searchResults?.issues.first(where: { $0.key == key }) { return issue }
        return openedIssue?.key == key ? openedIssue : nil
    }

    /// A pull request linked from a loaded issue detail, for a PR detail opened from it whose PR is in
    /// no list (merged or from another org); the issue the PR detail returns to is checked first.
    func linkedPR(for key: PRKey) -> LinkedPR? {
        if case .issueDetail(let issue) = detailReturnRoute,
           let pr = issueDetails[issue]?.linkedPRs.first(where: { $0.key == key }) {
            return pr
        }
        return issueDetails.values.lazy.compactMap { $0.linkedPRs.first { $0.key == key } }.first
    }

    /// The issue's Status on the board, as the lists show it; nil when it is not on the board, has no
    /// Status, the board can't be read, or its option no longer exists.
    func boardStatus(for key: PRKey) -> BoardStatusValue? {
        guard let snapshot else { return nil }
        return IssueTabBuilder.shownStatus(snapshot.boardIssues.first(where: { $0.key == key })?.status, in: snapshot)
    }

    /// Shows the issue detail for `key` with the cached detail at once, then refreshes it in place.
    func openIssueDetail(_ key: PRKey) {
        switch route {
        case .list, .search:
            leaveAsk()
            issueDetailReturnRoute = route
        case .ask:
            askReturn.open(from: .ask)
            issueDetailReturnRoute = route
        case .detail:
            // From a PR detail (e.g. a notification): Back goes to the list, not into the PR.
            askReturn.reset()
            detailTask?.cancel()
            detailTask = nil
            detailFetch = nil
            issueDetailReturnRoute = .list
        case .issueDetail:
            break
        }
        openedIssue = issue(for: key) ?? issueDetails[key]?.issue
        closeCompletion()
        route = .issueDetail(key)
        loadIssueDetail(key)
    }

    /// Back: the Ask screen when Ask opened the issue detail, the search (query kept) when the issue
    /// detail was opened from it, else the list.
    func closeIssueDetail() {
        issueDetailTask?.cancel()
        issueDetailTask = nil
        issueDetailFetch = nil
        if !askReturn.isEmpty, askReturn.close() == .ask {
            route = .ask
            return
        }
        route = issueDetailReturnRoute == .search && !searchText.isEmpty ? .search : .list
        searchAgainIfStale()
    }

    /// Fetches the issue detail on screen again (Refresh, Retry).
    func reloadIssueDetail() {
        guard case .issueDetail(let key) = route else { return }
        loadIssueDetail(key)
    }

    fileprivate func loadIssueDetail(_ key: PRKey) {
        issueDetailTask?.cancel()
        guard let ref = running?.ref else {
            issueDetailFetch = DetailFetch(key: key, isLoading: false, error: "No GitHub account")
            return
        }
        let account = ref.login
        issueDetailFetch = DetailFetch(key: key, isLoading: true, error: nil)
        let api = api(for: ref)
        let store = snapshotStore
        issueDetailTask = Task { [weak self] in
            if self?.issueDetails[key] == nil, let cached = await store.loadIssueDetail(key, account: account) {
                guard let self, !Task.isCancelled, self.running?.account == account else { return }
                if self.issueDetails[key] == nil { self.issueDetails[key] = cached }
            }
            do {
                let fresh = try await api.issueDetail(key)
                guard let self, !Task.isCancelled, self.running?.account == account else { return }
                self.issueDetails[key] = fresh
                if self.issueDetailFetch?.key == key { self.issueDetailFetch = nil }
                try? await store.saveIssueDetail(fresh, account: account)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.issueDetailFetch?.key == key else { return }
                self.issueDetailFetch = DetailFetch(
                    key: key, isLoading: false, error: self.message(for: RefreshError(error)))
                if case APIError.notFound = error { self.askItemNotFound(key) }
            }
        }
    }
}

// MARK: Settings window

extension AppModel {
    /// For an app account, the orgs that installed PullBull; for `gh`, every org the login is in.
    func organizations(for account: AccountRef) async throws -> [String] {
        switch account.source {
        case .gh: try await api(for: account).organizations()
        case .gitHubApp: Self.installedOrgs(try await loadInstallations(for: account))
        }
    }

    /// Every org the login belongs to, as GitHub lists it to the account's token. For an app account the
    /// list may hold only the orgs that installed PullBull; Settings then has no others to offer.
    func memberOrganizations(for account: AccountRef) async throws -> [String] {
        try await api(for: account).organizations()
    }

    func projects(for account: AccountRef, owner: BoardOwner) async throws -> [BoardSummary] {
        let boards = try await api(for: account).projects(owner: owner)
        boardList.loaded(boards, account: account, owner: owner, at: Date())
        return boards
    }

    /// Changes account and org in one settings write, so the coordinator restarts once.
    /// A nil org is no-org mode. Ends a Sign Out's first-run state: every caller is the user's choice,
    /// or a pick `findAccount` makes only while there is no such state.
    func switchAccount(to account: AccountRef, org: String?) {
        var updated = settings
        updated.choose(account, org: org)
        settings = updated
    }
}

// MARK: - Sign in with GitHub

extension AppModel {
    /// The GitHub App accounts signed in to, in sign-in order.
    var appAccounts: [AccountSummary] { settings.appAccounts }

    /// The current account is an app account whose sign-in ended.
    var isSignedOut: Bool {
        guard let account = settings.accountRef, case .signedOut = authStates[account] else { return false }
        return true
    }

    /// The current account's renewed sign-in is only in memory: the Keychain save failed. Cleared when
    /// a later save succeeds.
    var isSignInUnsaved: Bool {
        guard let account = settings.accountRef else { return false }
        return authStates[account] == .unsaved
    }

    /// Sign-in is configured but the Keychain can't hold a sign-in: the build isn't team-signed. False
    /// until launch's storage probe has run, and when the app isn't configured at all.
    var needsTeamSignedBuild: Bool {
        appConfig != nil && storageAvailable == false
    }

    /// The build lacks the app's client ID or slug (`Config/Shared.xcconfig`), so it can't sign in at all.
    var isSignInMisconfigured: Bool { appConfig == nil && !previewing }

    /// The build has the app's client ID and slug, and the Keychain can hold a sign-in (a team-signed build).
    var canSignInWithGitHub: Bool {
        appConfig != nil && storageAvailable == true
    }

    /// The popover's first-run layout: no account once launch has looked for one, or the current app
    /// account is signed out (headed "Signed out of GitHub").
    var showsFirstRun: Bool {
        if settings.account == nil { return !resolvingAccount }
        return isSignedOut
    }

    func showSignIn() {
        SignInWindowController.shared.show(
            app: self,
            complete: { [weak self] grant in
                guard let self else { return .unreachable }
                return await self.signIn(grant: grant)
            },
            checkApproval: { [weak self] in
                guard let self else { return false }
                await self.checkOrgAccessAgain()
                guard let org = self.settings.org, case .ok = self.orgAccess[org] else { return false }
                return true
            })
    }

    /// Saves a granted sign-in and selects it. Closing the sign-in window cancels the caller; the work
    /// runs in its own task, so a granted sign-in is saved and set up even then.
    func signIn(grant: TokenGrant) async -> SignInOutcome {
        await Task { await self.completeSignIn(grant) }.value
    }

    private func completeSignIn(_ grant: TokenGrant) async -> SignInOutcome {
        signingIn = true
        defer { signingIn = false }
        // A launch search still running would switch away from the new account once it finishes.
        await bootstrapTask?.value
        let identity: GitHubIdentity
        let account: AccountRef
        do {
            identity = try await AccessChecker(
                transport: httpTransport, auth: StaticTokenSource(grant.accessToken),
                appSlug: appConfig?.appSlug ?? ""
            ).identity()
        } catch {
            return .unreachable
        }
        do {
            account = try await broker.add(grant, identity: identity)
        } catch {
            storageAvailable = await broker.isStorageAvailable()
            return .saveFailed(needsSignedBuild: error as? CredentialStoreError == .unsignedBuild)
        }

        let renamed = settings.appAccounts.first { $0.userID == identity.userID && $0.login != identity.login }
        var updated = settings
        updated.upsert(AccountSummary(userID: identity.userID, login: identity.login, avatarURL: identity.avatarURL))
        if let renamed { adoptRename(from: renamed.ref, to: account, in: &updated) }
        if let current = updated.accountRef, current.source == .gitHubApp, current != account,
           case .signedOut = authStates[current] {
            // Signed in as someone else: added, but the signed-out account stays current.
            settings = updated
            await dropCaches(ofRenamed: renamed)
            return .differentLogin(identity, stillSignedOut: current.login)
        }
        // Signing in again as the signed-out running account: a fresh loop, so nothing from before shows.
        let resumesSignedOut = running?.ref == account && authStates[account].map(Self.isSignedOutState) == true
        authStates[account] = .valid
        activityUnsupported.remove(account)
        settings = updated

        var outcome = SignInOutcome.ready(identity)
        let org: String?
        do {
            let choice = try await appOrgChoice(for: account, preferring: settings)
            org = choice.org
            if !choice.installed, let org {
                outcome = .needsApproval(
                    identity, org: org, installURL: AccessChecker.installURL(appSlug: appConfig?.appSlug ?? ""))
            }
        } catch {
            // Installations unreadable (offline, SSO): the org last used, else the first; the next
            // reload checks access.
            let orgs = (try? await api(for: account).organizations()) ?? []
            org = settings.preferredOrg(for: account.login, among: orgs)
        }
        switchAccount(to: account, org: org)
        await dropCaches(ofRenamed: renamed)
        if resumesSignedOut, running?.ref == account {
            running = nil
            startCoordinatorIfNeeded()
        }
        // No org at all, and not installed on the user's own account: the window walks them through it.
        if case .ready = outcome, settings.org == nil, case .notInstalled = personalAccess {
            outcome = .needsPersonalInstall(identity)
        }
        return outcome
    }

    private static func isSignedOutState(_ state: AuthState) -> Bool {
        if case .signedOut = state { return true }
        return false
    }

    /// The same GitHub user signed in under a new login: the old login's org choice and current-account
    /// selection move to the new one, and its sign-in state goes.
    private func adoptRename(from old: AccountRef, to new: AccountRef, in settings: inout AppSettings) {
        if let org = settings.orgByAccount[old.login], settings.orgByAccount[new.login] == nil {
            settings.orgByAccount[new.login] = org
        }
        settings.orgByAccount[old.login] = nil
        if settings.accountRef == old { settings.account = new.login }
        authStates[old] = nil
        installations[old] = nil
        personalRepoReads[old] = nil
    }

    /// The old login's caches after a rename, unless a `gh` login still uses that name.
    private func dropCaches(ofRenamed renamed: AccountSummary?) async {
        guard let renamed, !accounts.contains(where: { $0.login == renamed.login }) else { return }
        await settleAsk()
        try? await snapshotStore.removeAll(account: renamed.login)
    }

    /// The user's explicit Sign Out, of an app account or a `gh` login: deletes the account's cached data
    /// and avatars (and an app account's Keychain item) and forgets it. Signing out of the current
    /// account leaves no account, the first-run state, until the user chooses one, even across
    /// relaunch; other accounts stay signed in and listed. A `gh` login stays logged in to GitHub CLI,
    /// which PullBull never changes. Returns false when an app account's Keychain item couldn't be
    /// deleted; the account is forgotten on this Mac all the same, and signing in again as that user
    /// overwrites the item.
    @discardableResult
    func signOut(_ account: AccountRef) async -> Bool {
        signingOut = true
        defer { signingOut = false }
        // A launch lookup still running could pick this account again once it is forgotten, and an
        // installations read still running would store them again for it.
        await bootstrapTask?.value
        await accountsTask?.value
        await installationsTask?.task.value
        // The broker can delete an app account's item only once it knows the user ID.
        await broker.register(settings.appAccounts)
        var removedFromKeychain = true
        switch account.source {
        case .gitHubApp:
            do {
                try await broker.signOut(account)
            } catch {
                removedFromKeychain = false
            }
        case .gh:
            // No Keychain item: only the token the broker read from `gh` for this login goes, once
            // nothing can fetch with it again (below).
            break
        }
        authStates[account] = nil
        installations[account] = nil
        personalRepoReads[account] = nil
        activityUnsupported.remove(account)
        searchCache.removeAll()
        let wasCurrent = settings.accountRef == account
        let stopped = wasCurrent ? coordinator : nil
        if wasCurrent { resolvingAccount = true }
        defer { if wasCurrent { resolvingAccount = false } }
        let summary = settings.appAccounts.first { $0.ref == account }
        // An account of the same name from the other source that PullBull still holds shares the
        // remembered org and the `<login>@*` caches.
        let keepsShared = SignOutPolicy.keepsSharedData(
            of: account, current: settings.accountRef, appLogins: settings.appAccounts.map(\.login))
        // Detail fetches of this account: cancelled ones save nothing, and one already saving
        // finishes before the caches are deleted.
        let detailWrites = wasCurrent ? [detailTask, prefetchTask, issueDetailTask].compactMap { $0 } : []
        detailWrites.forEach { $0.cancel() }
        var updated = settings
        updated.signOut(account, keepingRememberedOrg: keepsShared)
        settings = updated
        if wasCurrent { status = RefreshStatus(lastSuccess: nil, error: nil, isRefreshing: false) }
        // No poll may write the cache again once it is deleted: `stop()` waits for the fetch in flight.
        await stopped?.stop()
        for task in detailWrites { await task.value }
        await broker.invalidate(account)
        installations[account] = nil
        personalRepoReads[account] = nil
        if !keepsShared {
            var avatars = await snapshotStore.avatarURLs(account: account.login)
            avatars.formUnion(CachedAvatars.own(login: account.login, avatarURL: summary?.avatarURL))
            AvatarCache.shared.remove(avatars)
            await settleAsk()
            try? await snapshotStore.removeAll(account: account.login)
        }
        return removedFromKeychain
    }
}

// MARK: - Onboarding

extension AppModel {
    /// What launch found out about `gh`, for the first-run screen.
    var ghDetection: GhDetection {
        if ghInstalled == false { return .notInstalled }
        return accounts.isEmpty ? .noLogin : .logins(accounts)
    }

    var signInAvailability: SignInAvailability {
        if canSignInWithGitHub { return .available }
        return isSignInMisconfigured ? .misconfigured : .needsTeamSignedBuild
    }

    /// "Use X from GitHub CLI": what launch's `findAccount` does for that one login (its first org whose
    /// context loads, else no-org mode). `personal` keeps no-org mode even when X has orgs: the personal
    /// board's entry points switch for that board. A failure stays on screen as `ghUse.failure`.
    @discardableResult
    func useGhLogin(_ login: String, personal: Bool = false) async -> Bool {
        guard ghUse == nil || ghUse?.failure != nil else { return false }
        ghUse = GhUse(login: login)
        await bootstrapTask?.value
        let account = AccountRef(login: login, source: .gh)
        let api = api(for: account)
        do {
            let orgs = try await api.organizations()
            let org = personal ? nil : orgs.first
            if let org { _ = try await api.orgContext(org: org) }
            status.error = nil
            switchAccount(to: account, org: org)
            ghUse = nil
            return true
        } catch {
            let message = RefreshError(error).message(org: nil, source: .gh)
            ghUse = GhUse(login: login, failure: message)
            return false
        }
    }

    /// One pass of the GitHub CLI checklist: where `gh` is and who is logged in. Single-flight with
    /// `reloadAccounts`; the healthy logins become `accounts`, so the rest of the app sees a new login
    /// without a second `gh` run.
    func ghSetupPass() async -> GhStatus {
        await bootstrapTask?.value
        await accountsTask?.value
        let gh = gh
        let pass = Task { await gh.status() }
        accountsTask = Task { [weak self] in
            let result = await pass.value
            guard let self else { return }
            self.ghInstalled = result != .notInstalled
            if case .logins(_, let logins) = result {
                self.accountsCheckedAt = Date()
                await self.adoptGhAccounts(logins.filter { $0.health == .ok }.map {
                    GhAccount(login: $0.login, scopes: $0.scopes, active: $0.active)
                })
            }
            self.accountsTask = nil
        }
        await accountsTask?.value
        return await pass.value
    }

    /// The personal install step's state for the current app account; nil for `gh`.
    var personalInstallStep: PersonalInstallStep? {
        guard settings.accountRef?.source == .gitHubApp else { return nil }
        return PersonalInstallStep.current(
            org: settings.org, personalAccess: personalAccess, personalRepos: personalRepos, wait: installWait,
            lastCheckError: installCheckError)
    }

    /// Opens the install page and starts the timed re-checks (5 s, then every 10 s, for 10 minutes)
    /// while a screen shows the step.
    func chooseRepositoriesOnGitHub(_ url: URL) {
        NSWorkspace.shared.open(url)
        installWaitTask?.cancel()
        installWaitTask = nil
        installWait = .waiting
        installWaitStarted = Date()
        installCheckError = nil
        runInstallWaitIfShown()
    }

    func personalInstallStepAppeared() {
        installStepViewers += 1
        runInstallWaitIfShown()
    }

    /// Nothing is timed while no screen shows the step; the wait resumes with what is left of its 10
    /// minutes when one does.
    func personalInstallStepDisappeared() {
        installStepViewers = max(0, installStepViewers - 1)
        guard installStepViewers == 0 else { return }
        installWaitTask?.cancel()
        installWaitTask = nil
    }

    /// Check Again on the personal install step.
    func checkPersonalInstallAgain() async {
        guard !checkingAccess else { return }
        checkingAccess = true
        defer { checkingAccess = false }
        _ = await recheckPersonalInstall()
    }

    private func runInstallWaitIfShown() {
        guard installStepViewers > 0, installWait == .waiting, installWaitTask == nil,
              let started = installWaitStarted else { return }
        let elapsed = Duration.seconds(Date().timeIntervalSince(started))
        installWaitTask = Task { [weak self] in
            let end = await RecheckSchedule.personalInstall.run(clock: ContinuousClock(), startingAfter: elapsed) {
                await self?.recheckPersonalInstall() ?? .done
            }
            guard let self, end != .cancelled else { return }
            self.installWaitTask = nil
            self.installWait = end == .outOfTime ? .outOfTime : .notStarted
        }
    }

    private func recheckPersonalInstallOnActivation() {
        guard case .personalInstall = orgAccessNotice else { return }
        Task { _ = await recheckPersonalInstall() }
    }

    /// Reads the app account's installations (and in no-org mode its repository list) once: an install
    /// on the user's own account lets polling start, one on an org selects it. A failed read is not
    /// "not installed". Skipped when launch's lookup, which reads them too, was running.
    private func recheckPersonalInstall() async -> RecheckResult {
        guard let account = settings.accountRef, account.source == .gitHubApp, settings.org == nil else { return .done }
        if let bootstrapTask {
            await bootstrapTask.value
            return personalInstallStep?.recheckResult ?? .done
        }
        await accountsTask?.value
        accountsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let list = try await self.loadInstallations(for: account)
                self.installCheckError = nil
                if self.settings.accountRef == account, self.settings.org == nil,
                   let org = self.settings.preferredOrg(for: account.login, among: Self.installedOrgs(list)) {
                    self.settings.org = org
                }
                self.startCoordinatorIfNeeded()
            } catch {
                self.installCheckError = RefreshError(error)
            }
            self.accountsTask = nil
        }
        await accountsTask?.value
        return personalInstallStep?.recheckResult ?? .done
    }
}

/// The preview model's store: nothing saved, nothing to load.
private struct PreviewCredentialStore: CredentialStore {
    func load(userID: Int64) throws -> StoredCredential? { nil }
    func save(_ credential: StoredCredential) throws { throw CredentialStoreError.unsignedBuild }
    func delete(userID: Int64) throws {}
    func checkAvailable() throws { throw CredentialStoreError.unsignedBuild }
}
