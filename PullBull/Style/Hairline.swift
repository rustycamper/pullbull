import SwiftUI

/// The one separator weight: a single device pixel in `Palette.separator`. Horizontal fills the width;
/// vertical fills the height.
struct Hairline: View {
    var axis: Axis = .horizontal
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let weight = 1 / displayScale
        Palette.separator
            .frame(width: axis == .vertical ? weight : nil, height: axis == .horizontal ? weight : nil)
    }
}
