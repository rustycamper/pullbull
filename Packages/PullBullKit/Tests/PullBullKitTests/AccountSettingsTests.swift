import Foundation
import Testing
@testable import PullBullKit

private let install = URL(string: "https://github.com/apps/pullbull-for-macos/installations/new")!

@Suite struct OrgPickerTests {
    @Test func ghListsEveryOrgEnabled() {
        let items = OrgPicker.items(source: .gh, installed: ["acme", "octo"], memberOrgs: ["other"], current: "acme", currentAccess: nil)
        #expect(items == [OrgPickerItem(org: "acme", approved: true), OrgPickerItem(org: "octo", approved: true)])
    }

    @Test func ghKeepsACurrentOrgNoLongerListed() {
        let items = OrgPicker.items(source: .gh, installed: ["acme"], memberOrgs: [], current: "gone", currentAccess: nil)
        #expect(items.map(\.org) == ["gone", "acme"])
        #expect(items.allSatisfy { $0.approved })
    }

    @Test func appListsInstalledThenOthersNotApproved() {
        let items = OrgPicker.items(
            source: .gitHubApp, installed: ["acme"], memberOrgs: ["ACME", "initech", "octo"], current: "acme",
            currentAccess: .ok(allRepos: true, canReadProjects: true))
        #expect(items == [
            OrgPickerItem(org: "acme", approved: true),
            OrgPickerItem(org: "initech", approved: false),
            OrgPickerItem(org: "octo", approved: false),
        ])
        #expect(items[1].label == "initech — Not approved")
        #expect(items[0].label == "acme")
    }

    @Test func appCurrentOrgNotInstalledIsListedNotApproved() {
        let items = OrgPicker.items(
            source: .gitHubApp, installed: [], memberOrgs: [], current: "initech",
            currentAccess: .notInstalled(install))
        #expect(items == [OrgPickerItem(org: "initech", approved: false)])
    }

    @Test func appCurrentOrgWithUnknownAccessStaysEnabled() {
        // Installations unreadable (offline): the saved org is not marked as unapproved on a guess.
        let items = OrgPicker.items(source: .gitHubApp, installed: [], memberOrgs: [], current: "acme", currentAccess: nil)
        #expect(items == [OrgPickerItem(org: "acme", approved: true)])
    }

    @Test func appCurrentOrgUnderSSOIsNotMarkedUnapproved() {
        // Installed or not is unknown until the SSO session exists; the notice explains SSO instead.
        let items = OrgPicker.items(
            source: .gitHubApp, installed: [], memberOrgs: ["octo"], current: "initech",
            currentAccess: .ssoRequired(nil))
        #expect(items == [OrgPickerItem(org: "initech", approved: true), OrgPickerItem(org: "octo", approved: false)])
    }

    @Test func orgsToSwitchToListInstalledFirst() {
        #expect(OrgPicker.candidates(installed: ["acme"], memberOrgs: ["ACME", "octo"]) == ["acme", "octo"])
    }

    @Test func appCurrentOrgMatchesAMemberOrgWithoutDuplicating() {
        let items = OrgPicker.items(
            source: .gitHubApp, installed: [], memberOrgs: ["initech"], current: "initech",
            currentAccess: .notInstalled(install))
        #expect(items == [OrgPickerItem(org: "initech", approved: false)])
    }
}

private let personalInstall = URL(string: "https://github.com/apps/pullbull-for-macos/installations/new/permissions?target_id=7")!
private let target = PersonalInstallTarget(login: "solo", installURL: personalInstall, installationID: 42)

private func notice(_ source: AccountSource, org: String?, access: OrgAccess?) -> OrgAccessNotice? {
    OrgAccessNotice.notice(source: source, org: org, access: access, installURL: install, personal: target)
}

@Suite struct OrgAccessNoticeTests {
    @Test func ghAccountsNeverShowOne() {
        #expect(notice(.gh, org: nil, access: nil) == nil)
        #expect(notice(.gh, org: "acme", access: .notInstalled(install)) == nil)
    }

    /// No org and no installation anywhere, not even on the user's own account: personal copy, with the
    /// owner's link kept in a footer.
    @Test func appAccountWithoutAnOrg() {
        let notice = notice(.gitHubApp, org: nil, access: .notInstalled(install))
        #expect(notice == .personalInstall(login: "solo", installURL: personalInstall, ownerURL: install))
        #expect(notice?.title == "Choose the repositories PullBull can see")
        #expect(notice?.body == "PullBull didn't find an organization for solo, so it shows your own repositories. "
            + "On GitHub, install PullBull on your account and choose all repositories or only some. PullBull only reads them.")
        #expect(notice?.blocksPolling == true)
        #expect(OrgAccessNotice.personalFooter == "Using PullBull for an organization? An owner installs it there.")
    }

    /// Without the account's ID the install page can't preselect it, so the copy says which to pick.
    @Test func appAccountWithoutAnOrgAndNoPreselection() {
        let untargeted = PersonalInstallTarget(login: "solo", installURL: install, installationID: nil)
        let notice = OrgAccessNotice.notice(
            source: .gitHubApp, org: nil, access: .notInstalled(install), installURL: install, personal: untargeted)
        #expect(notice?.body?.hasSuffix("PullBull only reads them. On GitHub, choose your account (solo), not an organization.") == true)
    }

    /// No org, installed on the user's own account: polling runs; selected repositories say so, with
    /// the user's own settings page to change them.
    @Test func appAccountWithAPersonalInstallation() {
        #expect(notice(.gitHubApp, org: nil, access: .ok(allRepos: true, canReadProjects: false)) == nil)
        let selected = notice(.gitHubApp, org: nil, access: .ok(allRepos: false, canReadProjects: false))
        #expect(selected == .personalSelectedRepositories(
            changeURL: URL(string: "https://github.com/settings/installations/42")!))
        #expect(selected?.title == "PullBull can see only the repositories you selected.")
        #expect(selected?.blocksPolling == false)
    }

    @Test func personalSelectionWithoutAnInstallationIDHasNoLink() {
        let noID = PersonalInstallTarget(login: "solo", installURL: personalInstall, installationID: nil)
        #expect(OrgAccessNotice.notice(
            source: .gitHubApp, org: nil, access: .ok(allRepos: false, canReadProjects: false), installURL: install,
            personal: noID) == .personalSelectedRepositories(changeURL: nil))
    }

    /// No org with the installations not read yet: nothing is claimed until they are.
    @Test func appAccountWithoutAnOrgBeforeInstallationsLoad() {
        #expect(notice(.gitHubApp, org: nil, access: nil) == nil)
    }

    @Test func notInstalled() {
        let other = URL(string: "https://github.com/apps/other/installations/new")!
        let notice = notice(.gitHubApp, org: "initech", access: .notInstalled(other))
        #expect(notice == .notApproved(org: "initech", installURL: other))
        #expect(notice?.title == "initech hasn't approved PullBull yet")
        #expect(notice?.body
            == "An owner of initech needs to install PullBull for the organization. You can send them a request now; GitHub emails them.")
        #expect(notice?.blocksPolling == true)
    }

    @Test func ssoRequired() {
        let sso = URL(string: "https://github.com/orgs/initech/sso")!
        let notice = notice(.gitHubApp, org: "initech", access: .ssoRequired(sso))
        #expect(notice == .ssoRequired(org: "initech", url: sso))
        #expect(notice?.title == "initech uses single sign-on. Open the SSO page, then Check Again")
        #expect(notice?.body == nil)
        #expect(notice?.blocksPolling == true)
    }

    @Test func selectedRepositoriesOnly() {
        let notice = notice(.gitHubApp, org: "acme", access: .ok(allRepos: false, canReadProjects: true))
        #expect(notice == .selectedRepositoriesOnly)
        #expect(notice?.title == "PullBull can see only the repositories an owner selected for it.")
        #expect(notice?.blocksPolling == false)
    }

    @Test func fullAccessOrUnknownShowsNothing() {
        #expect(notice(.gitHubApp, org: "acme", access: .ok(allRepos: true, canReadProjects: false)) == nil)
        #expect(notice(.gitHubApp, org: "acme", access: nil) == nil)
    }
}

@Suite struct PersonalInstallStepTests {
    private func step(
        org: String? = nil, access: OrgAccess? = .notInstalled(install), repos: PersonalRepos? = nil,
        wait: InstallWait = .notStarted, failed: RefreshError? = nil
    ) -> PersonalInstallStep {
        PersonalInstallStep.current(org: org, personalAccess: access, personalRepos: repos, wait: wait, lastCheckError: failed)
    }

    @Test func waitingStates() {
        #expect(step() == .intro)
        #expect(step(wait: .waiting) == .waiting)
        #expect(step(wait: .outOfTime) == .waitedOut)
        #expect(step(wait: .waiting).line == "Waiting for you to click Install on GitHub…")
        #expect(step(wait: .waiting).detail == "This step finishes by itself.")
        #expect(step(wait: .outOfTime).line == "Not installed yet. Click Check Again once you've installed PullBull.")
        #expect(step().line == nil)
    }

    /// A failed check isn't "not installed": it keeps waiting.
    @Test func offlineWhileWaiting() {
        #expect(step(wait: .waiting, failed: .offline) == .checkFailedWhileWaiting(.offline))
        #expect(step(wait: .waiting, failed: .offline).line == "Can't reach GitHub. Still checking…")
        #expect(step(failed: .offline) == .checkFailed(.offline))
        #expect(step(failed: .offline).line == "Can't reach GitHub. Check your connection, then Check Again.")
        #expect(step(wait: .outOfTime, failed: .offline) == .checkFailed(.offline))
    }

    /// A check that reached GitHub, or failed for another reason, says why instead of "check your connection".
    @Test func otherFailuresSayWhy() {
        let tls = RefreshError.unreachable(.secureConnectionFailed)
        #expect(step(wait: .waiting, failed: tls) == .checkFailedWhileWaiting(tls))
        #expect(step(wait: .waiting, failed: tls).line == "Couldn't reach GitHub (secure connection failed). Still checking…")
        #expect(step(wait: .waiting, failed: .forbidden).line == "GitHub refused access (403). Still checking…")
        #expect(step(failed: tls) == .checkFailed(tls))
        #expect(step(failed: tls).line == "Couldn't reach GitHub (secure connection failed). Click Check Again to retry.")
        #expect(step(wait: .outOfTime, failed: .forbidden).line == "GitHub refused access (403). Click Check Again to retry.")
        // An app account gets no `gh` instructions.
        #expect(step(failed: .unauthorized).line == "GitHub rejected the sign-in. Click Check Again to retry.")
        #expect(!step(failed: .forbidden).isFinished)
        #expect(step(wait: .waiting, failed: .forbidden).recheckResult == .unchanged)
    }

    @Test func installed() {
        let all = step(access: .ok(allRepos: true, canReadProjects: false), wait: .waiting)
        #expect(all == .installedAll)
        #expect(all.line == "PullBull can see all your repositories.")
        #expect(all.isFinished)
        let some = step(access: .ok(allRepos: false, canReadProjects: false), repos: .selected(["solo/a", "solo/b"]))
        #expect(some == .installedSelected(count: 2))
        #expect(some.line == "PullBull can see 2 of your repositories. Change them any time in Settings.")
        #expect(step(access: .ok(allRepos: false, canReadProjects: false), repos: .selected(["solo/a"])).line
            == "PullBull can see 1 of your repositories. Change them any time in Settings.")
        #expect(step(access: .ok(allRepos: false, canReadProjects: false)) == .installedSelected(count: nil))
        #expect(step(access: .ok(allRepos: false, canReadProjects: false)).line
            == "PullBull can see the repositories you selected. Change them any time in Settings.")
    }

    @Test func installedOnAnOrgHandsOff() {
        let org = step(org: "acme", wait: .waiting)
        #expect(org == .installedOnOrg("acme"))
        #expect(org.line == "PullBull is installed on acme. Showing acme.")
        #expect(org.isFinished)
        #expect(!org.showsFooter)
        #expect(step(wait: .waiting).showsFooter)
        #expect(!step(access: .ok(allRepos: true, canReadProjects: false)).showsFooter)
    }

    @Test func aCheckFinishesTheWaitOnlyOnceInstalled() {
        #expect(step(wait: .waiting).recheckResult == .unchanged)
        #expect(step(wait: .waiting, failed: .offline).recheckResult == .unchanged)
        #expect(step(access: .ok(allRepos: true, canReadProjects: false)).recheckResult == .done)
        #expect(step(org: "acme").recheckResult == .done)
    }
}

@Suite struct AccountPickerTests {
    @Test func appAccountsThenGhLogins() {
        let sections = AccountPicker.sections(
            appAccounts: [AccountSummary(userID: 1, login: "devon")], ghLogins: ["frank", "alt"],
            current: AccountRef(login: "frank", source: .gh))
        #expect(sections.app == [AccountRef(login: "devon", source: .gitHubApp)])
        #expect(sections.gh == [AccountRef(login: "frank", source: .gh), AccountRef(login: "alt", source: .gh)])
    }

    @Test func sameLoginInBothSourcesIsListedTwice() {
        let sections = AccountPicker.sections(
            appAccounts: [AccountSummary(userID: 1, login: "frank")], ghLogins: ["frank"], current: nil)
        #expect(sections.app == [AccountRef(login: "frank", source: .gitHubApp)])
        #expect(sections.gh == [AccountRef(login: "frank", source: .gh)])
    }

    @Test func currentGhLoginNoLongerInGhStaysListed() {
        let sections = AccountPicker.sections(
            appAccounts: [], ghLogins: ["alt"], current: AccountRef(login: "gone", source: .gh))
        #expect(sections.gh == [AccountRef(login: "gone", source: .gh), AccountRef(login: "alt", source: .gh)])
    }

    @Test func currentAppAccountMissingFromSummariesStaysListed() {
        let sections = AccountPicker.sections(
            appAccounts: [], ghLogins: [], current: AccountRef(login: "devon", source: .gitHubApp))
        #expect(sections.app == [AccountRef(login: "devon", source: .gitHubApp)])
        #expect(sections.gh.isEmpty)
    }

    // MARK: Footer menu

    private let devon = AccountRef(login: "devon", source: .gitHubApp)
    private let frank = AccountRef(login: "frank", source: .gh)
    private let alt = AccountRef(login: "alt", source: .gh)

    @Test func menuListsAppAccountsThenGhThenActions() {
        let entries = AccountPicker.menu(
            appAccounts: [AccountSummary(userID: 1, login: "devon")], ghLogins: ["frank", "alt"],
            current: frank, currentOrg: "initech", orgByAccount: ["devon": "acme"], signedOut: [], canSignIn: true)
        #expect(entries == [
            .account(devon, detail: "acme", isCurrent: false),
            .separator,
            .header("GitHub CLI"),
            .account(frank, detail: "initech", isCurrent: true),
            .account(alt, detail: nil, isCurrent: false),
            .separator,
            .addAccount,
            .settings,
        ])
    }

    @Test func menuShowsPersonalAndSignedOut() {
        let entries = AccountPicker.menu(
            appAccounts: [AccountSummary(userID: 1, login: "devon")], ghLogins: ["frank"],
            current: frank, currentOrg: nil, orgByAccount: ["devon": "acme"], signedOut: [devon], canSignIn: false)
        #expect(entries.first == .account(devon, detail: "Signed out", isCurrent: false))
        #expect(entries.contains(.account(frank, detail: "personal", isCurrent: true)))
        // Without sign-in, no Add Account….
        #expect(!entries.contains(.addAccount))
        #expect(entries.last == .settings)
    }

    @Test func menuWithOnlyGhAccountsStartsWithItsHeader() {
        let entries = AccountPicker.menu(
            appAccounts: [], ghLogins: ["frank"], current: frank, currentOrg: "initech", orgByAccount: [:],
            signedOut: [], canSignIn: true)
        #expect(entries.first == .header("GitHub CLI"))
    }

    @Test func menuWithNoAccountsOffersOnlyActions() {
        let entries = AccountPicker.menu(
            appAccounts: [], ghLogins: [], current: nil, currentOrg: nil, orgByAccount: [:], signedOut: [],
            canSignIn: true)
        #expect(entries == [.addAccount, .settings])
    }

    @Test func ghOfferOnlyForAGhAccountWhenSignInWorks() {
        #expect(AccountPicker.offersSignIn(current: AccountRef(login: "p", source: .gh), canSignIn: true))
        #expect(!AccountPicker.offersSignIn(current: AccountRef(login: "p", source: .gh), canSignIn: false))
        #expect(!AccountPicker.offersSignIn(current: AccountRef(login: "p", source: .gitHubApp), canSignIn: true))
        #expect(!AccountPicker.offersSignIn(current: nil, canSignIn: true))
    }
}

@Suite struct SignOutPolicyTests {
    private let app = AccountRef(login: "frank", source: .gitHubApp)
    private let gh = AccountRef(login: "frank", source: .gh)

    /// Signing out of an app account keeps the data only for a same-login `gh` account PullBull is
    /// still using: the current one after this sign-out.
    @Test func currentGhLoginKeepsAnAppAccountsData() {
        #expect(SignOutPolicy.keepsSharedData(of: app, current: gh, appLogins: ["frank"]))
        #expect(!SignOutPolicy.keepsSharedData(of: app, current: app, appLogins: ["frank"]))
        #expect(!SignOutPolicy.keepsSharedData(of: app, current: nil, appLogins: ["frank"]))
        #expect(!SignOutPolicy.keepsSharedData(
            of: app, current: AccountRef(login: "other", source: .gh), appLogins: ["frank", "other"]))
    }

    /// Signing out of a `gh` login keeps the data while an app account of the same login is signed in.
    @Test func signedInAppAccountKeepsAGhLoginsData() {
        #expect(SignOutPolicy.keepsSharedData(of: gh, current: gh, appLogins: ["frank"]))
        #expect(!SignOutPolicy.keepsSharedData(of: gh, current: gh, appLogins: []))
        #expect(!SignOutPolicy.keepsSharedData(of: gh, current: gh, appLogins: ["other"]))
    }

    /// One Sign Out as the app runs it: whether the shared data stays, and the settings after.
    private func signOut(_ account: AccountRef, from settings: inout AppSettings) -> Bool {
        let keeps = SignOutPolicy.keepsSharedData(
            of: account, current: settings.accountRef, appLogins: settings.appAccounts.map(\.login))
        settings.signOut(account, keepingRememberedOrg: keeps)
        return keeps
    }

    private func bothSignedIn(current: AccountRef) -> AppSettings {
        var s = AppSettings()
        s.upsert(AccountSummary(userID: 1, login: "frank"))
        s.choose(current, org: "acme")
        s.orgByAccount["frank"] = "acme"
        return s
    }

    /// gh first (the app account still holds the data), then the app account: gone on the second.
    @Test func signingOutOfGhThenTheAppDeletesTheData() {
        var s = bothSignedIn(current: gh)
        #expect(signOut(gh, from: &s))
        #expect(s.orgByAccount["frank"] == "acme")
        s.choose(app, org: "acme")
        #expect(!signOut(app, from: &s))
        #expect(s.orgByAccount["frank"] == nil)
    }

    /// The app account first: gh still lists the login, but PullBull isn't using it, so the data goes.
    @Test func signingOutOfTheAppThenGhDeletesTheData() {
        var s = bothSignedIn(current: app)
        #expect(!signOut(app, from: &s))
        #expect(s.orgByAccount["frank"] == nil)
        s.choose(gh, org: nil)
        #expect(!signOut(gh, from: &s))
    }

    /// The app account isn't current and its `gh` login is: the `gh` account keeps the data.
    @Test func signingOutOfANonCurrentAppAccountKeepsTheCurrentGhData() {
        var s = bothSignedIn(current: gh)
        #expect(signOut(app, from: &s))
        #expect(s.orgByAccount["frank"] == "acme")
        #expect(s.accountRef == gh)
        #expect(!s.signedOutByUser)
    }

    @Test func ownAvatars() {
        let avatar = URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!
        #expect(CachedAvatars.own(login: "frank", avatarURL: avatar)
            == [avatar, URL(string: "https://github.com/frank.png")!])
        #expect(CachedAvatars.own(login: "frank", avatarURL: nil) == [URL(string: "https://github.com/frank.png")!])
    }
}

@Suite struct CachedAvatarsTests {
    private let at = Date(timeIntervalSince1970: 1_800_000_000)

    private func pr(_ number: Int, author: String, avatar: URL?, reviewer: String, requested: String) -> PullRequest {
        PullRequest(
            key: PRKey(repo: "o/r", number: number), title: "t", url: URL(string: "https://x/\(number)")!,
            author: author, authorAvatarURL: avatar, state: .open, isDraft: false,
            createdAt: at, updatedAt: at, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
            headCommitDate: at, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: [Review(author: reviewer, state: .approved, submittedAt: at)],
            reviewRequests: [.user(requested), .team("core")])
    }

    @Test func collectsListAndDetailAvatars() {
        let aliceAvatar = URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!
        let carolAvatar = URL(string: "https://avatars.githubusercontent.com/u/3?v=4")!
        let key = PRKey(repo: "o/r", number: 1)
        var snapshot = Snapshot(
            fetchedAt: at, org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
            reviewCandidates: [pr(1, author: "alice", avatar: aliceAvatar, reviewer: "bob", requested: "dave")],
            mine: [], team: [], recentlyClosed: [], boardIssues: [])
        snapshot.assignedIssues = [BoardIssue(
            key: PRKey(repo: "o/r", number: 2), title: "i", url: URL(string: "https://x/2")!, isOpen: true,
            author: "erin", assignees: [Assignee(login: "carol", avatarURL: carolAvatar)])]
        let detail = PRDetail(
            key: key, body: "", checks: [], reviews: [Review(author: "frank", state: .commented, submittedAt: at)],
            comments: [Comment(author: "gina", body: "", createdAt: at)], files: [])
        let issueDetail = IssueDetail(
            key: key, issue: BoardIssue(key: key, title: "i", url: URL(string: "https://x/1")!, isOpen: true, author: "hank"),
            body: "", commentTotal: 1, lastComments: [Comment(author: "ivy", body: "", createdAt: at)], linkedPRs: [])

        let urls = CachedAvatars.urls(snapshots: [snapshot], details: [detail], issueDetails: [issueDetail])

        #expect(urls.contains(aliceAvatar))
        #expect(urls.contains(carolAvatar))
        for login in ["alice", "bob", "dave", "carol", "erin", "frank", "gina", "hank", "ivy"] {
            #expect(urls.contains(URL(string: "https://github.com/\(login).png")!), "\(login)")
        }
        #expect(!urls.contains(URL(string: "https://github.com/core.png")!))
    }

    @Test func storeReadsOnlyThatAccountsCaches() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pullbull-avatars-\(UUID().uuidString)").appendingPathComponent("cache")
        let store = SnapshotStore(directory: dir)
        let mine = Snapshot(
            fetchedAt: at, org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
            reviewCandidates: [pr(1, author: "alice", avatar: nil, reviewer: "bob", requested: "dave")],
            mine: [], team: [], recentlyClosed: [], boardIssues: [])
        let theirs = Snapshot(
            fetchedAt: at, org: OrgContext(org: "o", viewer: "other", members: [], myTeams: [], repos: []),
            reviewCandidates: [pr(2, author: "zed", avatar: nil, reviewer: "zed", requested: "zed")],
            mine: [], team: [], recentlyClosed: [], boardIssues: [])
        try await store.save(mine, account: "me", scope: .org("o"))
        try await store.save(theirs, account: "me-2", scope: .org("o"))
        let key = PRKey(repo: "o/r", number: 1)
        try await store.saveDetail(
            PRDetail(key: key, body: "", checks: [], reviews: [], comments: [Comment(author: "gina", body: "", createdAt: at)], files: []),
            account: "me")
        try await store.saveIssueDetail(
            IssueDetail(
                key: key, issue: BoardIssue(key: key, title: "i", url: URL(string: "https://x/1")!, isOpen: true),
                body: "", commentTotal: 1, lastComments: [Comment(author: "ivy", body: "", createdAt: at)], linkedPRs: []),
            account: "me")

        let urls = await store.avatarURLs(account: "me")

        #expect(urls.contains(URL(string: "https://github.com/alice.png")!))
        #expect(urls.contains(URL(string: "https://github.com/gina.png")!))
        #expect(urls.contains(URL(string: "https://github.com/ivy.png")!))
        #expect(!urls.contains(URL(string: "https://github.com/zed.png")!))
    }
}
