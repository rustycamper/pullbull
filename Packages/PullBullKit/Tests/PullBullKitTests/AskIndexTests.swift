import Foundation
import SQLite3
import Testing
@testable import PullBullKit

struct AskIndexTests {
    static func tempURL(_ name: String = "t.ask.sqlite") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ask-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
    }

    static func item(
        _ repo: String, _ number: Int, title: String = "t", body: String = "b", author: String? = "ann",
        updated: TimeInterval = 1_000_000, labels: [String] = []
    ) -> AskItem {
        AskItem(
            key: PRKey(repo: repo, number: number), kind: .issue, state: "open", author: author,
            created: Date(timeIntervalSince1970: 1000), updated: Date(timeIntervalSince1970: updated),
            labels: labels, title: title, body: body)
    }

    static func setUserVersion(_ url: URL, _ version: Int) -> Bool {
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        return sqlite3_open(url.path, &handle) == SQLITE_OK
            && sqlite3_exec(handle, "PRAGMA user_version = \(version)", nil, nil, nil) == SQLITE_OK
    }

    @Test func upsertReplacesByKey() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([Self.item("o/a", 1, title: "alpha pager")])
        try await index.upsert([Self.item("o/a", 1, title: "beta cursor")])
        #expect(try await index.count() == 1)
        #expect(try await index.search("cursor", limit: 5, excluding: [], repo: nil).map(\.title) == ["beta cursor"])
        #expect(try await index.search("pager", limit: 5, excluding: [], repo: nil).isEmpty)
    }

    @Test func searchRanksTitleOverBody() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([
            Self.item("o/a", 1, title: "unrelated", body: "mentions the kraken once"),
            Self.item("o/a", 2, title: "kraken sighting", body: "unrelated"),
        ])
        #expect(try await index.search("kraken", limit: 5, excluding: [], repo: nil).map(\.key.number) == [2, 1])
    }

    @Test func accentedTitleIsFoundByAccentedQuery() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([Self.item("o/a", 1, title: "Café crème menu"), Self.item("o/a", 2, title: "other")])
        let hits = try await index.search("café", limit: 5, excluding: [], repo: nil)
        #expect(hits.map(\.key.number) == [1])
    }

    @Test func searchFiltersRepoAndExcluding() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([
            Self.item("o/a", 1, title: "login"), Self.item("o/a", 2, title: "login"), Self.item("o/b", 3, title: "login"),
        ])
        let inA = try await index.search("login", limit: 10, excluding: [], repo: "O/A")
        #expect(Set(inA.map(\.key.number)) == [1, 2])
        let rest = try await index.search("login", limit: 2, excluding: [PRKey(repo: "o/a", number: 1)], repo: nil)
        #expect(rest.count == 2)
        #expect(!rest.contains { $0.key == PRKey(repo: "o/a", number: 1) })
    }

    @Test func roundTripsEveryField() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        let merged = AskItem(
            key: PRKey(repo: "Acme/Web", number: 7), kind: .pr, state: "merged", author: nil,
            created: Date(timeIntervalSince1970: 100), updated: Date(timeIntervalSince1970: 200),
            labels: ["bug", "a,b"], title: "Fix \"quotes\"", body: "line\nbreak", mergedAt: Date(timeIntervalSince1970: 300),
            baseRef: "main")
        try await index.upsert([merged])
        #expect(try await index.search("quotes", limit: 3, excluding: [], repo: "acme/web") == [merged])
    }

    @Test func pruneDropsOlderThanWindow() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([
            Self.item("o/a", 1, title: "old thing", updated: 100), Self.item("o/a", 2, title: "new thing", updated: 900),
        ])
        try await index.prune(updatedBefore: Date(timeIntervalSince1970: 500))
        #expect(try await index.count() == 1)
        #expect(try await index.keys(updatedSince: Date(timeIntervalSince1970: 0)) == [PRKey(repo: "o/a", number: 2)])
        #expect(try await index.search("old", limit: 5, excluding: [], repo: nil).isEmpty)
    }

    @Test func deleteKeysAndRepos() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([Self.item("o/a", 1), Self.item("o/a", 2), Self.item("o/b", 3), Self.item("o/c", 4)])
        try await index.delete(keys: [PRKey(repo: "o/a", number: 1)])
        #expect(try await index.count() == 3)
        try await index.deleteRepos { $0 == "o/b" }
        #expect(try await index.keys(updatedSince: .distantPast) == [PRKey(repo: "o/a", number: 2), PRKey(repo: "o/c", number: 4)])
    }

    @Test func deleteReposIsCaseInsensitive() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([Self.item("o/a", 1), Self.item("o/b", 2)])
        try await index.delete(repos: ["O/A"])
        #expect(try await index.keys(updatedSince: .distantPast) == [PRKey(repo: "o/b", number: 2)])
    }

    @Test func searchWithNilMatchReturnsEmpty() async throws {
        let index = try AskIndex(fileURL: Self.tempURL())
        try await index.upsert([Self.item("o/a", 1, title: "what that")])
        #expect(try await index.search("what's that one?", limit: 5, excluding: [], repo: nil).isEmpty)
    }

    @Test func fileIsCreatedWithMetaRoundTrip() async throws {
        let url = Self.tempURL()
        do {
            let index = try AskIndex(fileURL: url)
            #expect(try await index.meta(.lastSync) == nil)
            try await index.setMeta(.lastSync, Date(timeIntervalSince1970: 1234))
            try await index.setMeta(.backfilledUntil, Date(timeIntervalSince1970: 99))
            try await index.setMeta(.backfilledUntil, nil)
            try await index.upsert([Self.item("o/a", 1)])
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let reopened = try AskIndex(fileURL: url)
        #expect(try await reopened.meta(.lastSync) == Date(timeIntervalSince1970: 1234))
        #expect(try await reopened.meta(.backfilledUntil) == nil)
        #expect(try await reopened.count() == 1)
    }

    @Test func versionMismatchRecreatesTheIndex() async throws {
        let url = Self.tempURL()
        do {
            let index = try AskIndex(fileURL: url)
            try await index.upsert([Self.item("o/a", 1)])
        }
        #expect(Self.setUserVersion(url, 99))
        let reopened = try AskIndex(fileURL: url)
        #expect(try await reopened.count() == 0)
        try await reopened.upsert([Self.item("o/a", 2, title: "again")])
        #expect(try await reopened.search("again", limit: 1, excluding: [], repo: nil).count == 1)
    }

    @Test func removeAllDeletesAskIndex() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SnapshotStore(directory: dir)
        let url = store.askIndexURL(account: "ann", scope: .org("acme"))
        #expect(url.lastPathComponent == "ann@acme.ask.sqlite")
        let other = store.askIndexURL(account: "bob", scope: .org("acme"))
        for u in [url, other] {
            for suffix in ["", "-wal", "-shm"] {
                try Data("x".utf8).write(to: URL(fileURLWithPath: u.path + suffix))
            }
        }
        try await store.removeAll(account: "ann")
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(left == ["bob@acme.ask.sqlite", "bob@acme.ask.sqlite-shm", "bob@acme.ask.sqlite-wal"])
    }
}
