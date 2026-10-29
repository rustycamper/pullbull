import Foundation

/// A PR or issue as the Ask index stores it: the text the question is matched against plus the fields
/// the answer card shows.
public struct AskItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case pr, issue }

    public let key: PRKey
    public let kind: Kind
    /// "open", "closed", "merged" or "draft".
    public let state: String
    public let author: String?
    public let created: Date
    public let updated: Date
    public let labels: [String]
    public let title: String
    public let body: String
    public let mergedAt: Date?
    public let baseRef: String?

    public init(
        key: PRKey, kind: Kind, state: String, author: String?, created: Date, updated: Date,
        labels: [String], title: String, body: String, mergedAt: Date? = nil, baseRef: String? = nil
    ) {
        self.key = key
        self.kind = kind
        self.state = state
        self.author = author
        self.created = created
        self.updated = updated
        self.labels = labels
        self.title = title
        self.body = body
        self.mergedAt = mergedAt
        self.baseRef = baseRef
    }
}

extension PRKey {
    /// `owner/repo#12`, the form Ask shows and the model cites.
    public var askKey: String { "\(repo)#\(number)" }

    /// Parses `owner/repo#12`; anything else is nil.
    public init?(askKey: String) {
        let parts = askKey.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, let number = Int(parts[1]), number >= 0 else { return nil }
        let repo = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard repo.count == 2, repo.allSatisfy({ !$0.isEmpty }) else { return nil }
        self.init(repo: String(parts[0]), number: number)
    }
}
