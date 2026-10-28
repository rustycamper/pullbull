import Foundation

/// One entry of the Settings organization picker. Every entry can be chosen; choosing one that isn't
/// approved shows the approval message.
public struct OrgPickerItem: Equatable, Sendable, Identifiable {
    public let org: String
    /// False for an org that hasn't installed PullBull (app accounts only).
    public let approved: Bool

    public init(org: String, approved: Bool) {
        self.org = org
        self.approved = approved
    }

    public var id: String { org }

    public var label: String { approved ? org : "\(org) — Not approved" }
}

public enum OrgPicker {
    /// For `gh`, `installed` is every org the login is in, all approved. For an app account: the orgs
    /// that installed PullBull, then the user's other orgs marked not approved (matched without regard
    /// to case). The current org is kept at the top when neither list has it; for an app account it is
    /// marked not approved only when its access is known to be `.notInstalled`.
    public static func items(
        source: AccountSource, installed: [String], memberOrgs: [String], current: String?, currentAccess: OrgAccess?
    ) -> [OrgPickerItem] {
        var items: [OrgPickerItem] = []
        func contains(_ org: String) -> Bool {
            items.contains { $0.org.caseInsensitiveCompare(org) == .orderedSame }
        }
        for org in installed where !contains(org) { items.append(OrgPickerItem(org: org, approved: true)) }
        if source == .gitHubApp {
            for org in memberOrgs where !contains(org) { items.append(OrgPickerItem(org: org, approved: false)) }
        }
        if let current, !contains(current) {
            var approved = true
            if source == .gitHubApp, case .notInstalled = currentAccess { approved = false }
            items.insert(OrgPickerItem(org: current, approved: approved), at: 0)
        }
        return items
    }

    /// The orgs an account switch may select: the installed ones first, then the user's other orgs.
    public static func candidates(installed: [String], memberOrgs: [String]) -> [String] {
        items(source: .gitHubApp, installed: installed, memberOrgs: memberOrgs, current: nil, currentAccess: nil)
            .map(\.org)
    }
}

/// No-org mode's install on the user's own account: who it is for, the page that installs it there and
/// the installation, once there is one.
public struct PersonalInstallTarget: Equatable, Sendable {
    public let login: String
    /// Preselects the user's account when it carries `target_id`; see `AccessChecker.installURL`.
    public let installURL: URL
    public let installationID: Int64?

    public init(login: String, installURL: URL, installationID: Int64?) {
        self.login = login
        self.installURL = installURL
        self.installationID = installationID
    }
}

/// What Settings and the popover say about an app account's access to its org.
public enum OrgAccessNotice: Equatable, Sendable {
    /// The org hasn't installed PullBull.
    case notApproved(org: String, installURL: URL)
    /// No org has installed PullBull, none is known that could be asked, and it isn't installed on the
    /// user's own account either: the user installs it there. `ownerURL` is the plain install page, for
    /// an owner installing it on an org instead.
    case personalInstall(login: String, installURL: URL, ownerURL: URL)
    case ssoRequired(org: String, url: URL?)
    /// Installed for selected repositories only: works, with less coverage.
    case selectedRepositoriesOnly
    /// The user's own installation covers selected repositories; `changeURL` is where they change them.
    case personalSelectedRepositories(changeURL: URL?)

    public static let personalFooter = "Using PullBull for an organization? An owner installs it there."

    /// Nil for `gh` accounts, and for an app account with full or not yet known access. With no org,
    /// `access` is that of the installation on the user's own account (the personal scope), described by
    /// `personal`.
    public static func notice(
        source: AccountSource, org: String?, access: OrgAccess?, installURL: URL, personal: PersonalInstallTarget
    ) -> OrgAccessNotice? {
        guard source == .gitHubApp else { return nil }
        guard let org else {
            switch access {
            case .notInstalled:
                return .personalInstall(login: personal.login, installURL: personal.installURL, ownerURL: installURL)
            case .ok(false, _):
                return .personalSelectedRepositories(
                    changeURL: personal.installationID.map(AccessChecker.installationSettingsURL(id:)))
            case .ok(true, _), .ssoRequired, nil: return nil
            }
        }
        switch access {
        case .notInstalled(let url): return .notApproved(org: org, installURL: url)
        case .ssoRequired(let url): return .ssoRequired(org: org, url: url)
        case .ok(false, _): return .selectedRepositoriesOnly
        case .ok(true, _), nil: return nil
        }
    }

    public var title: String {
        switch self {
        case .notApproved(let org, _): "\(org) hasn't approved PullBull yet"
        case .personalInstall: "Choose the repositories PullBull can see"
        case .ssoRequired(let org, _): "\(org) uses single sign-on. Open the SSO page, then Check Again"
        case .selectedRepositoriesOnly: "PullBull can see only the repositories an owner selected for it."
        case .personalSelectedRepositories: "PullBull can see only the repositories you selected."
        }
    }

    public var body: String? {
        switch self {
        case .notApproved(let org, _):
            "An owner of \(org) needs to install PullBull for the organization. You can send them a request now; GitHub emails them."
        case .personalInstall(let login, let url, _):
            "PullBull didn't find an organization for \(login), so it shows your own repositories. On GitHub, "
                + "install PullBull on your account and choose all repositories or only some. PullBull only reads them."
                + (url.query?.contains("target_id=") == true
                    ? "" : " On GitHub, choose your account (\(login)), not an organization.")
        case .ssoRequired, .selectedRepositoriesOnly, .personalSelectedRepositories:
            nil
        }
    }

    /// Polling can't run until it's resolved; the popover shows the notice in place of the lists.
    public var blocksPolling: Bool {
        switch self {
        case .notApproved, .personalInstall, .ssoRequired: true
        case .selectedRepositoriesOnly, .personalSelectedRepositories: false
        }
    }
}

/// How far the user has got installing PullBull on their own account, for the "Choose your
/// repositories" step (sign-in window, popover, Settings).
public enum InstallWait: Equatable, Sendable {
    case notStarted
    /// Choose Repositories on GitHub was clicked; timed re-checks run while the step shows.
    case waiting
    /// The re-checks' 10 minutes ran out.
    case outOfTime
}

public enum PersonalInstallStep: Equatable, Sendable {
    case intro, waiting, waitedOut
    /// A check failed while waiting, with why; the wait goes on.
    case checkFailedWhileWaiting(RefreshError)
    /// A check failed outside a wait, with why.
    case checkFailed(RefreshError)
    case installedAll
    /// Selected repositories; the count once their list is read.
    case installedSelected(count: Int?)
    /// Installed on an org instead: the org flow takes over.
    case installedOnOrg(String)

    /// From the account's state after the last check: `org` is the selected org (one that installed
    /// PullBull is adopted by the check), `personalAccess` and `personalRepos` the own-account install.
    public static func current(
        org: String?, personalAccess: OrgAccess?, personalRepos: PersonalRepos?, wait: InstallWait,
        lastCheckError: RefreshError?
    ) -> PersonalInstallStep {
        if let org { return .installedOnOrg(org) }
        switch personalAccess {
        case .ok(true, _): return .installedAll
        case .ok(false, _): return .installedSelected(count: personalRepos?.repos?.count)
        case .notInstalled, .ssoRequired, nil: break
        }
        switch wait {
        case .waiting: return lastCheckError.map { .checkFailedWhileWaiting($0) } ?? .waiting
        case .notStarted: return lastCheckError.map { .checkFailed($0) } ?? .intro
        case .outOfTime: return lastCheckError.map { .checkFailed($0) } ?? .waitedOut
        }
    }

    public var isFinished: Bool {
        switch self {
        case .installedAll, .installedSelected, .installedOnOrg: true
        case .intro, .waiting, .waitedOut, .checkFailedWhileWaiting, .checkFailed: false
        }
    }

    /// The state's line; nil for the intro, which is the notice's own copy.
    public var line: String? {
        switch self {
        case .intro: nil
        case .waiting: "Waiting for you to click Install on GitHub…"
        case .waitedOut: "Not installed yet. Click Check Again once you've installed PullBull."
        case .checkFailedWhileWaiting(.offline): "Can't reach GitHub. Still checking…"
        case .checkFailedWhileWaiting(let error): "\(Self.message(error)). Still checking…"
        case .checkFailed(.offline): "Can't reach GitHub. Check your connection, then Check Again."
        case .checkFailed(let error): "\(Self.message(error)). Click Check Again to retry."
        case .installedAll: "PullBull can see all your repositories."
        case .installedSelected(let count?):
            "PullBull can see \(count) of your repositories. Change them any time in Settings."
        case .installedSelected(nil):
            "PullBull can see the repositories you selected. Change them any time in Settings."
        case .installedOnOrg(let org): "PullBull is installed on \(org). Showing \(org)."
        }
    }

    /// A failed check's reason as a poll would give it; this step is only for GitHub App accounts.
    private static func message(_ error: RefreshError) -> String {
        error.message(org: nil, source: .gitHubApp)
    }

    /// A second, quieter line under `line`.
    public var detail: String? {
        self == .waiting ? "This step finishes by itself." : nil
    }

    /// "Using PullBull for an organization?" and the owner's link, until the step is finished.
    public var showsFooter: Bool { !isFinished }

    /// For the timed re-checks: they stop once installed anywhere.
    public var recheckResult: RecheckResult { isFinished ? .done : .unchanged }
}

/// The Settings account picker: signed-in app accounts, then `gh` logins.
public enum AccountPicker {
    /// The current account stays listed in its section even when its source no longer has it.
    public static func sections(
        appAccounts: [AccountSummary], ghLogins: [String], current: AccountRef?
    ) -> (app: [AccountRef], gh: [AccountRef]) {
        var app = appAccounts.map(\.ref)
        var gh = ghLogins.map { AccountRef(login: $0, source: .gh) }
        if let current {
            switch current.source {
            case .gitHubApp: if !app.contains(current) { app.insert(current, at: 0) }
            case .gh: if !gh.contains(current) { gh.insert(current, at: 0) }
            }
        }
        return (app, gh)
    }

    /// "Sign in with GitHub to stop depending on gh." shows for a current `gh` account when sign-in works.
    public static func offersSignIn(current: AccountRef?, canSignIn: Bool) -> Bool {
        canSignIn && current?.source == .gh
    }
}

/// What a Sign Out deletes besides the account itself.
public enum SignOutPolicy {
    /// An app account and a `gh` login of the same login share that login's remembered org and its
    /// `<login>@*` caches (both are keyed by login). Signing out of one keeps them only while PullBull
    /// still holds the other: a signed-in app account (listed in `appLogins`), or a `gh` login that is
    /// the current account after this sign-out. GitHub CLI merely listing the login doesn't count, so
    /// signing out of both sources deletes them. `current` is the current account before signing out;
    /// signing out of it leaves none.
    public static func keepsSharedData(of account: AccountRef, current: AccountRef?, appLogins: [String]) -> Bool {
        switch account.source {
        case .gitHubApp:
            let currentAfter = current == account ? nil : current
            return currentAfter == AccountRef(login: account.login, source: .gh)
        case .gh:
            return appLogins.contains(account.login)
        }
    }
}

/// The avatar images an account's cached lists and details may have put in the avatar cache: the URLs
/// GitHub sent, and the `github.com/<login>.png` images details draw for the people they name.
public enum CachedAvatars {
    public static func urls(snapshots: [Snapshot], details: [PRDetail], issueDetails: [IssueDetail]) -> Set<URL> {
        var urls: Set<URL> = []
        var logins: Set<String> = []
        func add(_ issue: BoardIssue) {
            if let author = issue.author { logins.insert(author) }
            for assignee in issue.assignees {
                logins.insert(assignee.login)
                if let url = assignee.avatarURL { urls.insert(url) }
            }
        }
        for snapshot in snapshots {
            for pr in snapshot.reviewCandidates + snapshot.mine + snapshot.team + snapshot.recentlyClosed {
                logins.insert(pr.author)
                if let url = pr.authorAvatarURL { urls.insert(url) }
                for review in pr.latestReviews { logins.insert(review.author) }
                for case .user(let login) in pr.reviewRequests { logins.insert(login) }
            }
            for issue in snapshot.boardIssues + (snapshot.assignedIssues ?? []) + (snapshot.createdIssues ?? []) {
                add(issue)
            }
        }
        for detail in details {
            for review in detail.reviews { logins.insert(review.author) }
            for comment in detail.comments { logins.insert(comment.author) }
        }
        for detail in issueDetails {
            add(detail.issue)
            for comment in detail.lastComments { logins.insert(comment.author) }
            for linked in detail.linkedPRs { logins.insert(linked.author) }
        }
        for login in logins {
            if let url = profileImageURL(login) { urls.insert(url) }
        }
        return urls
    }

    /// The account's own avatar: the one GitHub sent at sign-in, and the profile image.
    public static func own(login: String, avatarURL: URL?) -> Set<URL> {
        var urls: Set<URL> = []
        if let avatarURL { urls.insert(avatarURL) }
        if let url = profileImageURL(login) { urls.insert(url) }
        return urls
    }

    /// The image the detail views load for a login.
    public static func profileImageURL(_ login: String) -> URL? {
        URL(string: "https://github.com/\(login).png")
    }
}
