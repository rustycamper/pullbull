import AppKit
import CryptoKit
import Foundation
import PullBullKit

/// Avatar images cached in memory and on disk under ~/Library/Caches/io.github.rustycamper.pullbull/avatars.
final class AvatarCache: @unchecked Sendable {
    static let shared = AvatarCache()

    // NSCache and FileManager are thread-safe; nothing else here is mutable.
    private let memory = NSCache<NSURL, NSImage>()
    private let directory: URL
    private let session: URLSession

    init(
        directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.rustycamper.pullbull/avatars", isDirectory: true),
        session: URLSession = .shared
    ) {
        self.directory = directory
        self.session = session
        memory.countLimit = 300
    }

    /// The image if it is already in memory, without touching disk or network, so a view can draw it on
    /// its first frame.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        let file = directory.appendingPathComponent(Self.fileName(for: url))
        if let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            CacheTrimmer.touch(file)
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        guard let (data, response) = try? await session.data(from: Self.sized(url)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data)
        else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return image
    }

    /// Drops these images from memory and disk (a signed-out account's avatars).
    func remove(_ urls: Set<URL>) {
        for url in urls {
            memory.removeObject(forKey: url as NSURL)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.fileName(for: url)))
        }
    }

    /// Trims the disk cache by `policy` (see `CacheTrimPolicy`). Images in memory stay drawable; a row
    /// whose file went refetches it. Only the cache's own files count, never an atomic write's temporary.
    @discardableResult
    func trim(policy: CacheTrimPolicy = .avatars, now: Date) -> [URL] {
        CacheTrimmer.trim(directory, policy: policy, now: now, includes: { url in
            let name = url.lastPathComponent
            return name.count == 64 && name.allSatisfy(\.isHexDigit)
        })
    }

    private static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Asks GitHub for a small rendition (rows draw avatars at 20pt).
    private static func sized(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.hasSuffix("githubusercontent.com") == true
        else { return url }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "s" }) { items.append(URLQueryItem(name: "s", value: "64")) }
        components.queryItems = items
        return components.url ?? url
    }
}
