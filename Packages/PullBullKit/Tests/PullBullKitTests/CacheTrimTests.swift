import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400

private func entry(_ name: String, size: Int64 = 1, daysAgo: Double) -> CacheEntry {
    CacheEntry(url: URL(fileURLWithPath: "/cache/\(name)"), size: size, date: now.addingTimeInterval(-daysAgo * day))
}

private func names(_ entries: [CacheEntry]) -> [String] { entries.map(\.url.lastPathComponent) }

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pullbull-trim-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Writes `size` bytes to `dir/name` and dates it `daysAgo` days before `now`.
@discardableResult
private func file(_ name: String, in dir: URL, size: Int = 10, daysAgo: Double) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0, count: size).write(to: url)
    try FileManager.default.setAttributes(
        [.modificationDate: now.addingTimeInterval(-daysAgo * day)], ofItemAtPath: url.path)
    return url
}

@Suite struct CacheTrimPolicyTests {
    private let policy = CacheTrimPolicy(maxAge: 30 * day, capBytes: 100)

    @Test func ownerValues() {
        #expect(CacheTrimPolicy.details == CacheTrimPolicy(maxAge: 30 * day, capBytes: 50 * 1_024 * 1_024))
        #expect(CacheTrimPolicy.avatars == CacheTrimPolicy(maxAge: 30 * day, capBytes: 20 * 1_024 * 1_024))
    }

    @Test func removesEntriesUnusedForLongerThanMaxAge() {
        let entries = [
            entry("fresh", daysAgo: 1), entry("old", daysAgo: 31), entry("edge", daysAgo: 30),
            entry("ancient", daysAgo: 400), entry("almost", daysAgo: 29.9),
        ]
        #expect(names(policy.evictions(from: entries, now: now)) == ["ancient", "old"])
    }

    @Test func futureDatesCountAsJustUsed() {
        #expect(policy.evictions(from: [entry("ahead", daysAgo: -5)], now: now).isEmpty)
    }

    @Test func overCapRemovesLeastRecentlyUsedFirst() {
        let entries = [
            entry("c", size: 40, daysAgo: 3), entry("a", size: 40, daysAgo: 10),
            entry("d", size: 40, daysAgo: 1), entry("b", size: 40, daysAgo: 5),
        ]
        // 160 bytes: dropping a (oldest) leaves 120, dropping b leaves 80.
        #expect(names(policy.evictions(from: entries, now: now)) == ["a", "b"])
    }

    @Test func ageCutoffCountsTowardTheCap() {
        let entries = [
            entry("expired", size: 500, daysAgo: 40), entry("older", size: 60, daysAgo: 5),
            entry("newer", size: 60, daysAgo: 2),
        ]
        #expect(names(policy.evictions(from: entries, now: now)) == ["expired", "older"])
    }

    @Test func exactlyAtCapKeepsEverything() {
        let entries = [entry("a", size: 50, daysAgo: 2), entry("b", size: 50, daysAgo: 1)]
        #expect(policy.evictions(from: entries, now: now).isEmpty)
        let over = entries + [entry("c", size: 1, daysAgo: 0)]
        #expect(names(policy.evictions(from: over, now: now)) == ["a"])
    }

    @Test func tiesBreakByPath() {
        let entries = [entry("b", size: 60, daysAgo: 1), entry("a", size: 60, daysAgo: 1)]
        #expect(names(policy.evictions(from: entries, now: now)) == ["a"])
    }

    @Test func emptyCacheRemovesNothing() {
        #expect(policy.evictions(from: [], now: now).isEmpty)
    }

    @Test func singleEntryOverCapIsRemoved() {
        #expect(names(policy.evictions(from: [entry("big", size: 101, daysAgo: 0)], now: now)) == ["big"])
    }
}

@Suite struct CacheTrimmerTests {
    private let policy = CacheTrimPolicy(maxAge: 30 * day, capBytes: 25)

    @Test func emptyAndMissingDirectories() {
        let dir = tempDir()
        #expect(CacheTrimmer.entries(in: dir).isEmpty)
        #expect(CacheTrimmer.trim(dir, policy: policy, now: now).isEmpty)
        let missing = dir.appendingPathComponent("nope")
        #expect(CacheTrimmer.trim(missing, policy: policy, now: now).isEmpty)
    }

    @Test func trimsByAgeThenCapIncludingSubfolders() throws {
        let dir = tempDir()
        let old = try file("a/old.json", in: dir, daysAgo: 45)
        let lru = try file("a/issues/lru.json", in: dir, daysAgo: 10)
        let mid = try file("b/mid.json", in: dir, daysAgo: 5)
        let new = try file("b/new.json", in: dir, daysAgo: 1)
        let removed = CacheTrimmer.trim(dir, policy: policy, now: now)
        #expect(Set(removed.map(\.lastPathComponent)) == ["old.json", "lru.json"])
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: lru.path))
        #expect(fm.fileExists(atPath: mid.path) && fm.fileExists(atPath: new.path))
    }

    @Test func skipsHiddenAndExcludedFiles() throws {
        let dir = tempDir()
        let hidden = try file(".tmp-write", in: dir, daysAgo: 90)
        let other = try file("notes.txt", in: dir, daysAgo: 90)
        try file("old.json", in: dir, daysAgo: 90)
        let removed = CacheTrimmer.trim(dir, policy: policy, now: now, includes: { $0.pathExtension == "json" })
        #expect(removed.map(\.lastPathComponent) == ["old.json"])
        #expect(FileManager.default.fileExists(atPath: hidden.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func filesThatDisappearMidTrimAreSkipped() throws {
        let dir = tempDir()
        let first = try file("1.json", in: dir, daysAgo: 60)
        let second = try file("2.json", in: dir, daysAgo: 50)
        let third = try file("3.json", in: dir, daysAgo: 40)
        var calls: [String] = []
        // Something else (a sign-out) deletes the others while the first removal runs.
        let removed = CacheTrimmer.trim(dir, policy: policy, now: now, remove: { url in
            calls.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
            if url.lastPathComponent == first.lastPathComponent {
                try FileManager.default.removeItem(at: second)
                try FileManager.default.removeItem(at: third)
            }
        })
        #expect(removed.map(\.lastPathComponent) == ["1.json"])
        #expect(calls == ["1.json"])
    }

    @Test func aRemovalThatFailsIsNotReported() throws {
        let dir = tempDir()
        try file("1.json", in: dir, daysAgo: 60)
        try file("2.json", in: dir, daysAgo: 50)
        struct Gone: Error {}
        let removed = CacheTrimmer.trim(dir, policy: policy, now: now, remove: { url in
            if url.lastPathComponent == "1.json" { throw Gone() }
            try FileManager.default.removeItem(at: url)
        })
        #expect(removed.map(\.lastPathComponent) == ["2.json"])
    }

    @Test func aFileUsedMidTrimIsKept() throws {
        let dir = tempDir()
        let first = try file("1.json", in: dir, daysAgo: 60)
        let second = try file("2.json", in: dir, daysAgo: 50)
        // A read or a fresh write lands on the second file while the first is being removed.
        let removed = CacheTrimmer.trim(dir, policy: policy, now: now, remove: { url in
            try FileManager.default.removeItem(at: url)
            if url.lastPathComponent == first.lastPathComponent { CacheTrimmer.touch(second, now: now) }
        })
        #expect(removed.map(\.lastPathComponent) == ["1.json"])
        #expect(FileManager.default.fileExists(atPath: second.path))
    }
}

/// Details are saved and touched at the real time, so these tests trim against it too.
@Suite struct SnapshotStoreTrimTests {
    private func sampleDetail(_ number: Int) -> PRDetail {
        PRDetail(key: PRKey(repo: "o/r", number: number), body: "b", checks: [], reviews: [], comments: [], files: [])
    }

    private func age(_ url: URL, days: Double, from clock: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: clock.addingTimeInterval(-days * day)], ofItemAtPath: url.path)
    }

    @Test func loadingADetailMarksItUsed() async throws {
        let clock = Date()
        let dir = tempDir().appendingPathComponent("cache")
        let store = SnapshotStore(directory: dir)
        try await store.saveDetail(sampleDetail(1), account: "me")
        let url = dir.appendingPathComponent("details/me/o_r_1.json")
        try age(url, days: 60, from: clock)
        #expect(await store.loadDetail(PRKey(repo: "o/r", number: 1), account: "me") != nil)
        #expect(await store.trimDetails(now: clock).isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func trimsOldDetailsButNotSnapshots() async throws {
        let clock = Date()
        let dir = tempDir().appendingPathComponent("cache")
        let store = SnapshotStore(directory: dir)
        try await store.saveDetail(sampleDetail(1), account: "me")
        try await store.saveDetail(sampleDetail(2), account: "me")
        let snapshot = dir.appendingPathComponent("me@o.json")
        try Data("{}".utf8).write(to: snapshot)
        try age(snapshot, days: 90, from: clock)
        try age(dir.appendingPathComponent("details/me/o_r_1.json"), days: 31, from: clock)
        let removed = await store.trimDetails(now: clock)
        #expect(removed.map(\.lastPathComponent) == ["o_r_1.json"])
        #expect(FileManager.default.fileExists(atPath: snapshot.path))
        #expect(await store.loadDetail(PRKey(repo: "o/r", number: 2), account: "me") != nil)
    }
}
