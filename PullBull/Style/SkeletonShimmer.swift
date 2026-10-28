import SwiftUI

extension View {
    /// Placeholder shapes that feel alive. Shapes filled with the foreground style draw in `Palette.fill`,
    /// and one soft highlight band sweeps left to right across all of them together, masked to the shapes so
    /// the background between them never changes. Under Reduce Motion the shapes pulse calmly to a
    /// stronger neutral fill and back instead. Nothing animates while `skeletonAnimates` is false; at rest
    /// the shapes are plain `Palette.fill`. Layout is untouched.
    func skeletonShimmer() -> some View {
        modifier(SkeletonShimmer())
    }
}

private struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.skeletonAnimates) private var animates
    /// 0 → 1 over one sweep and the pause after it.
    @State private var phase: CGFloat = 0
    @State private var pulsed = false

    private static let sweep: Double = 1.5
    private static let pause: Double = 0.7
    private static let pulse: Double = 1.2

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Palette.fill)
            .overlay {
                if reduceMotion {
                    // A second `Palette.fill` on the shapes: about twice the alpha at the top of the pulse.
                    Rectangle()
                        .fill(Palette.fill)
                        .opacity(pulsed ? 1 : 0)
                        .mask { content.foregroundStyle(.black) }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    GeometryReader { geometry in
                        let band = max(geometry.size.width * 0.35, 80)
                        // The band crosses in `sweep` and stays past the trailing edge for the pause.
                        let travel = (geometry.size.width + band) * (Self.sweep + Self.pause) / Self.sweep
                        LinearGradient(
                            colors: [.clear, Palette.shimmer, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: band, height: geometry.size.height)
                            .offset(x: phase * travel - band)
                    }
                    // The same shapes, opaque, so the band shows at full strength on them and nowhere else.
                    .mask { content.foregroundStyle(.black) }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear(perform: start)
            .onChange(of: reduceMotion) { start() }
            .onChange(of: animates) { start() }
    }

    /// A non-animated reset replaces any running repeat, so a stopped skeleton does no work.
    private func start() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            phase = 0
            pulsed = false
        }
        guard animates else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: Self.pulse).repeatForever(autoreverses: true)) { pulsed = true }
        } else {
            withAnimation(.linear(duration: Self.sweep + Self.pause).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// A rounded placeholder bar centred in the height of one line of `font`, which is laid out but not drawn.
/// It fills with the foreground style, which `skeletonShimmer()` sets.
struct SkeletonBar: View {
    enum Width {
        case fixed(CGFloat)
        case fraction(CGFloat)
    }

    let font: Font
    let width: Width
    let height: CGFloat

    var body: some View {
        Text(" ")
            .font(font)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    let length: CGFloat = switch width {
                    case .fixed(let value): min(value, geometry.size.width)
                    case .fraction(let value): geometry.size.width * value
                    }
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.foreground)
                        .frame(width: length, height: height)
                        .position(x: length / 2, y: geometry.size.height / 2)
                }
            }
    }
}

extension EnvironmentValues {
    /// Whether skeletons animate: false while the popover is closed or a layer covers them.
    @Entry var skeletonAnimates = true
}
