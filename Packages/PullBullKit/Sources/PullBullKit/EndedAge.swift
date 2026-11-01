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
        return "\(word) \(date(closedAt, now: now, locale: locale, timeZone: timeZone))"
    }

    /// What an ended item's row and page say: `text`, or the bare "merged" / "closed" without a close date.
    /// nil for an open item.
    public static func label(state: PRState, closedAt: Date?, now: Date) -> String? {
        guard state != .open else { return nil }
        return text(state: state, closedAt: closedAt, now: now) ?? (state == .merged ? "merged" : "closed")
    }

    /// A compact row's age: `text` without the word ("2d", "Oct 12"), as bare as an open compact row's,
    /// since the row's glyph says merged or closed. nil without a close date.
    public static func compact(
        closedAt: Date?, now: Date, locale: Locale = .current, timeZone: TimeZone = .current
    ) -> String? {
        guard let closedAt else { return nil }
        if now.timeIntervalSince(closedAt) <= relativeLimit {
            return RelativeAge.short(from: closedAt, to: now)
        }
        return date(closedAt, now: now, locale: locale, timeZone: timeZone)
    }

    /// The compact age's hover and VoiceOver text: `label` capitalised, "Merged 2d ago".
    public static func help(state: PRState, closedAt: Date?, now: Date) -> String? {
        label(state: state, closedAt: closedAt, now: now).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// "Oct 12", with the year once it isn't this one.
    private static func date(_ closedAt: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let sameYear = calendar.isDate(closedAt, equalTo: now, toGranularity: .year)
        let style = sameYear
            ? Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day()
            : Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.abbreviated).day().year()
        return closedAt.formatted(style)
    }

    /// The app's relative ages ("just now", "12m ago", "3d ago") for the span a week allows. The formats must
    /// match `RelativeAge.ago`.
    private static func relative(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86_400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86_400))d ago"
        }
    }
}
