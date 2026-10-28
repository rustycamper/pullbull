import SwiftUI

/// A list or search row's rounded fill: the keyboard highlight, the hover tint, or, while the row
/// flashes on being chosen, the system selection colour with the text switched to its selected colour
/// and the content drawn in the dark appearance, so coloured glyphs and pills take their light-on-dark
/// variants. Only colours change, so the row keeps its geometry.
struct RowFill: ViewModifier {
    let cornerRadius: CGFloat
    let selected: Bool
    let hovering: Bool
    var flashing = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(flashing ? AnyShapeStyle(Palette.rowFlashText) : AnyShapeStyle(.primary))
            .environment(\.backgroundProminence, flashing ? .increased : .standard)
            // The content only: the fill keeps the outer appearance.
            .environment(\.colorScheme, flashing ? .dark : colorScheme)
            .background(RoundedRectangle(cornerRadius: cornerRadius).fill(fill))
    }

    private var fill: Color {
        if flashing { return Palette.rowFlash }
        if selected { return Palette.selection }
        return hovering ? Palette.rowHover : .clear
    }
}
