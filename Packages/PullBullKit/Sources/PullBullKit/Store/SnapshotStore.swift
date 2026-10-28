import Foundation

public actor SnapshotStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.encoder = encoder
        self.decoder = decoder
    }

    public func load(account: String, scope: FetchScope) -> Snapshot? {
        read(Snapshot.self, from: snapshotURL(account: account, scope: scope))
    }

    public func save(_ snapshot: Snapshot, account: String, scope: FetchScope) throws {
        try write(snapshot, to: snapshotURL(account: account, scope: scope))
    }

    public func loadDetail(_ key: PRKey, account: String) -> PRDetail? {
        readTouching(PRDetail.self, from: detailURL(key, account: account))
    }

    public func saveDetail(_ detail: PRDetail, account: String) throws {
        try write(detail, to: detailURL(detail.key, account: account))
    }

    public func loadIssueDetail(_ key: PRKey, account: String) -> IssueDetail? {
        readTouching(IssueDetail.self, from: issueDetailURL(key, account: account))
    }

    /// Trims the PR and issue detail caches of every account by `policy` (see `CacheTrimPolicy`).
    /// Snapshots, one per account and scope, are left alone. On the actor, so no save is ever half done.
    @discardableResult
    public func trimDetails(policy: CacheTrimPolicy = .details, now: Date) -> [URL] {
        CacheTrimmer.trim(
            directory.appendingPathComponent("details", isDirectory: true), policy: policy, now: now,
            includes: { $0.pathExtension == "json" })
    }

    public func saveIssueDetail(_ detail: IssueDetail, account: String) throws {
        try write(detail, to: issueDetailURL(detail.key, account: account))
    }

    /// Deletes every snapshot, Ask index and detail cache of `account`. The `@` that follows its name in a snapshot
    /// file can't occur in a sanitized login, so the prefix matches that account only.
    public func removeAll(account: String) throws {
        let fm = FileManager.default
        let prefix = Self.sanitize(account) + "@"
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        let askSuffixes = [".ask.sqlite", ".ask.sqlite-wal", ".ask.sqlite-shm"]
        for name in names where name.hasPrefix(prefix)
            && (name.hasSuffix(".json") || askSuffixes.contains(where: name.hasSuffix)) {
            try fm.removeItem(at: directory.appendingPathComponent(name))
        }
        let details = directory
            .appendingPathComponent("details", isDirectory: true)
            .appendingPathComponent(Self.sanitize(account), isDirectory: true)
        if fm.fileExists(atPath: details.path) { try fm.removeItem(at: details) }
    }

    /// The avatar URLs `account`'s cached snapshots and details refer to (see `CachedAvatars`), so its
    /// avatar entries can go with its caches.
    public func avatarURLs(account: String) -> Set<URL> {
        let fm = FileManager.default
        let prefix = Self.sanitize(account) + "@"
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        let snapshots = names.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .compactMap { read(Snapshot.self, from: directory.appendingPathComponent($0)) }
        let details = directory
            .appendingPathComponent("details", isDirectory: true)
            .appendingPathComponent(Self.sanitize(account), isDirectory: true)
        let issues = details.appendingPathComponent("issues", isDirectory: true)
        return CachedAvatars.urls(
            snapshots: snapshots,
            details: jsonFiles(in: details).compactMap { read(PRDetail.self, from: $0) },
            issueDetails: jsonFiles(in: issues).compactMap { read(IssueDetail.self, from: $0) })
    }

    private func jsonFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { folder.appendingPathComponent($0) }
    }

    /// `<login>@<org>.json`, or `<login>@-personal.json` for the personal scope.
    private func snapshotURL(account: String, scope: FetchScope) -> URL {
        directory.appendingPathComponent("\(Self.sanitize(account))@\(Self.sanitize(scope.cacheKey)).json")
    }

    /// `<login>@<org>.ask.sqlite`, the Ask index beside the snapshot of the same scope.
    public nonisolated func askIndexURL(account: String, scope: FetchScope) -> URL {
        directory.appendingPathComponent("\(Self.sanitize(account))@\(Self.sanitize(scope.cacheKey)).ask.sqlite")
    }

    private func detailURL(_ key: PRKey, account: String) -> URL {
        directory
            .appendingPathComponent("details", isDirectory: true)
            .appendingPathComponent(Self.sanitize(account), isDirectory: true)
            .appendingPathComponent("\(Self.sanitize(key.repo))_\(key.number).json")
    }

    /// `details/<account>/issues/`, beside the PR details: a folder of their own keeps an issue and a PR
    /// detail from ever reading each other's file.
    private func issueDetailURL(_ key: PRKey, account: String) -> URL {
        directory
            .appendingPathComponent("details", isDirectory: true)
            .appendingPathComponent(Self.sanitize(account), isDirectory: true)
            .appendingPathComponent("issues", isDirectory: true)
            .appendingPathComponent("\(Self.sanitize(key.repo))_\(key.number).json")
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    /// A detail read also marks its file as just used, for `trimDetails`.
    private func readTouching<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let value = read(type, from: url) else { return nil }
        CacheTrimmer.touch(url)
        return value
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    static func sanitize(_ name: String) -> String {
        let cleaned = String(name.unicodeScalars.map { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", ".", "_", "-": Character(scalar)
            default: "_"
            }
        })
        return cleaned.allSatisfy { $0 == "." } ? String(repeating: "_", count: max(cleaned.count, 1)) : cleaned
    }
}
