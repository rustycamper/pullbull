import Foundation

/// What the popover shows when it opens again after being closed with a detail on screen.
public enum PopoverReopen {
    /// A reopen sooner than this keeps the detail; at this long or later it opens on the list.
    public static let keepDetailFor: TimeInterval = 60

    public static func showsList(closedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(closedAt) >= keepDetailFor
    }
}
