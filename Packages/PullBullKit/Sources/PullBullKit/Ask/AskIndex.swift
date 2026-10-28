import Foundation
import SQLite3

/// A local SQLite FTS5 index of PRs and issues, one file per account and scope. Every statement is
/// prepared with bound parameters.
public actor AskIndex {
    public enum MetaKey: String, Sendable { case lastSync, lastFullSync, backfilledUntil }

    public struct IndexError: Error, Equatable, Sendable {
        public let message: String
    }

    private static let schemaVersion: Int32 = 1
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private nonisolated(unsafe) let db: OpaquePointer

    public init(fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existed = FileManager.default.fileExists(atPath: fileURL.path)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(fileURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw IndexError(message: message)
        }
        do {
            try Self.exec(handle, "PRAGMA journal_mode=WAL")
            try Self.prepareSchema(handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
        if !existed {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path)
        }
        db = handle
    }

    deinit { sqlite3_close(db) }

    // MARK: Writes

    /// Inserts `items`, replacing any row with the same key.
    public func upsert(_ items: [AskItem]) throws {
        try inTransaction {
            let sql = """
                INSERT INTO items(key, repo, number, kind, state, author, created, updated, labels, title, body, merged, base)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
                ON CONFLICT(key) DO UPDATE SET repo=?2, number=?3, kind=?4, state=?5, author=?6, created=?7,
                    updated=?8, labels=?9, title=?10, body=?11, merged=?12, base=?13
                """
            for item in items {
                try run(sql) { stmt in
                    bind(stmt, 1, item.key.askKey)
                    bind(stmt, 2, item.key.repo.lowercased())
                    sqlite3_bind_int64(stmt, 3, Int64(item.key.number))
                    bind(stmt, 4, item.kind.rawValue)
                    bind(stmt, 5, item.state)
                    bind(stmt, 6, item.author)
                    sqlite3_bind_double(stmt, 7, item.created.timeIntervalSince1970)
                    sqlite3_bind_double(stmt, 8, item.updated.timeIntervalSince1970)
                    bind(stmt, 9, Self.encodeLabels(item.labels))
                    bind(stmt, 10, item.title)
                    bind(stmt, 11, item.body)
                    bind(stmt, 12, item.mergedAt?.timeIntervalSince1970)
                    bind(stmt, 13, item.baseRef)
                }
            }
        }
    }

    public func delete(keys: Set<PRKey>) throws {
        try inTransaction {
            for key in keys {
                try run("DELETE FROM items WHERE key = ?1") { bind($0, 1, key.askKey) }
            }
        }
    }

    /// Deletes every row of the given repos, matched case-insensitively.
    public func delete(repos: Set<String>) throws {
        try inTransaction {
            for repo in repos {
                try run("DELETE FROM items WHERE repo = ?1") { bind($0, 1, repo.lowercased()) }
            }
        }
    }

    /// Deletes every row whose repo `drop` accepts. `drop` gets the repo lowercased.
    public func deleteRepos(where drop: @Sendable (String) -> Bool) throws {
        var repos: [String] = []
        try query("SELECT DISTINCT repo FROM items", bindings: { _ in }) { repos.append(text($0, 0) ?? "") }
        try delete(repos: Set(repos.filter(drop)))
    }

    /// Deletes every row last updated before `date`.
    public func prune(updatedBefore date: Date) throws {
        try run("DELETE FROM items WHERE updated < ?1") {
            sqlite3_bind_double($0, 1, date.timeIntervalSince1970)
        }
    }

    public func setMeta(_ key: MetaKey, _ value: Date?) throws {
        if let value {
            try run("INSERT INTO meta(k, v) VALUES (?1, ?2) ON CONFLICT(k) DO UPDATE SET v=?2") {
                bind($0, 1, key.rawValue)
                sqlite3_bind_double($0, 2, value.timeIntervalSince1970)
            }
        } else {
            try run("DELETE FROM meta WHERE k = ?1") { bind($0, 1, key.rawValue) }
        }
    }

    // MARK: Reads

    /// The best matches for `question`, best first, without the `excluding` keys. Title hits outrank
    /// author hits, which outrank body hits. `repo` limits the search to one repo (case-insensitive).
    public func search(_ question: String, limit: Int, excluding: Set<PRKey>, repo: String?) throws -> [AskItem] {
        guard let match = AskQuery.match(question), limit > 0 else { return [] }
        let skip = Set(excluding.map(\.askKey))
        var sql = """
            SELECT items.key, items.kind, items.state, items.author, items.created, items.updated,
                   items.labels, items.title, items.body, items.merged, items.base
            FROM items_fts JOIN items ON items.rowid = items_fts.rowid
            WHERE items_fts MATCH ?1
            """
        if repo != nil { sql += " AND items.repo = ?3" }
        sql += " ORDER BY bm25(items_fts, 5.0, 3.0, 1.0) LIMIT ?2"
        var found: [AskItem] = []
        try query(sql, bindings: { stmt in
            bind(stmt, 1, match)
            sqlite3_bind_int64(stmt, 2, Int64(limit + excluding.count))
            if let repo { bind(stmt, 3, repo.lowercased()) }
        }) { stmt in
            guard let key = text(stmt, 0).flatMap({ PRKey(askKey: $0) }), !skip.contains(key.askKey) else { return }
            found.append(AskItem(
                key: key, kind: AskItem.Kind(rawValue: text(stmt, 1) ?? "") ?? .pr, state: text(stmt, 2) ?? "",
                author: text(stmt, 3), created: date(stmt, 4) ?? .distantPast, updated: date(stmt, 5) ?? .distantPast,
                labels: Self.decodeLabels(text(stmt, 6)), title: text(stmt, 7) ?? "", body: text(stmt, 8) ?? "",
                mergedAt: date(stmt, 9), baseRef: text(stmt, 10)))
        }
        return Array(found.prefix(limit))
    }

    /// Keys of the rows updated at or after `date`.
    public func keys(updatedSince date: Date) throws -> Set<PRKey> {
        var keys: Set<PRKey> = []
        try query("SELECT key FROM items WHERE updated >= ?1", bindings: {
            sqlite3_bind_double($0, 1, date.timeIntervalSince1970)
        }) { stmt in
            if let key = text(stmt, 0).flatMap({ PRKey(askKey: $0) }) { keys.insert(key) }
        }
        return keys
    }

    public func count() throws -> Int {
        var total = 0
        try query("SELECT COUNT(*) FROM items", bindings: { _ in }) { total = Int(sqlite3_column_int64($0, 0)) }
        return total
    }

    public func meta(_ key: MetaKey) throws -> Date? {
        var value: Date?
        try query("SELECT v FROM meta WHERE k = ?1", bindings: { bind($0, 1, key.rawValue) }) {
            value = date($0, 0)
        }
        return value
    }

    // MARK: SQLite plumbing

    private func inTransaction(_ body: () throws -> Void) throws {
        try Self.exec(db, "BEGIN IMMEDIATE")
        do {
            try body()
            try Self.exec(db, "COMMIT")
        } catch {
            try? Self.exec(db, "ROLLBACK")
            throw error
        }
    }

    private func run(_ sql: String, bindings: (OpaquePointer) -> Void) throws {
        try query(sql, bindings: bindings) { _ in }
    }

    private func query(
        _ sql: String, bindings: (OpaquePointer) -> Void, row: (OpaquePointer) -> Void
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw IndexError(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindings(stmt)
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: row(stmt)
            case SQLITE_DONE: return
            default: throw IndexError(message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func text(_ stmt: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }

    private func date(_ stmt: OpaquePointer, _ column: Int32) -> Date? {
        sqlite3_column_type(stmt, column) == SQLITE_NULL
            ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, column))
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "sqlite error"
            sqlite3_free(error)
            throw IndexError(message: message)
        }
    }

    private static func userVersion(_ db: OpaquePointer) -> Int32 {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) : 0
    }

    /// Creates the tables, or drops and recreates them when the file has another schema version.
    private static func prepareSchema(_ db: OpaquePointer) throws {
        let version = userVersion(db)
        if version == schemaVersion { return }
        if version != 0 {
            try exec(db, """
                DROP TRIGGER IF EXISTS items_ai; DROP TRIGGER IF EXISTS items_ad; DROP TRIGGER IF EXISTS items_au;
                DROP TABLE IF EXISTS items_fts; DROP TABLE IF EXISTS items; DROP TABLE IF EXISTS meta;
                """)
        }
        try exec(db, """
            CREATE TABLE IF NOT EXISTS items(
                key TEXT PRIMARY KEY, repo TEXT, number INT, kind TEXT, state TEXT, author TEXT,
                created REAL, updated REAL, labels TEXT, title TEXT, body TEXT, merged REAL, base TEXT);
            CREATE INDEX IF NOT EXISTS items_repo ON items(repo);
            CREATE INDEX IF NOT EXISTS items_updated ON items(updated);
            CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                title, author, body, content='items', content_rowid='rowid', tokenize='porter unicode61');
            CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                INSERT INTO items_fts(rowid, title, author, body) VALUES (new.rowid, new.title, new.author, new.body);
            END;
            CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                INSERT INTO items_fts(items_fts, rowid, title, author, body)
                VALUES ('delete', old.rowid, old.title, old.author, old.body);
            END;
            CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
                INSERT INTO items_fts(items_fts, rowid, title, author, body)
                VALUES ('delete', old.rowid, old.title, old.author, old.body);
                INSERT INTO items_fts(rowid, title, author, body) VALUES (new.rowid, new.title, new.author, new.body);
            END;
            CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v REAL);
            PRAGMA user_version = \(schemaVersion);
            """)
    }

    private static func encodeLabels(_ labels: [String]) -> String {
        (try? JSONEncoder().encode(labels)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private static func decodeLabels(_ text: String?) -> [String] {
        text.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }
}
