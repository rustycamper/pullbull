import Foundation

/// Durations as the Stats cards show them. Minutes and hours round down.
public enum StatDuration {
    /// Compact form for cards: "< 1 m", "42 m", "3 h 10 m", "2 d 4 h".
    public static func short(_ t: TimeInterval) -> String {
        let (d, h, m) = parts(t)
        if d > 0 { return h == 0 ? "\(d) d" : "\(d) d \(h) h" }
        if h > 0 { return m == 0 ? "\(h) h" : "\(h) h \(m) m" }
        if m > 0 { return "\(m) m" }
        return "< 1 m"
    }

    /// The same duration spelled out for hover and VoiceOver: "3 hours 10 minutes".
    public static func spoken(_ t: TimeInterval) -> String {
        let (d, h, m) = parts(t)
        func count(_ n: Int, _ unit: String) -> String { n == 1 ? "1 \(unit)" : "\(n) \(unit)s" }
        if d > 0 { return h == 0 ? count(d, "day") : "\(count(d, "day")) \(count(h, "hour"))" }
        if h > 0 { return m == 0 ? count(h, "hour") : "\(count(h, "hour")) \(count(m, "minute"))" }
        if m > 0 { return count(m, "minute") }
        return "under a minute"
    }

    private static func parts(_ t: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        let total = Int(max(0, t))
        return (total / 86_400, total % 86_400 / 3600, total % 3600 / 60)
    }
}
