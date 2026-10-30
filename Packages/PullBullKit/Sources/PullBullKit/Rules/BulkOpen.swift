import Foundation

/// "Open All N on GitHub" on a group header: offered from two items, confirmed above eight.
public enum BulkOpen {
    /// More pages than this ask first.
    public static let confirmAbove = 8

    public static func offers(count: Int) -> Bool { count >= 2 }

    public static func needsConfirmation(count: Int) -> Bool { count > confirmAbove }

    public static func menuTitle(count: Int) -> String { "Open All \(count) on GitHub" }

    /// The confirmation's question.
    public static func prompt(count: Int) -> String { "Open \(count) pages in your browser?" }

    /// The pages to open, in the group's display order, each once.
    public static func urls(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
