import Foundation

/// The height of an empty or loading state. Without a section below, a fixed height, so the glyph sits
/// where every tab and search draw it. With a folded Recently closed or Done section below, the rest of the
/// viewport, so the section's header sits at the bottom instead of floating over empty space. With that
/// section open, the state's own height, so the section's rows get the room.
public enum EmptyListFrame {
    public enum Below: Equatable, Sendable {
        case nothing
        /// A folded section whose header, and the gaps around it, take `height` under the state.
        case folded(height: Double)
        case open
    }

    static let withoutSection: Double = 400
    /// The least a folded section leaves the state, in a viewport too short to share.
    static let floor: Double = 260

    /// Nil when the state takes its own height.
    public static func height(below: Below, viewport: Double) -> Double? {
        switch below {
        case .nothing: withoutSection
        case .folded(let height): max(floor, viewport - height)
        case .open: nil
        }
    }
}
