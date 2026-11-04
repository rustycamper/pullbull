import Foundation

public enum Median {
    /// The middle value; the mean of the two middle values for an even count.
    /// `nil` for no samples, so the card shows "–" rather than a made-up zero.
    public static func of(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
