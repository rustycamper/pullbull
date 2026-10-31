import Foundation
import Testing
@testable import PullBullKit

private let at = Date(timeIntervalSince1970: 1_800_000_000.123456)

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("pullbull-store-\(UUID().uuidString)")
        .appendingPathComponent("cache")
}

private func sample() -> Snapshot {
    let pr = PullRequest(
        key: PRKey(repo: "o/r", number: 7), title: "t", url: URL(string: "https://x/7")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: at, updatedAt: at, closedAt: nil, headRef: "h", baseRef: "main", ci: .none,
        headCommitDate: at, commentCount: 1, lastCommentAuthor: "bob",
        latestReviews: [], reviewRequests: [])
    return Snapshot(
        fetchedAt: at,
        org: OrgContext(org: "o", viewer: "me", members: [], myTeams: [], repos: []),
        reviewCandidates: [pr], mine: [], team: [], recentlyClosed: [], boardIssues: [])
}

@Suite struct SnapshotStoreTests {
    @Test func roundTrip() async throws {
        let store = SnapshotStore(directory: tempDir())
        let s = sample()
        try await store.save(s, account: "me", scope: .org("o"))
        #expect(await store.load(account: "me", scope: .org("o")) == s)
    }

    @Test func keyedByAccountAndOrg() async throws {
        let store = SnapshotStore(directory: tempDir())
        try await store.save(sample(), account: "a", scope: .org("o"))
        #expect(await store.load(account: "b", scope: .org("o")) == nil)
        #expect(await store.load(account: "a", scope: .org("p")) == nil)
    }

    /// The personal scope has a file of its own (`<login>@-personal.json`; an org login can't start with
    /// `-`): an org named like the login, or "personal", can't read it, and Sign Out's `removeAll` deletes
    /// it with the account's other caches.
    @Test func personalScopeNeverSharesAnOrgsFile() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        var personal = sample()
        personal.org = .personal(login: "me", repos: ["dotfiles"], reposComplete: true)
        try await store.save(personal, account: "me", scope: .personal(login: "me"))
        #expect(await store.load(account: "me", scope: .personal(login: "me")) == personal)
        #expect(await store.load(account: "me", scope: .org("me")) == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("me@-personal.json").path))
        #expect(await store.load(account: "me", scope: .org("personal")) == nil)
        try await store.save(sample(), account: "me", scope: .org("me"))
        #expect(await store.load(account: "me", scope: .personal(login: "me")) == personal)
        #expect(await store.load(account: "me", scope: .org("me"))?.scope == .org("o"))

        try await store.removeAll(account: "me")
        #expect(await store.load(account: "me", scope: .personal(login: "me")) == nil)
    }

    /// An org snapshot is written as before: `<login>@<org>.json`, with no new keys an older build would
    /// have to skip.
    @Test func orgSnapshotKeepsItsFileAndFormat() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "a", scope: .org("o"))
        let url = dir.appendingPathComponent("a@o.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let org = try #require(object["org"] as? [String: Any])
        #expect(Set(org.keys) == ["org", "viewer", "members", "myTeams", "repos", "reposComplete"])
        #expect(try #require(await store.load(account: "a", scope: .org("o"))).scope == .org("o"))
    }

    @Test func scopeCoversRepos() {
        #expect(FetchScope.org("acme").covers("someone/else"))
        let owned = FetchScope.personal(login: "me")
        #expect(owned.covers("me/a"))
        #expect(owned.covers("ME/a"))
        #expect(!owned.covers("other/a"))
        let selected = FetchScope.personal(login: "me", repos: ["me/a", "me/b"])
        #expect(selected.covers("me/A"))
        #expect(selected.covers("ME/B"))
        #expect(!selected.covers("me/c"))
        #expect(!selected.covers("other/a"))
    }

    /// Limiting drops other repos from every list, keeps the selection's names for number lookup, and
    /// round-trips through the cache (an org snapshot is left as it is).
    @Test func limitedSnapshotRoundTrips() async throws {
        let issue = { (repo: String) in
            BoardIssue(key: PRKey(repo: repo, number: 1), title: "i", url: URL(string: "https://x/1")!, isOpen: true)
        }
        var s = sample()
        s.org = .personal(login: "me", repos: ["a", "b"], reposComplete: false)
        let pr = s.reviewCandidates[0]
        s.mine = [pr]
        s.assignedIssues = [issue("me/a"), issue("me/b"), issue("o/r")]
        s.createdIssues = [issue("me/b")]
        let scope = FetchScope.personal(login: "me", repos: ["me/a"])
        let limited = s.limited(to: scope)
        #expect(limited.reviewCandidates.isEmpty)
        #expect(limited.mine.isEmpty)
        #expect(limited.assignedIssues?.map(\.key.repo) == ["me/a"])
        #expect(limited.createdIssues == [])
        #expect(limited.org.repos == ["a"])
        #expect(limited.scope == scope)
        #expect(sample().limited(to: .org("o")) == sample())
        #expect(s.limited(to: .personal(login: "me")).scope == .personal(login: "me"))

        let store = SnapshotStore(directory: tempDir())
        try await store.save(limited, account: "me", scope: scope)
        let loaded = try #require(await store.load(account: "me", scope: scope))
        #expect(loaded == limited)
        #expect(loaded.scope == scope)
    }

    @Test func snapshotWithoutBoardFieldsDecodes() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "a", scope: .org("o"))
        let url = dir.appendingPathComponent("a@o.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for key in ["boardProject", "boardTitle", "boardError"] { object[key] = nil }
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let loaded = try #require(await store.load(account: "a", scope: .org("o")))
        #expect(loaded.boardProject == nil)
        #expect(loaded.boardTitle == nil)
        #expect(loaded.boardError == nil)
    }

    /// Items and snapshots cached before node IDs were stored decode without them.
    @Test func cachedItemsWithoutNodeIdsDecode() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "a", scope: .org("o"))
        let url = dir.appendingPathComponent("a@o.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["boardIds"] == nil)
        var prs = try #require(object["reviewCandidates"] as? [[String: Any]])
        prs[0]["nodeId"] = nil
        object["reviewCandidates"] = prs
        object["boardIssues"] = [[
            "key": ["repo": "o/r", "number": 9], "title": "i", "url": "https://x/9", "isOpen": true,
        ]]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let loaded = try #require(await store.load(account: "a", scope: .org("o")))
        #expect(loaded.boardIds == nil)
        #expect(loaded.reviewCandidates.first?.nodeId == nil)
        #expect(loaded.boardIssues.first?.nodeId == nil)
        #expect(loaded.boardIssues.first?.boardItemNodeId == nil)
    }

    @Test func legacySnapshotDecodes() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "a", scope: .org("o"))
        let url = dir.appendingPathComponent("a@o.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for key in ["assignedIssues", "createdIssues", "boardStatusOptions"] { object[key] = nil }
        object["boardIssues"] = [[
            "key": ["repo": "o/r", "number": 9], "title": "i", "url": "https://x/9", "isOpen": true,
        ] as [String: Any]]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let loaded = try #require(await store.load(account: "a", scope: .org("o")))
        #expect(loaded.assignedIssues == nil)
        #expect(loaded.createdIssues == nil)
        #expect(loaded.boardStatusOptions == nil)
        #expect(loaded.assignedIssuesError == nil)
        #expect(loaded.createdIssuesError == nil)
        #expect(loaded.boardIssues.count == 1)
        #expect(loaded.boardIssues[0].key == PRKey(repo: "o/r", number: 9))
        #expect(loaded.boardIssues[0].labels == [])
        #expect(loaded.boardIssues[0].commentCount == 0)
        #expect(loaded.boardIssues[0].status == nil)
    }

    @Test func perListIssueErrorsDecode() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        var s = sample()
        s.createdIssuesError = "incomplete created issues list"
        try await store.save(s, account: "a", scope: .org("o"))
        #expect(await store.load(account: "a", scope: .org("o")) == s)
        // A cache from before the errors were stored per list, with the old single field, still loads.
        let url = dir.appendingPathComponent("a@o.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["createdIssuesError"] = nil
        object["issuesError"] = "GitHub server error 502"
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let loaded = try #require(await store.load(account: "a", scope: .org("o")))
        #expect(loaded.assignedIssuesError == nil)
        #expect(loaded.createdIssuesError == nil)
        #expect(loaded.issuesError(for: .board) == nil)
    }

    @Test func statusOptionColorsDecode() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        var s = sample()
        s.boardStatusOptions = [StatusOption(id: "o1", name: "Todo", color: .gray), StatusOption(id: "o2", name: "Done", color: .green)]
        try await store.save(s, account: "a", scope: .org("o"))
        #expect(await store.load(account: "a", scope: .org("o")) == s)
        // A cache from before colours were stored still loads, with every colour nil.
        let url = dir.appendingPathComponent("a@o.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["boardStatusOptions"] = [["id": "o1", "name": "Todo"], ["id": "o2", "name": "Done"]]
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let loaded = try #require(await store.load(account: "a", scope: .org("o")))
        #expect(loaded.boardStatusOptions == [StatusOption(id: "o1", name: "Todo"), StatusOption(id: "o2", name: "Done")])
    }

    @Test func assignedIssuesFetchedAtDecodes() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        var s = sample()
        s.assignedIssues = []
        s.assignedIssuesFetchedAt = at.addingTimeInterval(-1200)
        try await store.save(s, account: "a", scope: .org("o"))
        #expect(await store.load(account: "a", scope: .org("o")) == s)
        // A cache from before it was stored still loads, with the field nil.
        let url = dir.appendingPathComponent("a@o.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["assignedIssuesFetchedAt"] != nil)
        object["assignedIssuesFetchedAt"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        let loaded = try #require(await store.load(account: "a", scope: .org("o")))
        #expect(loaded.assignedIssuesFetchedAt == nil)
        #expect(loaded.assignedIssues == [])
    }

    @Test func issueListsRoundTrip() async throws {
        let store = SnapshotStore(directory: tempDir())
        var s = sample()
        let issue = BoardIssue(
            key: PRKey(repo: "o/r", number: 3), title: "i", url: URL(string: "https://x/3")!, isOpen: true,
            labels: ["bug"], myAssignment: Assignment(actor: "b", at: at))
        s.assignedIssues = [issue]
        s.createdIssues = []
        s.boardStatusOptions = [StatusOption(id: "o1", name: "Todo")]
        try await store.save(s, account: "me", scope: .org("o"))
        #expect(await store.load(account: "me", scope: .org("o")) == s)
    }

    @Test func corruptFileIsNil() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "a", scope: .org("o"))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("a@o.json"))
        #expect(await store.load(account: "a", scope: .org("o")) == nil)
    }

    @Test func craftedLoginStaysInsideDirectory() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "../../evil", scope: .org("o/x"))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names == [".._.._evil@o_x.json"])
        #expect(await store.load(account: "../../evil", scope: .org("o/x")) != nil)
    }

    @Test func dotOnlyNamesCannotTraverse() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        let key = PRKey(repo: "o/r", number: 1)
        let d = PRDetail(key: key, body: "b", checks: [], reviews: [], comments: [], files: [])
        try await store.saveDetail(d, account: "..")
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("details/__/o_r_1.json").path))
        #expect(await store.loadDetail(key, account: "..") != nil)
    }

    @Test func detailRoundTrip() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        let key = PRKey(repo: "o/r", number: 7)
        let d = PRDetail(key: key, body: "hello", checks: [], reviews: [], comments: [], files: [])
        #expect(await store.loadDetail(key, account: "me") == nil)
        try await store.saveDetail(d, account: "me")
        let back = await store.loadDetail(key, account: "me")
        #expect(back?.body == "hello")
        #expect(back?.key == key)
        #expect(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("details/me/o_r_7.json").path))
        #expect(await store.loadDetail(key, account: "other") == nil)
    }

    @Test func removeAllDeletesOnlyThatAccount() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "octocat", scope: .org("acme"))
        try await store.save(sample(), account: "octocat", scope: .org("octo-org"))
        try await store.save(sample(), account: "octocat-2", scope: .org("acme"))
        let key = PRKey(repo: "o/r", number: 7)
        try await store.saveDetail(
            PRDetail(key: key, body: "b", checks: [], reviews: [], comments: [], files: []), account: "octocat")
        let issue = BoardIssue(key: key, title: "t", url: URL(string: "https://x/7")!, isOpen: true)
        try await store.saveIssueDetail(
            IssueDetail(key: key, issue: issue, body: "", commentTotal: 0, lastComments: [], linkedPRs: []),
            account: "octocat")
        try await store.saveDetail(
            PRDetail(key: key, body: "b", checks: [], reviews: [], comments: [], files: []), account: "octocat-2")

        try await store.removeAll(account: "octocat")

        #expect(await store.load(account: "octocat", scope: .org("acme")) == nil)
        #expect(await store.load(account: "octocat", scope: .org("octo-org")) == nil)
        #expect(await store.loadDetail(key, account: "octocat") == nil)
        #expect(await store.loadIssueDetail(key, account: "octocat") == nil)
        #expect(await store.load(account: "octocat-2", scope: .org("acme")) != nil)
        #expect(await store.loadDetail(key, account: "octocat-2") != nil)
    }

    /// Ask off deletes every account's and scope's Ask index, and nothing else.
    @Test func removeAskIndexesKeepsSnapshots() async throws {
        let dir = tempDir()
        let store = SnapshotStore(directory: dir)
        try await store.save(sample(), account: "octocat", scope: .org("acme"))
        let fm = FileManager.default
        let indexes = [
            store.askIndexURL(account: "octocat", scope: .org("acme")),
            store.askIndexURL(account: "octocat-2", scope: .personal(login: "octocat-2")),
        ]
        for url in indexes {
            for suffix in ["", "-wal", "-shm"] {
                #expect(fm.createFile(atPath: url.path + suffix, contents: Data("x".utf8)))
            }
        }

        try await store.removeAskIndexes()

        for url in indexes {
            for suffix in ["", "-wal", "-shm"] { #expect(!fm.fileExists(atPath: url.path + suffix)) }
        }
        #expect(await store.load(account: "octocat", scope: .org("acme")) != nil)
        try await store.removeAskIndexes()
    }

    @Test func removeAllWithNoFilesDoesNotThrow() async throws {
        let store = SnapshotStore(directory: tempDir())
        try await store.removeAll(account: "octocat")
        try await store.save(sample(), account: "other", scope: .org("acme"))
        try await store.removeAll(account: "octocat")
        #expect(await store.load(account: "other", scope: .org("acme")) != nil)
    }
}

/// Each test gets fresh defaults suites named by a path in a temporary directory, so their plists
/// never land in ~/Library/Preferences (cfprefsd writes an emptied domain back after a delete);
/// teardown removes the directory.
@Suite final class SettingsStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("pullbull-settings-tests-\(UUID().uuidString)", isDirectory: true)
    private var suites: [String] = []

    deinit {
        for name in suites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        try? FileManager.default.removeItem(at: directory)
    }

    private func defaults() -> UserDefaults {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = directory.appendingPathComponent("pullbull-test-\(UUID().uuidString)").path
        suites.append(name)
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func suitesStayOutOfPreferences() {
        let d = defaults()
        d.set(1, forKey: "k")
        d.synchronize()
        let name = suites[0]
        #expect(FileManager.default.fileExists(atPath: name + ".plist"))
        let preferences = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences/\((name as NSString).lastPathComponent).plist")
        #expect(!FileManager.default.fileExists(atPath: preferences.path))
    }

    @Test func settingsDefaults() {
        let s = SettingsStore(defaults: defaults()).load()
        #expect(s.hideApprovedByMe == true)
        #expect(s.badge == .review)
        #expect(s.refreshMinutes == 2)
        #expect(s.notify == NotificationToggles())
        #expect(s.notify.reviewRequested && s.notify.approved && s.notify.changesRequested
            && s.notify.ciFailed && s.notify.newComment)
    }

    @Test func saveThenLoad() {
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.account = "me"
        s.org = nil
        s.refreshMinutes = 5
        s.hideApprovedByMe = false
        store.save(s)
        #expect(store.load() == s)
    }

    /// The hint fold is gone: its stored progress is ignored on load and dropped by the next save.
    @Test func storedHintProgressIsDropped() throws {
        let d = defaults()
        let old = #"{"account":"me","refreshMinutes":5,"searchHints":{"searchesRun":3,"seenVersion":2}}"#
        d.set(Data(old.utf8), forKey: "settings.v1")
        let store = SettingsStore(defaults: d)
        let s = store.load()
        #expect(s.account == "me")
        #expect(s.refreshMinutes == 5)
        store.save(s)
        let data = try #require(d.data(forKey: "settings.v1"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["searchHints"] == nil)
        #expect(object["account"] as? String == "me")
    }

    @Test func newTogglesRoundTrip() throws {
        let d = defaults()
        let store = SettingsStore(defaults: d)
        var s = AppSettings()
        #expect(!s.groupTeamByAuthor && !s.reviewOldestFirst)
        s.groupTeamByAuthor = true
        s.reviewOldestFirst = true
        store.save(s)
        let loaded = store.load()
        #expect(loaded.groupTeamByAuthor && loaded.reviewOldestFirst)
        d.set(Data(#"{"account":"me","org":"o"}"#.utf8), forKey: "settings.v1")
        let old = store.load()
        #expect(!old.groupTeamByAuthor && !old.reviewOldestFirst)
    }

    @Test func followPendingCIDefaultsOn() throws {
        let d = defaults()
        let store = SettingsStore(defaults: d)
        var s = AppSettings()
        #expect(s.followPendingCI)
        s.followPendingCI = false
        store.save(s)
        #expect(!store.load().followPendingCI)
        s.followPendingCI = true
        store.save(s)
        #expect(store.load().followPendingCI)
        d.set(Data(#"{"account":"me","org":"o"}"#.utf8), forKey: "settings.v1")
        #expect(store.load().followPendingCI)
    }

    @Test func savedSearchesSurviveSaveAndLoad() {
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        #expect(s.savedSearches == SavedSearches())
        s.savedSearches.add(name: "Open bugs", query: "~bug is:open")
        s.savedSearches.add(name: "Mine", query: "@me")
        store.save(s)
        #expect(store.load().savedSearches == s.savedSearches)
        #expect(store.load() == s)
    }

    /// Saved searches have a key of their own, `search.saved`, holding a JSON array; the settings
    /// object doesn't carry them.
    @Test func savedSearchesLiveUnderTheirOwnKey() throws {
        let d = defaults()
        var s = AppSettings()
        s.savedSearches.add(name: "Mine", query: "@me")
        SettingsStore(defaults: d).save(s)
        let data = try #require(d.data(forKey: "search.saved"))
        let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(array?.first?["query"] as? String == "@me")
        let settings = try #require(d.data(forKey: "settings.v1"))
        let object = try JSONSerialization.jsonObject(with: settings) as? [String: Any]
        #expect(object?.keys.contains { $0.localizedCaseInsensitiveContains("saved") } == false)
    }

    /// Settings saved before saved searches existed load as before, with none saved.
    @Test func olderSettingsLoadWithNoSavedSearches() throws {
        let d = defaults()
        let old = #"{"account":"me","org":"o","refreshMinutes":5,"searchHints":{"searchesRun":3,"seenVersion":2}}"#
        d.set(Data(old.utf8), forKey: "settings.v1")
        let s = SettingsStore(defaults: d).load()
        #expect(s.account == "me")
        #expect(s.refreshMinutes == 5)
        #expect(s.savedSearches.items.isEmpty)
    }

    /// Unreadable saved searches don't cost the other settings, nor the other way round.
    @Test func eachKeyDecodesOnItsOwn() {
        let d = defaults()
        var s = AppSettings()
        s.refreshMinutes = 10
        s.savedSearches.add(name: "Mine", query: "@me")
        SettingsStore(defaults: d).save(s)
        d.set(Data("[oops".utf8), forKey: "search.saved")
        #expect(SettingsStore(defaults: d).load().refreshMinutes == 10)
        #expect(SettingsStore(defaults: d).load().savedSearches.items.isEmpty)
        SettingsStore(defaults: d).save(s)
        d.set(Data("{oops".utf8), forKey: "settings.v1")
        #expect(SettingsStore(defaults: d).load().savedSearches == s.savedSearches)
    }

    /// Forgetting an account (Sign Out) leaves saved searches alone: they hold no account data.
    @Test func forgettingAnAccountKeepsSavedSearches() {
        var s = AppSettings()
        s.account = "me"
        s.accountSource = .gitHubApp
        s.savedSearches.add(name: "Mine", query: "@me")
        s.forget(AccountRef(login: "me", source: .gitHubApp))
        #expect(s.account == nil)
        #expect(s.savedSearches.items.count == 1)
    }

    @Test func corruptJSONGivesDefaults() {
        let d = defaults()
        d.set(Data("{oops".utf8), forKey: "settings.v1")
        #expect(SettingsStore(defaults: d).load() == AppSettings())
    }

    /// A field of the wrong type gets its default; every other field keeps its saved value, and
    /// the next save keeps them.
    @Test func oneBadFieldKeepsTheOthers() throws {
        let d = defaults()
        let stored = #"{"account":"me","org":"o","refreshMinutes":"ten","compact":true,"hideDrafts":true,"#
            + #""notify":{"approved":false,"ciFailed":"yes"},"toggleHotkey":{"bad":1}}"#
        d.set(Data(stored.utf8), forKey: "settings.v1")
        let store = SettingsStore(defaults: d)
        let s = store.load()
        #expect(s.refreshMinutes == 2)
        #expect(s.toggleHotkey == .togglePopoverDefault)
        #expect(s.account == "me")
        #expect(s.org == "o")
        #expect(s.compact && s.hideDrafts)
        #expect(s.notify.approved == false)
        #expect(s.notify.ciFailed == true)
        store.save(s)
        #expect(store.load() == s)
        #expect(d.object(forKey: SettingsStore.unreadableBackupKey) == nil)
    }

    /// An enum case from a newer version (or one removed since) falls back to that field's default.
    @Test func unknownEnumValueFallsBackForThatFieldOnly() throws {
        let stored = #"{"account":"me","badge":"everything","grouping":"none","lastTab":"later","mode":"issues","#
            + #""lastIssueTab":"board","projectOwner":{"kind":"enterprise","login":"e"},"projectNumber":7}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        #expect(s.badge == .review)
        #expect(s.lastTab == .review)
        #expect(s.grouping == Grouping.none)
        #expect(s.mode == .issues)
        #expect(s.lastIssueTab == .board)
        // An unreadable owner clears the board, so no other owner adopts board 7.
        #expect(s.projectNumber == nil)
        #expect(s.projectOwner == nil)
        #expect(s.account == "me")
    }

    @Test func unreadableBoardOwnerIsNeverAdoptedByTheOrg() throws {
        let stored = #"{"account":"me","org":"o","projectOwner":{"kind":"enterprise","login":"e"},"projectNumber":7}"#
        var s = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        _ = s.reconcileBoard()
        #expect(s.board == nil)
        #expect(s.projectNumber == nil)
    }

    /// An account source this version can't read is never taken for `gh`: the account and its org
    /// are cleared to pick again, and everything else stays.
    @Test func unreadableAccountSourceClearsTheAccount() throws {
        let stored = #"{"account":"me","org":"o","accountSource":"enterprise","refreshMinutes":5,"#
            + #""orgByAccount":{"me":"o"}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        #expect(s.account == nil)
        #expect(s.org == nil)
        #expect(s.accountSource == nil)
        #expect(s.accountRef == nil)
        #expect(s.refreshMinutes == 5)
        #expect(s.orgByAccount == ["me": "o"])
    }

    /// No source at all keeps the legacy reading: a `gh` account.
    @Test func missingAccountSourceStillMeansGh() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"account":"me","org":"o"}"#.utf8))
        #expect(s.accountRef == AccountRef(login: "me", source: .gh))
        #expect(s.org == "o")
    }

    /// Collections drop only their unreadable entries.
    @Test func collectionsSkipOnlyUnreadableEntries() throws {
        let stored = #"{"appAccounts":[{"userID":1,"login":"a"},{"userID":"two","login":"b"},{"userID":3,"login":"c"}],"#
            + #""orgByAccount":{"a":"o1","b":2,"c":"o3"},"laneFolds":{"org:o/3":["x"],"org:o/4":"bad"}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        #expect(s.appAccounts.map(\.login) == ["a", "c"])
        #expect(s.orgByAccount == ["a": "o1", "c": "o3"])
        let folds = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s.laneFolds)) as? [String: [String]]
        #expect(folds == ["org:o/3": ["x"]])
    }

    /// A missing field (renamed or removed, or saved before it existed) gets its default.
    @Test func missingFieldGetsItsDefault() throws {
        let stored = #"{"account":"me","org":"o","hideApprovedByMe":false,"badge":"mine"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        #expect(s.hideApprovedByMe == false)
        #expect(s.badge == .mine)
        #expect(s.refreshMinutes == 2)
        #expect(s.solidBackground == false)
        #expect(s.toggleHotkey == .togglePopoverDefault)
        #expect(s.projectNumber == 3)
    }

    /// Keys this version doesn't know (from a newer one) are ignored.
    @Test func extraKeysAreIgnored() throws {
        let stored = #"{"account":"me","refreshMinutes":5,"futureSetting":{"nested":[1,2]},"anotherOne":true,"#
            + #""notify":{"approved":false,"futureEvent":true}}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(stored.utf8))
        #expect(s.account == "me")
        #expect(s.refreshMinutes == 5)
        #expect(s.notify.approved == false)
    }

    /// Settings that aren't a JSON object load as defaults; the first save keeps one copy of them
    /// under a key of their own, and later saves never replace it.
    @Test func corruptBlobIsBackedUpBeforeTheFirstSave() throws {
        let d = defaults()
        let corrupt = Data("{oops".utf8)
        d.set(corrupt, forKey: "settings.v1")
        let store = SettingsStore(defaults: d)
        var s = store.load()
        #expect(s == AppSettings())
        #expect(d.object(forKey: SettingsStore.unreadableBackupKey) == nil)
        s.refreshMinutes = 5
        store.save(s)
        #expect(d.data(forKey: SettingsStore.unreadableBackupKey) == corrupt)
        #expect(store.load() == s)
        d.set(Data("[]".utf8), forKey: "settings.v1")
        store.save(s)
        #expect(d.data(forKey: SettingsStore.unreadableBackupKey) == corrupt)
    }

    /// A value of the wrong kind under the settings key (not data) is backed up too.
    @Test func nonDataSettingsAreBackedUp() {
        let d = defaults()
        d.set("not data", forKey: "settings.v1")
        let store = SettingsStore(defaults: d)
        store.save(store.load())
        #expect(d.string(forKey: SettingsStore.unreadableBackupKey) == "not data")
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s == AppSettings())
        let n = try JSONDecoder().decode(NotificationToggles.self, from: Data("{}".utf8))
        #expect(n == NotificationToggles())
    }

    @Test func partialObjectKeepsKnownFields() throws {
        let s = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"refreshMinutes":9,"notify":{"approved":false}}"#.utf8))
        #expect(s.refreshMinutes == 9)
        #expect(s.notify.approved == false)
        #expect(s.notify.ciFailed == true)
        #expect(s.badge == .review)
    }

    @Test func noBoardSurvivesSaveAndLoad() {
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.org = "o"
        s.projectNumber = nil
        store.save(s)
        #expect(store.load().projectNumber == nil)
        #expect(AppSettings().projectNumber == 3)
    }

    @Test func settingsSavedBeforeTheShortcutGetTheDefault() throws {
        let old = #"{"account":"me","org":"initech","projectNumber":3,"refreshMinutes":5,"lastTab":"team"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(s.toggleHotkey == .togglePopoverDefault)
        #expect(s.refreshMinutes == 5)
        #expect(s.lastTab == .team)
    }

    @Test func solidBackgroundDefaultsOffAndRoundTrips() throws {
        let old = #"{"account":"me","refreshMinutes":5}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8)).solidBackground == false)
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.solidBackground = true
        store.save(s)
        #expect(store.load().solidBackground)
        #expect(store.load() == s)
    }

    /// Settings saved before Sign Out left no account read as not signed out; an unreadable value too.
    @Test func signedOutByUserDefaultsOffAndRoundTrips() throws {
        let old = #"{"account":"me","refreshMinutes":5}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8)).signedOutByUser == false)
        let garbage = #"{"signedOutByUser":"yes","refreshMinutes":5}"#
        let read = try JSONDecoder().decode(AppSettings.self, from: Data(garbage.utf8))
        #expect(read.signedOutByUser == false)
        #expect(read.refreshMinutes == 5)
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.signedOutByUser = true
        store.save(s)
        #expect(store.load().signedOutByUser)
        #expect(store.load() == s)
    }

    /// Settings saved before Ask read as Ask off, Sonnet and nothing excluded; set values round-trip.
    @Test func askSettingsDefaultAndDecodeOldFile() throws {
        let old = #"{"account":"me","refreshMinutes":5}"#
        let read = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(read.askEnabled == false)
        #expect(read.askModel == "claude-sonnet-5-5")
        #expect(read.askExcludedRepos == [])
        #expect(read.refreshMinutes == 5)
        let garbage = #"{"askEnabled":"yes","askModel":7,"askExcludedRepos":["acme/web",3]}"#
        let partial = try JSONDecoder().decode(AppSettings.self, from: Data(garbage.utf8))
        #expect(partial.askEnabled == false)
        #expect(partial.askModel == AskModel.default.id)
        #expect(partial.askExcludedRepos == ["acme/web"])
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.askEnabled = true
        s.askModel = "claude-haiku-5-5"
        s.askExcludedRepos = ["acme/web", "acme/api"]
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func shortcutOffAndCustomSurviveEncoding() throws {
        var s = AppSettings()
        s.toggleHotkey = nil
        let off = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(off.toggleHotkey == nil)
        s.toggleHotkey = KeyCombo(keyCode: 46, modifiers: [.command, .option])
        let custom = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(custom.toggleHotkey == s.toggleHotkey)
    }

    @Test func legacySettingsGetIssueDefaults() throws {
        let old = #"""
            {"account":"me","org":"initech","projectNumber":3,"projectOrg":"initech","orgByAccount":{},
            "grouping":"none","compact":false,"hideOlderThanTwoMonths":true,"hideApprovedByMe":true,
            "hideDrafts":false,"badge":"review","notify":{"reviewRequested":true,"approved":true,
            "changesRequested":true,"ciFailed":true,"newComment":true},"refreshMinutes":2,"lastTab":"mine",
            "toggleHotkey":null}
            """#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(s.mode == .pullRequests)
        #expect(s.lastIssueTab == .assigned)
        #expect(s.countAssignedIssues == false)
        #expect(s.notify.issueAssigned == false)
        #expect(s.notify.merged == true)
        #expect(s.notify.reviewRequested == true)
        #expect(s.lastTab == .mine)
        #expect(s.grouping == .none)
        #expect(s.toggleHotkey == nil)
    }

    @Test func issueSettingsRoundTrip() throws {
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.mode = .issues
        s.lastIssueTab = .board
        s.countAssignedIssues = true
        s.notify.issueAssigned = true
        s.notify.merged = false
        store.save(s)
        let loaded = store.load()
        #expect(loaded == s)
        #expect(loaded.mode == .issues)
        #expect(loaded.lastIssueTab == .board)
        #expect(loaded.countAssignedIssues)
        #expect(loaded.notify.issueAssigned)
        #expect(!loaded.notify.merged)
    }

    @Test func legacySettingsTieBoardToSavedOrg() throws {
        let s = try JSONDecoder().decode(
            AppSettings.self, from: Data(#"{"account":"me","org":"initech","projectNumber":3}"#.utf8))
        #expect(s.projectOwner == .org("initech"))
        #expect(s.board == .org("initech", 3))
        #expect(s.orgByAccount.isEmpty)
    }

    @Test func legacyProjectOrgBecomesTheOwner() throws {
        let json = #"{"account":"me","org":"other","projectNumber":3,"projectOrg":"initech"}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.projectOwner == .org("initech"))
        // Chosen in another org: not this scope's board until reconciled.
        #expect(s.board == nil)
    }

    /// Settings saved in no-org mode before personal boards: the number (the default 3) has no owner,
    /// and is never read as the user's board #3.
    @Test func legacyNoOrgBoardIsNeverAPersonalBoard() throws {
        for json in [
            #"{"account":"me","projectNumber":3}"#,
            #"{"account":"me"}"#,
        ] {
            var s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(s.projectOwner == nil)
            #expect(s.board == nil)
            #expect(s.reconcileBoard() == true)
            #expect(s.projectNumber == nil)
            #expect(s.projectOwner == .user("me"))
            #expect(s.board == nil)
        }
        // A no-org account that kept the org's board from before (projectOrg was left as it was).
        let kept = #"{"account":"me","projectNumber":3,"projectOrg":"initech"}"#
        var s = try JSONDecoder().decode(AppSettings.self, from: Data(kept.utf8))
        #expect(s.board == nil)
        #expect(s.reconcileBoard() == true)
        #expect(s.projectNumber == nil)
    }

    @Test func boardOwnerRoundTrips() throws {
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.account = "me"
        s.board = .user("me", 2)
        store.save(s)
        let loaded = store.load()
        #expect(loaded.projectOwner == .user("me"))
        #expect(loaded.board == .user("me", 2))
        #expect(loaded == s)
    }

    @Test func orgChangeResetsBoard() {
        var s = AppSettings()
        s.account = "me"
        s.org = "initech"
        // The first org adopts the owner-less default.
        #expect(s.reconcileBoard() == false)
        #expect(s.projectNumber == 3)
        #expect(s.projectOwner == .org("initech"))
        #expect(s.board == .org("initech", 3))

        s.org = "initech"
        #expect(s.reconcileBoard() == false)
        #expect(s.projectNumber == 3)

        s.org = "other"
        #expect(s.reconcileBoard() == true)
        #expect(s.projectNumber == nil)
        #expect(s.projectOwner == .org("other"))
    }

    /// Each owner's board comes back with its scope: switching accounts or orgs and back keeps the
    /// board chosen there instead of falling back to the owner's first.
    @Test func boardComesBackWithItsOwner() {
        var s = AppSettings()
        s.account = "me"
        s.org = "initech"
        _ = s.reconcileBoard()
        s.board = .org("initech", 5)
        s.rememberBoard()

        // Another account in another org: nothing remembered there yet, so the caller picks.
        s.choose(AccountRef(login: "work", source: .gitHubApp), org: "acme")
        #expect(s.reconcileBoard() == true)
        #expect(s.board == nil)
        s.board = .org("acme", 2)
        s.rememberBoard()

        // Back: initech's board returns, and nothing needs picking.
        s.choose(AccountRef(login: "me", source: .gh), org: "initech")
        #expect(s.reconcileBoard() == false)
        #expect(s.board == .org("initech", 5))

        // No-org mode keeps the user's own board the same way.
        s.org = nil
        #expect(s.reconcileBoard() == true)
        s.board = .user("me", 1)
        s.rememberBoard()
        s.org = "acme"
        #expect(s.reconcileBoard() == false)
        #expect(s.board == .org("acme", 2))
        s.org = nil
        #expect(s.reconcileBoard() == false)
        #expect(s.board == .user("me", 1))
    }

    /// Owners are remembered as GitHub compares them: kind and login, without regard to case.
    @Test func rememberedBoardIgnoresLoginCase() {
        var s = AppSettings()
        s.account = "me"
        s.org = "Initech"
        _ = s.reconcileBoard()
        s.board = .org("Initech", 4)
        s.rememberBoard()
        #expect(s.boardByOwner == ["org:initech": 4])
        s.org = "other"
        _ = s.reconcileBoard()
        s.org = "INITECH"
        #expect(s.reconcileBoard() == false)
        #expect(s.projectNumber == 4)
        // A user and an org of the same name are different owners.
        s.org = nil
        s.account = "initech"
        #expect(s.reconcileBoard() == true)
    }

    /// Settings saved before boards were remembered: remembering the board at load (as launch does)
    /// keeps it for its owner through the first switch away and back.
    @Test func boardInUseBeforeUpgradeComesBack() throws {
        let saved = #"{"account":"me","org":"initech","projectNumber":7,"projectOwner":{"kind":"org","login":"initech"}}"#
        var s = try JSONDecoder().decode(AppSettings.self, from: Data(saved.utf8))
        s.rememberBoard()
        s.org = "acme"
        #expect(s.reconcileBoard() == true)
        s.org = "initech"
        #expect(s.reconcileBoard() == false)
        #expect(s.board == .org("initech", 7))
    }

    @Test func rememberedBoardsRoundTrip() throws {
        let store = SettingsStore(defaults: defaults())
        var s = AppSettings()
        s.account = "me"
        s.boardByOwner = ["org:initech": 4, "user:me": 1]
        store.save(s)
        #expect(store.load().boardByOwner == s.boardByOwner)
        // Settings saved before boards were remembered load with none.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"account":"me"}"#.utf8))
        #expect(old.boardByOwner.isEmpty)
    }

    /// No-org mode shows only the user's own boards; org mode never does.
    @Test func scopeChangesReconcileTheBoardOwner() {
        var s = AppSettings()
        s.account = "me"
        s.org = "initech"
        _ = s.reconcileBoard()
        #expect(s.board == .org("initech", 3))

        // Into no-org mode: the org's #3 is not the user's #3.
        s.org = nil
        #expect(s.board == nil)
        #expect(s.reconcileBoard() == true)
        #expect(s.projectNumber == nil)
        #expect(s.boardOwner == .user("me"))
        s.board = .user("me", 3)
        #expect(s.reconcileBoard() == false)
        #expect(s.board == .user("me", 3))

        // Another account in no-org mode: someone else's board is cleared.
        s.account = "other"
        #expect(s.board == nil)
        #expect(s.reconcileBoard() == true)
        #expect(s.projectNumber == nil)
        #expect(s.projectOwner == .user("other"))

        // Back to an org: a personal board is never kept there.
        s.board = .user("other", 1)
        s.org = "initech"
        #expect(s.board == nil)
        #expect(s.reconcileBoard() == true)
        #expect(s.projectNumber == nil)
        #expect(s.projectOwner == .org("initech"))
    }

    /// The same login from `gh` and from the app shares its no-org board; logins match without case.
    @Test func personalBoardMatchesTheLoginWithoutCase() {
        var s = AppSettings()
        s.account = "RustyCamper"
        s.board = .user("rustycamper", 3)
        #expect(s.reconcileBoard() == false)
        #expect(s.board == .user("rustycamper", 3))
        s.accountSource = .gitHubApp
        #expect(s.reconcileBoard() == false)
        #expect(s.board?.number == 3)
    }

    @Test func noAccountLeavesTheBoardAlone() {
        var s = AppSettings()
        #expect(s.reconcileBoard() == false)
        #expect(s.projectNumber == 3)
        #expect(s.projectOwner == nil)
    }

    /// An account with no org remembers none, and leaves the other accounts' orgs alone.
    @Test func noOrgIsNotRemembered() {
        var s = AppSettings()
        s.account = "a"
        s.org = "x"
        s.rememberOrg()
        s.account = "solo"
        s.org = nil
        s.rememberOrg()
        #expect(s.orgByAccount == ["a": "x"])
        #expect(s.preferredOrg(for: "solo", among: []) == nil)
    }

    @Test func scopeFollowsAccountAndOrg() {
        var s = AppSettings()
        #expect(s.scope == nil)
        s.account = "solo"
        #expect(s.scope == .personal(login: "solo"))
        s.org = "acme"
        #expect(s.scope == .org("acme"))
    }

    /// Team is hidden without an org: a saved Team tab shows Review; with an org it stays.
    @Test func teamTabWithoutAnOrgFallsBackToReview() {
        var s = AppSettings()
        s.account = "a"
        s.org = "acme"
        s.lastTab = .team
        s.reconcileTab()
        #expect(s.lastTab == .team)
        s.org = nil
        s.reconcileTab()
        #expect(s.lastTab == .review)
        s.lastTab = .mine
        s.reconcileTab()
        #expect(s.lastTab == .mine)
    }

    @Test func preferredOrgRestoresRememberedChoice() {
        var s = AppSettings()
        s.account = "a"
        s.org = "x"
        s.rememberOrg()
        #expect(s.orgByAccount == ["a": "x"])

        s.account = "b"
        s.org = nil
        #expect(s.preferredOrg(for: "a", among: ["w", "x"]) == "x")
        #expect(s.preferredOrg(for: "a", among: ["w"]) == "w")
        #expect(s.preferredOrg(for: "a", among: []) == nil)
        // The remembered org wins over the current one; the current org is the fallback.
        s.org = "w"
        #expect(s.preferredOrg(for: "a", among: ["w", "x"]) == "x")
        #expect(s.preferredOrg(for: "a", among: ["v", "w"]) == "w")
        #expect(s.preferredOrg(for: "c", among: ["v", "w"]) == "w")
    }

    @Test func accountsSharingAnOrgKeepTheirOwnRememberedOrg() {
        var s = AppSettings()
        s.account = "frank"
        s.accountSource = .gh
        s.org = "initech"
        s.rememberOrg()
        s.orgByAccount["devon"] = "rustycamper"
        // gh frank (on initech) → app devon: both orgs are in its list, its own choice wins.
        let toApp = s.preferredOrg(for: "devon", among: ["initech", "rustycamper"])
        #expect(toApp == "rustycamper")
        s.account = "devon"
        s.accountSource = .gitHubApp
        s.org = toApp
        s.rememberOrg()
        // And back: frank returns to initech, not the app account's org.
        #expect(s.preferredOrg(for: "frank", among: ["initech", "rustycamper"]) == "initech")
        #expect(s.orgByAccount == ["frank": "initech", "devon": "rustycamper"])
    }

    @Test func preLoginPayloadDecodesAsGh() throws {
        let json = Data(#"{"account":"octocat","org":"acme","projectNumber":3}"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(s.accountSource == nil)
        #expect(s.accountRef == AccountRef(login: "octocat", source: .gh))
        #expect(s.appAccounts == [])
    }

    @Test func loginFieldsRoundTrip() throws {
        var s = AppSettings()
        s.account = "octocat"
        s.accountSource = .gitHubApp
        s.appAccounts = [AccountSummary(userID: 1, login: "octocat"), AccountSummary(userID: 2, login: "hubot")]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.accountRef == AccountRef(login: "octocat", source: .gitHubApp))
    }

    @Test func noAccountMeansNoRef() {
        #expect(AppSettings().accountRef == nil)
    }

    @Test func upsertSameUserIDReplacesSummary() {
        var s = AppSettings()
        s.upsert(AccountSummary(userID: 1, login: "octocat"))
        s.upsert(AccountSummary(userID: 1, login: "octocat-renamed"))
        #expect(s.appAccounts == [AccountSummary(userID: 1, login: "octocat-renamed")])
    }

    @Test func forgetRemovesSummaryAndOrg() {
        var s = AppSettings()
        s.upsert(AccountSummary(userID: 1, login: "octocat"))
        s.account = "octocat"
        s.accountSource = .gitHubApp
        s.org = "acme"
        s.orgByAccount["octocat"] = "acme"
        s.forget(AccountRef(login: "octocat", source: .gitHubApp))
        #expect(s.appAccounts.isEmpty)
        #expect(s.orgByAccount["octocat"] == nil)
        #expect(s.account == nil)
        #expect(s.org == nil)
        #expect(s.accountSource == nil)
    }

    @Test func forgetKeepingRememberedOrgForASharedGhLogin() {
        var s = AppSettings()
        s.upsert(AccountSummary(userID: 1, login: "octocat"))
        s.account = "octocat"
        s.accountSource = .gitHubApp
        s.org = "acme"
        s.orgByAccount["octocat"] = "acme"
        s.forget(AccountRef(login: "octocat", source: .gitHubApp), keepingRememberedOrg: true)
        #expect(s.appAccounts.isEmpty)
        #expect(s.orgByAccount["octocat"] == "acme")
        #expect(s.account == nil)
    }

    @Test func summaryWithoutAvatarDecodes() throws {
        let json = Data(#"{"userID":1,"login":"octocat"}"#.utf8)
        let summary = try JSONDecoder().decode(AccountSummary.self, from: json)
        #expect(summary == AccountSummary(userID: 1, login: "octocat"))
        #expect(summary.avatarURL == nil)
        let withAvatar = AccountSummary(userID: 1, login: "octocat", avatarURL: URL(string: "https://a/1"))
        #expect(try JSONDecoder().decode(AccountSummary.self, from: JSONEncoder().encode(withAvatar)) == withAvatar)
    }

    /// Signing out of the current account, of either kind, leaves no account and no switch to another.
    @Test func signOutOfTheCurrentAccountLeavesNone() {
        for current in [AccountRef(login: "octocat", source: .gitHubApp), AccountRef(login: "octocat", source: .gh)] {
            var s = AppSettings()
            s.upsert(AccountSummary(userID: 1, login: "octocat"))
            s.upsert(AccountSummary(userID: 2, login: "hubot"))
            s.choose(current, org: "acme")
            s.signOut(current)
            #expect(s.accountRef == nil)
            #expect(s.org == nil)
            #expect(s.signedOutByUser)
            // The other app account stays signed in; a gh login keeps the app account of its name.
            #expect(s.appAccounts.map(\.login) == (current.source == .gh ? ["octocat", "hubot"] : ["hubot"]))
        }
    }

    @Test func signOutOfAnotherAccountKeepsCurrent() {
        var s = AppSettings()
        s.upsert(AccountSummary(userID: 1, login: "octocat"))
        s.upsert(AccountSummary(userID: 2, login: "hubot"))
        s.choose(AccountRef(login: "octocat", source: .gitHubApp), org: "acme")
        s.signOut(AccountRef(login: "hubot", source: .gitHubApp))
        #expect(s.accountRef == AccountRef(login: "octocat", source: .gitHubApp))
        #expect(s.org == "acme")
        #expect(!s.signedOutByUser)
        #expect(s.appAccounts == [AccountSummary(userID: 1, login: "octocat")])
    }

    /// Choosing an account, of either kind, ends a Sign Out's first-run state.
    @Test func choosingAnAccountClearsTheSignOut() {
        for account in [AccountRef(login: "hubot", source: .gitHubApp), AccountRef(login: "hubot", source: .gh)] {
            var s = AppSettings()
            s.choose(AccountRef(login: "octocat", source: .gh), org: nil)
            s.signOut(AccountRef(login: "octocat", source: .gh))
            s.choose(account, org: nil)
            #expect(s.accountRef == account)
            #expect(s.org == nil)
            #expect(!s.signedOutByUser)
        }
    }

    @Test func forgetOtherAccountKeepsCurrent() {
        var s = AppSettings()
        s.upsert(AccountSummary(userID: 1, login: "octocat"))
        s.upsert(AccountSummary(userID: 2, login: "hubot"))
        s.account = "octocat"
        s.accountSource = .gitHubApp
        s.org = "acme"
        s.orgByAccount["octocat"] = "acme"
        s.orgByAccount["hubot"] = "octo-org"
        s.forget(AccountRef(login: "hubot", source: .gitHubApp))
        #expect(s.appAccounts == [AccountSummary(userID: 1, login: "octocat")])
        #expect(s.orgByAccount == ["octocat": "acme"])
        #expect(s.account == "octocat")
        #expect(s.accountSource == .gitHubApp)
        #expect(s.org == "acme")
    }
}

@Test func askModelChoicesRoundTripAndDefaultEmpty() throws {
    #expect(AppSettings().askModelChoices.isEmpty)
    var settings = AppSettings()
    settings.askModelChoices = [AskModel(id: "claude-sonnet-6", name: "Claude Sonnet 6")]
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded.askModelChoices == settings.askModelChoices)
}
