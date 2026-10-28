import Foundation

/// One PR or issue named by a pasted github.com link (`https://github.com/o/r/pull/12`, `/issues/12`,
/// with anything after the number, a query or a fragment) or by `o/r#12`. Other hosts (GitHub
/// Enterprise included), other paths and numbers outside 1...Int32.max name nothing.
public struct ItemReference: Equatable, Sendable {
    /// `owner/name`, as written.
    public let repo: String
    public let number: Int

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace) else { return nil }
        if let parsed = Self.link(trimmed) ?? Self.shorthand(trimmed) {
            self = parsed
        } else {
            return nil
        }
    }

    private init(owner: Substring, name: Substring, number: Substring) {
        repo = "\(owner)/\(name)"
        self.number = Int(number) ?? 0
    }

    /// `https://github.com/o/r/pull/12…`; the scheme may be `http` or left out, the host may be `www.`.
    private static func link(_ text: String) -> ItemReference? {
        let lowered = text.lowercased()
        let withScheme = lowered.hasPrefix("https://") || lowered.hasPrefix("http://")
        guard withScheme || lowered.hasPrefix("github.com/") || lowered.hasPrefix("www.github.com/"),
              let components = URLComponents(string: withScheme ? text : "https://\(text)"),
              let host = components.host?.lowercased(), host == "github.com" || host == "www.github.com",
              components.port == nil, components.user == nil, components.password == nil
        else { return nil }
        let parts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard parts.count >= 4 else { return nil }
        let owner = parts[parts.startIndex], name = parts[parts.startIndex + 1]
        let kind = parts[parts.startIndex + 2], number = parts[parts.startIndex + 3]
        guard kind == "pull" || kind == "issues", isRepo(owner: owner, name: name), isNumber(number) else {
            return nil
        }
        return ItemReference(owner: owner, name: name, number: number)
    }

    /// `o/r#12`.
    private static func shorthand(_ text: String) -> ItemReference? {
        let halves = text.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let repo = halves[0].split(separator: "/", omittingEmptySubsequences: false)
        guard repo.count == 2, isRepo(owner: repo[0], name: repo[1]), isNumber(halves[1]) else { return nil }
        return ItemReference(owner: repo[0], name: repo[1], number: halves[1])
    }

    private static func isRepo(owner: Substring, name: Substring) -> Bool {
        SearchQuery.isLogin(owner) && GitHubAPI.isValidRepoName(String(name)) && name != "." && name != ".."
    }

    private static func isNumber(_ s: Substring) -> Bool {
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(s) else { return false }
        return n > 0 && n <= Int(Int32.max)
    }
}

extension FetchScope {
    /// Whether a link to `repo` (`owner/name`) is one PullBull looks up: the org's repos, or in the
    /// personal scope the ones `covers` keeps.
    public func reaches(_ repo: String) -> Bool {
        switch self {
        case .org(let org):
            let owner = repo.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
            return owner.caseInsensitiveCompare(org) == .orderedSame
        case .personal:
            return covers(repo)
        }
    }
}
