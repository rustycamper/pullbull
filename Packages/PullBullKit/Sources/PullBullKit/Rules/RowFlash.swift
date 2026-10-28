import Foundation

/// The brief highlight on a list or search row chosen to open its detail, as a menu item blinks when
/// picked. One row at a time: a click or Return during the flash opens nothing more. `Context` is what
/// was on screen when the row was chosen; the detail opens only if it is the same when the flash ends.
public struct RowFlash<Context: Equatable & Sendable>: Equatable, Sendable {
    /// How long the row stays highlighted before its detail opens.
    public static var duration: Duration { .milliseconds(110) }

    /// The row flashing; nil between flashes.
    public private(set) var key: PRKey?
    private var context: Context?

    public init() {}

    /// Starts flashing `key`; false while a flash is running, and then nothing changes.
    public mutating func begin(_ key: PRKey, context: Context) -> Bool {
        guard self.key == nil else { return false }
        self.key = key
        self.context = context
        return true
    }

    /// Ends the flash, whatever it returns. True when the detail should open: a flash was running and
    /// `context` is the one it began in.
    public mutating func end(context: Context) -> Bool {
        defer {
            key = nil
            self.context = nil
        }
        return key != nil && self.context == context
    }
}
