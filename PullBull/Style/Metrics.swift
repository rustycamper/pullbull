import SwiftUI

/// Shared horizontal edges, so every surface hangs off one vertical line.
enum Metrics {
    /// Where content starts on list surfaces: the field's magnifier, filter row, group headers, rows and footer.
    static let listGutter: CGFloat = 14
    /// Where content starts in the PR and issue details.
    static let detailGutter: CGFloat = 16
    /// The inset of the list's row highlight, which the search field's rounded edge lines up with.
    static let rowInset: CGFloat = 6
}
