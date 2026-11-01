/// Where the list selection goes when an edit moves its row, and back when the edit is taken back.
public struct EditSelection: Equatable, Sendable {
    public enum Follow: Equatable, Sendable {
        /// Leave the selection.
        case none
        /// The selected row is still shown, elsewhere: scroll to it.
        case scroll
        /// Select this row.
        case select(PRKey?)
    }

    /// The edited row that left the list, and the row selected in its place.
    private var left: PRKey?
    private var standIn: PRKey?

    public init() {}

    /// What to do with `selection` after an edit of `key` changed the rows from `before` to `after`.
    /// A row that left the list while selected is selected again when it comes back, unless the
    /// selection moved meanwhile.
    public mutating func follow(_ key: PRKey, selection: PRKey?, from before: [PRKey], to after: [PRKey]) -> Follow {
        if selection == key {
            left = nil
            if after.contains(key) { return .scroll }
            let next = ListNavigation.selection(key, from: before, to: after)
            (left, standIn) = (key, next)
            return .select(next)
        }
        guard left == key, selection == standIn, after.contains(key) else { return .none }
        left = nil
        return .select(key)
    }
}
