import Foundation

/// Short relative times as the design uses them: "just now", "3m", "5h", "2d".
public enum RelativeAge {
    public static func short(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(86_400 * 30): return "\(Int(seconds / 86_400))d"
        case ..<(86_400 * 365): return "\(Int(seconds / (86_400 * 30)))mo"
        default: return "\(Int(seconds / (86_400 * 365)))y"
        }
    }

    /// "just now" or "12m ago".
    public static func ago(_ date: Date, now: Date) -> String {
        let value = short(from: date, to: now)
        return value == "now" ? "just now" : "\(value) ago"
    }

    /// The same age spelled out for hover and VoiceOver: "under a minute", "1 hour", "4 days".
    public static func spoken(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        func count(_ n: Int, _ unit: String) -> String { n == 1 ? "1 \(unit)" : "\(n) \(unit)s" }
        switch seconds {
        case ..<60: return "under a minute"
        case ..<3600: return count(Int(seconds / 60), "minute")
        case ..<86_400: return count(Int(seconds / 3600), "hour")
        case ..<(86_400 * 30): return count(Int(seconds / 86_400), "day")
        case ..<(86_400 * 365): return count(Int(seconds / (86_400 * 30)), "month")
        default: return count(Int(seconds / (86_400 * 365)), "year")
        }
    }
}
