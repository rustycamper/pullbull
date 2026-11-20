import SwiftUI

/// Group headers pin to the top of the list while their group scrolls under them, until the next header
/// pushes them off, so the repo or lane of the rows in view stays named.
enum PinnedHeader {
    /// Room kept above a row scrolled to, so it lands below the pinned header rather than under it: a
    /// `ListSectionHeader` and 6pt of air.
    static let clearance: CGFloat = ListSectionHeader.height + 6
}

extension View {
    /// A header's backing, so rows scrolling beneath it while it is pinned are hidden rather than show
    /// through: the popover's own glass (`GlassBackground`, no lift) across the full list width, so a header
    /// at rest reads as part of the list and never as a band above it.
    func pinnedHeaderBackground() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PinnedHeaderGlass()
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

/// `GlassBackground` as Solid background asks, for `pinnedHeaderBackground()`.
private struct PinnedHeaderGlass: View {
    @Environment(\.solidBackground) private var solid

    var body: some View {
        GlassBackground(solid: solid)
    }
}
