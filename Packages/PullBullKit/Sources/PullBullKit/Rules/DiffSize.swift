import Foundation

/// A `size:` search token: how many lines a pull request changes, additions plus deletions.
public enum SizeFilter: String, CaseIterable, Sendable {
    /// Up to 50 lines.
    case s
    /// Up to 300 lines.
    case m
    /// More.
    case l

    /// `size:s`, as typed in the field.
    public var token: String { QueryScanner.sizeQualifier + rawValue }

    public var summary: String {
        switch self {
        case .s: "small"
        case .m: "medium"
        case .l: "large"
        }
    }

    /// The bucket's bounds, as `of` draws them.
    public var limit: String {
        switch self {
        case .s: "up to 50 lines changed"
        case .m: "up to 300 lines changed"
        case .l: "over 300 lines changed"
        }
    }

    /// `Small · up to 50 lines changed`, for the completion row.
    public var caption: String { summary.prefix(1).uppercased() + summary.dropFirst() + " · " + limit }

    /// The bucket of a pull request, nil when either total is unknown.
    public static func of(additions: Int?, deletions: Int?) -> SizeFilter? {
        guard let additions, let deletions else { return nil }
        switch additions + deletions {
        case ...50: return .s
        case ...300: return .m
        default: return .l
        }
    }
}

public struct SizeCandidate: CompletionCandidate {
    public let size: SizeFilter

    public var id: String { size.rawValue }
    public var insertText: String { size.token }

    public init(size: SizeFilter) {
        self.size = size
    }

    /// The sizes whose letter starts with `prefix`, ignoring case, in `SizeFilter` order.
    static func candidates(prefix: String) -> [SizeCandidate] {
        let p = prefix.lowercased()
        return SizeFilter.allCases.filter { $0.rawValue.hasPrefix(p) }.map(SizeCandidate.init)
    }
}

public enum DiffSize {
    /// `+120 −30` (U+2212 for the minus), nil when either total is unknown.
    public static func text(additions: Int?, deletions: Int?) -> String? {
        guard let additions, let deletions else { return nil }
        return "+\(additions) \u{2212}\(deletions)"
    }

    /// What VoiceOver reads for `text`.
    public static func spoken(additions: Int?, deletions: Int?) -> String? {
        guard let additions, let deletions else { return nil }
        return "\(additions) lines added, \(deletions) removed"
    }
}
