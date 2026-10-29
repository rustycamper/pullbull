import SwiftUI

/// Group headers pin to the top of the list while their group scrolls under them, until the next header
/// pushes them off, so the repo or lane of the rows in view stays named.
enum PinnedHeader {
    /// Room kept above a row scrolled to, so it lands below the pinned header rather than under it: the
    /// tallest header, Done's (32pt and 2pt above it).
    static let clearance: CGFloat = 34
}

extension View {
    /// A header's backing, so rows scrolling beneath it while it is pinned blur rather than show through: a
    /// translucent SwiftUI material (drawn in the list, unlike an AppKit effect view) across the full list width.
    func pinnedHeaderBackground() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle().fill(.thinMaterial)
                    .padding(.horizontal, -Metrics.rowInset)
            }
    }

    /// The row's scroll identity, reaching `clearance` above it, so scrolling up to the row leaves room for
    /// a pinned header; the row's own layout is unchanged.
    func scrollTarget<ID: Hashable>(_ id: ID, clearance: CGFloat) -> some View {
        padding(.top, clearance)
            .id(id)
            .padding(.top, -clearance)
    }
}
