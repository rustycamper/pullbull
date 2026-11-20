import AppKit
import SwiftUI

// The popover's surface rules: the glass every layer is drawn on, a raised layer floating over content, a
// field, a card and the selection fill. Each look lives here, so every view that uses one matches.

extension EnvironmentValues {
    /// Settings' Solid background, set at the popover's root, so a surface drawing its own glass matches the
    /// panel's.
    @Entry var solidBackground = false
}

/// The popover's background, so a layer drawn on it reads as part of the panel: the material behind the
/// window, or with a solid background the same opaque fill under the window-background material.
struct GlassBackground: View {
    let solid: Bool

    var body: some View {
        ZStack {
            if solid { Color(nsColor: .windowBackgroundColor) }
            EffectView(solid: solid)
        }
        .accessibilityHidden(true)
    }

    private struct EffectView: NSViewRepresentable {
        let solid: Bool

        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.state = .active
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {
            view.material = solid ? .windowBackground : .popover
            view.blendingMode = solid ? .withinWindow : .behindWindow
        }
    }
}

extension View {
    /// A layer floating over content (`RaisedSurface`). `attachedEdge` is the side a panel sits flush
    /// against, which takes no edge and no shadow; `castsShadow` is false while another raised layer covers
    /// this one, since only the topmost casts one.
    func raisedSurface(radius: CGFloat, attachedEdge: Edge? = nil, castsShadow: Bool = true) -> some View {
        modifier(RaisedSurface(radius: radius, attachedEdge: attachedEdge, castsShadow: castsShadow))
    }

    /// A text field's box: `Palette.field` with a separator edge, and while focused a halo of the accent
    /// outside it.
    func fieldSurface(radius: CGFloat, focused: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.separator, lineWidth: 0.5))
            .overlay(
                RoundedRectangle(cornerRadius: radius + 3)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3.5)
                    .padding(-3.5)
                    .opacity(focused ? 1 : 0))
    }

    /// A card: `Palette.card` under a separator edge.
    func cardSurface(radius: CGFloat) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.separator, lineWidth: 0.5))
    }

    /// The selection look, while `selected`: `Palette.selection` behind the content and, under Increase
    /// Contrast, a 1pt accent edge. Draws nothing otherwise, so a hover fill goes underneath.
    func selectionFill(_ selected: Bool, radius: CGFloat) -> some View {
        selectionFill(selected, in: RoundedRectangle(cornerRadius: radius))
    }

    /// `selectionFill(_:radius:)` in another shape, such as a chip's capsule.
    func selectionFill(_ selected: Bool, in shape: some InsettableShape) -> some View {
        modifier(SelectionFill(selected: selected, shape: shape))
    }
}

/// `GlassBackground` with `Palette.lift` over it and the content, clipped to the layer's shape; then its
/// edge (0.5pt separator, or 1pt primary 0.5 under Increase Contrast) and, outside the clip, its shadow. A
/// free-floating layer casts `Palette.raisedShadow` all round, drawn only outside its shape so the glass
/// never darkens. A panel attached to an edge draws no edge of its own, keeping its own `Hairline` as the
/// one rule on its free side, and gets an 8pt gradient beyond that side instead.
private struct RaisedSurface: ViewModifier {
    let radius: CGFloat
    let attachedEdge: Edge?
    let castsShadow: Bool
    @Environment(\.solidBackground) private var solid
    @Environment(\.colorSchemeContrast) private var contrast

    private static let shadowRadius: CGFloat = 8
    private static let shadowY: CGFloat = 2
    /// How far the shadow's mask reaches past the shape, beyond the blur and its offset.
    private static let shadowReach: CGFloat = 24
    private static let gradientDepth: CGFloat = 8

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let increased = contrast == .increased
        content
            .background {
                ZStack {
                    GlassBackground(solid: solid)
                    Palette.lift
                }
            }
            .clipShape(shape)
            .overlay {
                if attachedEdge == nil {
                    shape.strokeBorder(
                        increased ? Color.primary.opacity(0.5) : Palette.separator, lineWidth: increased ? 1 : 0.5)
                }
            }
            .background(alignment: Self.shadowAlignment(attachedEdge)) {
                if castsShadow {
                    shadow(shape: shape, color: increased ? Palette.raisedShadowIncreased : Palette.raisedShadow)
                        .accessibilityHidden(true)
                }
            }
    }

    @ViewBuilder private func shadow(shape: RoundedRectangle, color: Color) -> some View {
        if let attachedEdge {
            let depth = Self.gradientDepth
            switch attachedEdge {
            case .top:
                LinearGradient(colors: [color, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: depth).offset(y: depth).allowsHitTesting(false)
            case .bottom:
                LinearGradient(colors: [.clear, color], startPoint: .top, endPoint: .bottom)
                    .frame(height: depth).offset(y: -depth).allowsHitTesting(false)
            case .leading:
                LinearGradient(colors: [color, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: depth).offset(x: depth).allowsHitTesting(false)
            case .trailing:
                LinearGradient(colors: [.clear, color], startPoint: .leading, endPoint: .trailing)
                    .frame(width: depth).offset(x: -depth).allowsHitTesting(false)
            }
        } else {
            shape.fill(.black)
                .shadow(color: color, radius: Self.shadowRadius, y: Self.shadowY)
                .mask { Rectangle().inset(by: -Self.shadowReach).subtracting(shape) }
                .allowsHitTesting(false)
        }
    }

    /// The side the gradient hangs from: the free side, opposite the attached one.
    private static func shadowAlignment(_ attached: Edge?) -> Alignment {
        switch attached {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        case nil: .center
        }
    }
}

private struct SelectionFill<S: InsettableShape>: ViewModifier {
    let selected: Bool
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                if selected { shape.fill(Palette.selection) }
            }
            .overlay {
                if selected, contrast == .increased { shape.strokeBorder(Color.accentColor, lineWidth: 1) }
            }
    }
}
