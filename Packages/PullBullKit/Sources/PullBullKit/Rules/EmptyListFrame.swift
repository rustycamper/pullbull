import Foundation

/// The height of an empty or loading state, so the glyph sits where the tab draws it.
public enum EmptyListFrame {
    /// Shorter with a Recently closed or Done section below, which takes the rest of the room.
    public static func height(sectionBelow: Bool) -> Double {
        sectionBelow ? 260 : 400
    }
}
