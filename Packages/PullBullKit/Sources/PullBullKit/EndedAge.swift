import Foundation

/// When a merged or closed item ended, as its meta line says it: relative for the first week
/// ("merged 3d ago"), then the date ("merged Oct 12", with the year once it isn't this one).
public enum EndedAge {
    /// Up to and including seven days the age is relative.
    static let relativeLimit: TimeInterval = 7 * 86_400

    /// nil for an open item or one without a close date, so the caller can fall back.
    public static func text(
        state: PRState, closedAt: Date?, now: Date,
        locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String? {
        guard state != .open, let closedAt else { return nil }
        let word = state == .merged ? "merged" : "closed"
        let seconds = max(0, now.timeIntervalSince(closedAt))
        if seconds <= relativeLimit {
            return "\(word) \(relative(seconds))"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameYear = calendar.isDate(closedAt, equalTo: now, toGranularity: .year)
        let style = sameYear
            ? Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day()
            : Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day().year()
        return "\(word) \(closedAt.formatted(style))"
    }

    /// The app's relative ages ("just now", "12m ago", "3d ago") for the span a week allows.
    private static func relative(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
