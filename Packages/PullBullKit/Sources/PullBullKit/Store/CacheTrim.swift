import Foundation

/// One file of a disk cache. `date` is its modification date, which reads and writes both bump, so it is
/// when the entry was last used.
public struct CacheEntry: Equatable, Sendable {
    public let url: URL
    public let size: Int64
    public let date: Date

    public init(url: URL, size: Int64, date: Date) {
        self.url = url
        self.size = size
        self.date = date
    }
}

/// How a disk cache is trimmed: entries unused for longer than `maxAge` go first, then the least recently
/// used until the rest fit in `capBytes`.
public struct CacheTrimPolicy: Equatable, Sendable {
    public let maxAge: TimeInterval
    public let capBytes: Int64

    public init(maxAge: TimeInterval, capBytes: Int64) {
        self.maxAge = maxAge
        self.capBytes = capBytes
    }

    public static let details = CacheTrimPolicy(maxAge: 30 * 86_400, capBytes: 50 * 1_024 * 1_024)
    public static let avatars = CacheTrimPolicy(maxAge: 30 * 86_400, capBytes: 20 * 1_024 * 1_024)

    /// The entries to remove, oldest first. An entry used exactly `maxAge` ago stays, and so does a cache
    /// exactly at the cap. Dates after `now` (a clock moved back) count as just used.
    public func evictions(from entries: [CacheEntry], now: Date) -> [CacheEntry] {
        let cutoff = now.addingTimeInterval(-maxAge)
        // Least recently used first; the path breaks ties so the order never depends on listing order.
        let ordered = entries.sorted { ($0.date, $0.url.path) < ($1.date, $1.url.path) }
        var removed: [CacheEntry] = []
        var kept: [CacheEntry] = []
        for entry in ordered {
            if entry.date < cutoff { removed.append(entry) } else { kept.append(entry) }
        }
        var total = kept.reduce(Int64(0)) { $0 + $1.size }
        for entry in kept where total > capBytes {
            removed.append(entry)
            total -= entry.size
        }
        return removed
    }
}

/// The filesystem side of `CacheTrimPolicy`: lists a cache folder and removes what the policy picks.
public enum CacheTrimmer {
    /// The regular files under `directory` (subfolders included, hidden files such as an atomic write's
    /// temporary file skipped) that `includes` accepts.
    public static func entries(in directory: URL, includes: (URL) -> Bool = { _ in true }) -> [CacheEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return [] }
        var entries: [CacheEntry] = []
        for case let url as URL in walker where includes(url) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let date = values.contentModificationDate
            else { continue }
            entries.append(CacheEntry(url: url, size: Int64(values.fileSize ?? 0), date: date))
        }
        return entries
    }

    /// Trims `directory` by `policy` and returns the files it removed. A file that is gone by the time
    /// its turn comes is skipped, and so is one used or rewritten since the listing: its date moved on.
    @discardableResult
    public static func trim(
        _ directory: URL, policy: CacheTrimPolicy, now: Date, includes: (URL) -> Bool = { _ in true },
        remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> [URL] {
        var removed: [URL] = []
        for entry in policy.evictions(from: entries(in: directory, includes: includes), now: now) {
            // A fresh URL: the listed one caches the values read when it was listed.
            let url = URL(fileURLWithPath: entry.url.path)
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, date == entry.date
            else { continue }
            if (try? remove(url)) != nil { removed.append(url) }
        }
        return removed
    }

    /// Marks a cache file as just used, so trimming keeps it longer. Fails quietly if the file is gone.
    public static func touch(_ url: URL, now: Date = Date()) {
        try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
    }
}
