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
