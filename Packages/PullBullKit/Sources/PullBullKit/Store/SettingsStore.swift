import Foundation

public enum PRTab: String, Codable, CaseIterable, Sendable { case review, mine, team }

public enum BadgeSource: String, Codable, CaseIterable, Sendable { case review, mine, reviewAndMine, all }

public enum Grouping: String, Codable, Sendable { case repository, none }

public enum PopoverMode: String, Codable, CaseIterable, Sendable { case pullRequests, issues }

public enum IssueTab: String, Codable, CaseIterable, Sendable { case assigned, created, board }

public struct NotificationToggles: Codable, Equatable, Sendable {
    public var reviewRequested = true
    public var approved = true
    public var changesRequested = true
    public var ciFailed = true
    public var newComment = true
    /// My pull request merged by someone else.
    public var merged = true
    /// Off by default: an issue newly assigned to me by someone else.
    public var issueAssigned = false

    public init() {}

    /// Each toggle decodes on its own: one that can't be read gets its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = NotificationToggles()
        d.reviewRequested = c.readable(Bool.self, forKey: .reviewRequested) ?? d.reviewRequested
        d.approved = c.readable(Bool.self, forKey: .approved) ?? d.approved
        d.changesRequested = c.readable(Bool.self, forKey: .changesRequested) ?? d.changesRequested
        d.ciFailed = c.readable(Bool.self, forKey: .ciFailed) ?? d.ciFailed
        d.newComment = c.readable(Bool.self, forKey: .newComment) ?? d.newComment
        d.merged = c.readable(Bool.self, forKey: .merged) ?? d.merged
        d.issueAssigned = c.readable(Bool.self, forKey: .issueAssigned) ?? d.issueAssigned
        self = d
    }
}

extension KeyedDecodingContainer {
    /// The value at `key`; nil when it is missing, null, or can't be read (a wrong type, an enum case
    /// from a newer version), so one bad field never fails the whole object.
    func readable<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// For a field whose saved null differs from a missing key: `.some(nil)` for a saved null, nil
    /// when the key is missing or its value can't be read (both take the field's default).
    func readableOrNull<T: Decodable>(_ type: T.Type, forKey key: Key) -> T?? {
        guard contains(key) else { return nil }
        do {
            return .some(try decodeIfPresent(type, forKey: key))
        } catch {
            return nil
        }
    }

    /// The array at `key` without its unreadable elements; nil when the key is missing, null or not
    /// an array.
    func readableElements<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        readable([Readable<T>].self, forKey: key)?.compactMap(\.value)
    }

    /// The dictionary at `key` without its unreadable values; nil when the key is missing, null or
    /// not a dictionary.
    func readableValues<T: Decodable>(_ type: T.Type, forKey key: Key) -> [String: T]? {
        readable([String: Readable<T>].self, forKey: key)?.compactMapValues(\.value)
    }
}

/// One element of a collection decoded on its own: nil when it can't be read.
struct Readable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var account: String?
    public var org: String?
    /// The number of the Projects board searched for issues; nil when none is chosen. The default
    /// has no owner until an org adopts it (`reconcileBoard`); it is never a personal board.
    public var projectNumber: Int? = 3
    /// Who owns board `projectNumber`: the org it was chosen in, or in no-org mode the user. A
    /// different owner resets the board.
    public var projectOwner: BoardOwner?
    /// The org last chosen for each account, restored when switching back to it.
    public var orgByAccount: [String: String] = [:]
    public var grouping: Grouping = .repository
    public var compact = false
    public var hideOlderThanTwoMonths = true
    public var hideApprovedByMe = true
    public var hideDrafts = false
    public var badge: BadgeSource = .review
    public var notify = NotificationToggles()
    public var refreshMinutes = 2
    public var lastTab: PRTab = .review
    /// The global shortcut that shows and hides the popover; nil when turned off.
    public var toggleHotkey: KeyCombo? = .togglePopoverDefault
    /// The popover mode last shown.
    public var mode: PopoverMode = .pullRequests
    /// The Issues tab last shown.
    public var lastIssueTab: IssueTab = .assigned
    /// Adds the Assigned issues count to the menu bar badge.
    public var countAssignedIssues = false
    /// Draws the popover on an opaque window background instead of the translucent material.
    public var solidBackground = false
    /// Where `account`'s token comes from; nil with `account` set means `gh` (settings saved before sign-in).
    public var accountSource: AccountSource?
    /// The GitHub App accounts signed in to, in sign-in order.
    public var appAccounts: [AccountSummary] = []
    /// The user signed out of the current account and hasn't chosen another: launch and account
    /// reloads leave PullBull on the first-run screen instead of picking an account.
    public var signedOutByUser = false
    /// The saved searches, in the owner's order. `SettingsStore` keeps them under a key of their own,
    /// so they are not part of this object's coding.
    public var savedSearches = SavedSearches()
    /// The Board tab's folded lanes, per board.
    public var laneFolds = LaneFolds()
    /// Ask (AI search over a local index) is on. Off means no index file, no backfill and no key check.
    public var askEnabled = false
    /// The `AskModel` ID Ask uses; an unknown one reads as `AskModel.default`.
    public var askModel = AskModel.default.id
    /// The models the last key check offered (newest Sonnet and Haiku); empty means `AskModel.all`.
    public var askModelChoices: [AskModel] = []
    /// Repos (`owner/name`) Ask never indexes or sends.
    public var askExcludedRepos: [String] = []

    private enum CodingKeys: String, CodingKey {
        case account, org, projectNumber, projectOwner, projectOrg, orgByAccount, grouping, compact,
            hideOlderThanTwoMonths, hideApprovedByMe, hideDrafts, badge, notify, refreshMinutes, lastTab, toggleHotkey, mode, lastIssueTab,
            countAssignedIssues, solidBackground, accountSource, appAccounts, signedOutByUser, laneFolds,
            askEnabled, askModel, askModelChoices, askExcludedRepos
    }

    public init() {}

    /// Each field decodes on its own: one that can't be read (after a downgrade, an enum case from a
    /// newer version, a changed type) gets its default and the others keep their saved values.
    /// Unknown keys are ignored. Only a value that isn't a JSON object at all fails.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = AppSettings()
        d.account = c.readable(String.self, forKey: .account)
        d.org = c.readable(String.self, forKey: .org)
        // A saved null is "no board"; a missing key is the default board.
        if let number = c.readableOrNull(Int.self, forKey: .projectNumber) { d.projectNumber = number }
        // Settings saved before personal boards kept the org as `projectOrg`, and before that chose
        // their board in the saved org. With neither (no-org mode) the board has no owner, so a saved
        // number is never taken for a personal board. An owner saved but unreadable clears the board
        // too, so `reconcileBoard` never adopts another owner's number.
        if c.contains(.projectOwner) {
            d.projectOwner = c.readable(BoardOwner.self, forKey: .projectOwner)
            if d.projectOwner == nil { d.projectNumber = nil }
        } else if let org = c.readable(String.self, forKey: .projectOrg) ?? d.org {
            d.projectOwner = .org(org)
        }
        d.orgByAccount = c.readableValues(String.self, forKey: .orgByAccount) ?? d.orgByAccount
        d.grouping = c.readable(Grouping.self, forKey: .grouping) ?? d.grouping
        d.compact = c.readable(Bool.self, forKey: .compact) ?? d.compact
        d.hideOlderThanTwoMonths =
            c.readable(Bool.self, forKey: .hideOlderThanTwoMonths) ?? d.hideOlderThanTwoMonths
        d.hideApprovedByMe = c.readable(Bool.self, forKey: .hideApprovedByMe) ?? d.hideApprovedByMe
        d.hideDrafts = c.readable(Bool.self, forKey: .hideDrafts) ?? d.hideDrafts
        d.badge = c.readable(BadgeSource.self, forKey: .badge) ?? d.badge
        d.notify = c.readable(NotificationToggles.self, forKey: .notify) ?? d.notify
        d.refreshMinutes = c.readable(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
        d.lastTab = c.readable(PRTab.self, forKey: .lastTab) ?? d.lastTab
        // A saved null is "turned off"; a missing key (settings saved before the shortcut) is the default.
        if let hotkey = c.readableOrNull(KeyCombo.self, forKey: .toggleHotkey) { d.toggleHotkey = hotkey }
        d.mode = c.readable(PopoverMode.self, forKey: .mode) ?? d.mode
        d.lastIssueTab = c.readable(IssueTab.self, forKey: .lastIssueTab) ?? d.lastIssueTab
        d.countAssignedIssues = c.readable(Bool.self, forKey: .countAssignedIssues) ?? d.countAssignedIssues
        d.solidBackground = c.readable(Bool.self, forKey: .solidBackground) ?? d.solidBackground
        // A missing source means `gh` (settings saved before sign-in). One saved but unreadable (a
        // newer version's) is never taken for `gh`: the account and its org are cleared, to be chosen afresh.
        if let source = c.readableOrNull(AccountSource.self, forKey: .accountSource) {
            d.accountSource = source
        } else if c.contains(.accountSource) {
            d.account = nil
            d.org = nil
        }
        d.appAccounts = c.readableElements(AccountSummary.self, forKey: .appAccounts) ?? d.appAccounts
        d.signedOutByUser = c.readable(Bool.self, forKey: .signedOutByUser) ?? d.signedOutByUser
        d.laneFolds = c.readable(LaneFolds.self, forKey: .laneFolds) ?? d.laneFolds
        d.askEnabled = c.readable(Bool.self, forKey: .askEnabled) ?? d.askEnabled
        d.askModel = c.readable(String.self, forKey: .askModel) ?? d.askModel
        d.askModelChoices = c.readableElements(AskModel.self, forKey: .askModelChoices) ?? d.askModelChoices
        d.askExcludedRepos = c.readableElements(String.self, forKey: .askExcludedRepos) ?? d.askExcludedRepos
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(account, forKey: .account)
        try c.encodeIfPresent(org, forKey: .org)
        try c.encode(projectNumber, forKey: .projectNumber)
        try c.encodeIfPresent(projectOwner, forKey: .projectOwner)
        try c.encode(orgByAccount, forKey: .orgByAccount)
        try c.encode(grouping, forKey: .grouping)
        try c.encode(compact, forKey: .compact)
        try c.encode(hideOlderThanTwoMonths, forKey: .hideOlderThanTwoMonths)
        try c.encode(hideApprovedByMe, forKey: .hideApprovedByMe)
        try c.encode(hideDrafts, forKey: .hideDrafts)
        try c.encode(badge, forKey: .badge)
        try c.encode(notify, forKey: .notify)
        try c.encode(refreshMinutes, forKey: .refreshMinutes)
        try c.encode(lastTab, forKey: .lastTab)
        try c.encode(toggleHotkey, forKey: .toggleHotkey)
        try c.encode(mode, forKey: .mode)
        try c.encode(lastIssueTab, forKey: .lastIssueTab)
        try c.encode(countAssignedIssues, forKey: .countAssignedIssues)
        try c.encode(solidBackground, forKey: .solidBackground)
        try c.encodeIfPresent(accountSource, forKey: .accountSource)
        try c.encode(appAccounts, forKey: .appAccounts)
        try c.encode(signedOutByUser, forKey: .signedOutByUser)
        try c.encode(laneFolds, forKey: .laneFolds)
        try c.encode(askEnabled, forKey: .askEnabled)
        try c.encode(askModel, forKey: .askModel)
        try c.encode(askModelChoices, forKey: .askModelChoices)
        try c.encode(askExcludedRepos, forKey: .askExcludedRepos)
    }

    /// The current account with its token source; nil when none is chosen.
    public var accountRef: AccountRef? {
        account.map { AccountRef(login: $0, source: accountSource ?? .gh) }
    }

    /// What the current account polls: its org, or with none the user's own repositories (no-org
    /// mode); nil when no account is chosen.
    public var scope: FetchScope? {
        account.map { login in org.map(FetchScope.org) ?? .personal(login: login) }
    }

    /// A PR tab the scope doesn't show (Team without an org) gives way to Review.
    public mutating func reconcileTab() {
        guard let scope, !PRTab.shown(in: scope).contains(lastTab) else { return }
        lastTab = .review
    }

    /// Adds `summary`, replacing any summary with the same user ID (the login can change on GitHub).
    public mutating func upsert(_ summary: AccountSummary) {
        if let index = appAccounts.firstIndex(where: { $0.userID == summary.userID }) {
            appAccounts[index] = summary
        } else {
            appAccounts.append(summary)
        }
    }

    /// The user chose `account` (a nil org is no-org mode): it becomes current, and a Sign Out's
    /// first-run state ends.
    public mutating func choose(_ account: AccountRef, org: String?) {
        self.account = account.login
        accountSource = account.source
        self.org = org
        signedOutByUser = false
    }

    /// The user's Sign Out of `account`: forgets it, and when it was current leaves no account, to
    /// stay that way until the user chooses one. Signing out of another account leaves the current one.
    public mutating func signOut(_ account: AccountRef, keepingRememberedOrg: Bool = false) {
        let wasCurrent = accountRef == account
        forget(account, keepingRememberedOrg: keepingRememberedOrg)
        if wasCurrent { signedOutByUser = true }
    }

    /// Drops `account`'s summary and remembered org. When it is the current account, clears the
    /// current account, its source and the org. `keepingRememberedOrg` leaves the org remembered for
    /// the login (an account of the same name from the other source still uses it; see `SignOutPolicy`).
    public mutating func forget(_ account: AccountRef, keepingRememberedOrg: Bool = false) {
        if account.source == .gitHubApp { appAccounts.removeAll { $0.login == account.login } }
        if !keepingRememberedOrg { orgByAccount[account.login] = nil }
        if accountRef == account {
            self.account = nil
            accountSource = nil
            org = nil
        }
    }

    /// Whose boards the current scope shows: the org's, or in no-org mode the account's own; nil with
    /// no account.
    public var boardOwner: BoardOwner? {
        scope?.boardOwner
    }

    /// The chosen board, when it is one the current scope shows; nil otherwise. Setting it keeps the
    /// owner when set to nil.
    public var board: BoardRef? {
        get {
            guard let projectNumber, let projectOwner, let boardOwner, projectOwner.matches(boardOwner)
            else { return nil }
            return BoardRef(owner: projectOwner, number: projectNumber)
        }
        set {
            projectNumber = newValue?.number
            if let newValue { projectOwner = newValue.owner }
        }
    }

    /// Ties the board to the current scope's owner. The first org adopts an owner-less board as is;
    /// moving to another org, to no-org mode or to another account there clears it (the caller then
    /// picks the new owner's first board). Returns true when it was cleared, or when no-org mode
    /// found the board owner-less: a number saved without an owner is never a personal board.
    public mutating func reconcileBoard() -> Bool {
        guard let owner = boardOwner else { return false }
        if let projectOwner, projectOwner.matches(owner) { return false }
        defer { projectOwner = owner }
        if projectOwner == nil, !owner.isUser { return false }
        projectNumber = nil
        return true
    }

    /// Records the current org as the one chosen for the current account.
    public mutating func rememberOrg() {
        guard let account, let org else { return }
        orgByAccount[account] = org
    }

    /// The org to use for `login` (after switching to it, or when it has none): the org last chosen
    /// for `login` if it is among `orgs`, else the current org if `login` is in it, else its first org.
    /// Each account keeps its own org even when two accounts share one.
    public func preferredOrg(for login: String, among orgs: [String]) -> String? {
        if let remembered = orgByAccount[login], orgs.contains(remembered) { return remembered }
        if let org, orgs.contains(org) { return org }
        return orgs.first
    }
}

public struct SettingsStore: Sendable {
    private static let key = "settings.v1"
    /// Saved searches, a JSON array: global, not per account, and kept by Sign Out.
    private static let savedSearchesKey = "search.saved"
    /// A copy of settings that weren't a JSON object at all, kept by the first save over them.
    static let unreadableBackupKey = "settings.v1.unreadable"
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Each key decodes on its own: one that can't be read gives its defaults and leaves the other.
    public func load() -> AppSettings {
        var settings = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
        if let data = defaults.data(forKey: Self.savedSearchesKey),
           let saved = try? JSONDecoder().decode(SavedSearches.self, from: data) {
            settings.savedSearches = saved
        }
        return settings
    }

    /// Before overwriting settings that can't be read at all (they loaded as defaults), keeps one copy
    /// of them under `unreadableBackupKey`; an existing copy is never replaced.
    public func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            if let stored = defaults.object(forKey: Self.key), !Self.isReadable(stored),
               defaults.object(forKey: Self.unreadableBackupKey) == nil {
                defaults.set(stored, forKey: Self.unreadableBackupKey)
            }
            defaults.set(data, forKey: Self.key)
        }
        if let data = try? JSONEncoder().encode(settings.savedSearches) {
            defaults.set(data, forKey: Self.savedSearchesKey)
        }
    }

    /// Whether `stored` is data holding a JSON object, the one shape `AppSettings` decodes from.
    private static func isReadable(_ stored: Any) -> Bool {
        guard let data = stored as? Data else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
}
