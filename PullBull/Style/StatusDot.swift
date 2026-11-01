import PullBullKit
import SwiftUI

/// A board Status as a filled dot in the colour the owner gave its option, as GitHub shows it; an option
/// without a colour is gray. Decorative: the Status's name sits beside it.
struct StatusDot: View {
    let color: StatusOptionColor?

    var body: some View {
        Circle()
            .fill(color.map(Palette.statusOptionColor) ?? .secondary)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}
