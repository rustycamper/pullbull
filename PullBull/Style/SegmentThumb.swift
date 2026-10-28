import SwiftUI

/// The soft fill and hairline behind the selected segment of a segmented control. The tab bar draws it.
struct SegmentThumb: View {
    var radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Palette.strongFill)
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.separator, lineWidth: 0.5))
    }
}
