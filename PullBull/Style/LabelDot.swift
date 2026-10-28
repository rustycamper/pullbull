import SwiftUI
import PullBullKit

/// The 6pt dot that leads a label chip, in the label's GitHub colour tuned for this appearance
/// (`LabelDotColor`). Decorative: the chip's text names the label, so VoiceOver skips the dot.
struct LabelDot: View {
    let color: UInt32
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tuned = LabelDotColor.tuned(
            color, for: colorScheme == .dark ? .dark : .light,
            target: contrast == .increased ? LabelDotColor.highContrastTarget : LabelDotColor.target)
        Circle()
            .fill(Color(
                .sRGB, red: Double((tuned >> 16) & 0xFF) / 255, green: Double((tuned >> 8) & 0xFF) / 255,
                blue: Double(tuned & 0xFF) / 255))
            .overlay(Circle().strokeBorder(Palette.separator, lineWidth: 0.5))
            .frame(width: 6, height: 6)
            .accessibilityHidden(true)
    }
}
