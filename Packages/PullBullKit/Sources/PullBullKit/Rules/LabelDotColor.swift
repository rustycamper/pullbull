import Foundation

/// A label's GitHub colour tuned into a small dot that reads on the popover. GitHub's raw colours
/// often fail contrast (`enhancement` #A2EEEF is 1.17:1 on light), so the hue is kept, saturation is
/// capped, and lightness walks down (light) or up (dark) until the dot reaches `target` against the
/// popover background. Colours are 0xRRGGBB.
public enum LabelDotColor {
    public enum Appearance: Sendable { case light, dark }

    /// The popover material, about this in each appearance.
    public static let lightBackground: UInt32 = 0xF2F1F5
    public static let darkBackground: UInt32 = 0x28272D
    public static let maxSaturation = 0.72
    /// Non-text marks need 3:1; a little over leaves room for the material's tint.
    public static let target = 3.2
    /// Under Increase Contrast.
    public static let highContrastTarget = 4.5

    /// GitHub's label `color`, "d73a4a" (with or without "#"); nil for anything else.
    public static func parse(_ hex: String?) -> UInt32? {
        guard var hex else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex, radix: 16)
    }

    public static func background(_ appearance: Appearance) -> UInt32 {
        appearance == .light ? lightBackground : darkBackground
    }

    /// The dot colour for `color` in `appearance`.
    public static func tuned(_ color: UInt32, for appearance: Appearance, target: Double = target) -> UInt32 {
        var (h, l, s) = hls(color)
        s = min(s, maxSaturation)
        let bg = background(appearance)
        let step = appearance == .light ? -0.005 : 0.005
        var candidate = rgb(h: h, l: l, s: s)
        for _ in 0..<200 {
            candidate = rgb(h: h, l: l, s: s)
            if contrast(candidate, bg) >= target { return candidate }
            l = min(1, max(0, l + step))
        }
        return candidate
    }

    /// WCAG contrast ratio between two colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// WCAG relative luminance.
    public static func luminance(_ c: UInt32) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (r, g, b) = components(c)
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// Hue (0..<1), lightness and saturation, as Python's `colorsys.rgb_to_hls`.
    public static func hls(_ c: UInt32) -> (h: Double, l: Double, s: Double) {
        let (r, g, b) = components(c)
        let hi = max(r, g, b), lo = min(r, g, b)
        let l = (hi + lo) / 2
        guard hi != lo else { return (0, l, 0) }
        let d = hi - lo
        let s = l <= 0.5 ? d / (hi + lo) : d / (2 - hi - lo)
        let rc = (hi - r) / d, gc = (hi - g) / d, bc = (hi - b) / d
        var h = r == hi ? bc - gc : g == hi ? 2 + rc - bc : 4 + gc - rc
        h = (h / 6).truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        return (h, l, s)
    }

    private static func rgb(h: Double, l: Double, s: Double) -> UInt32 {
        guard s > 0 else { return pack(l, l, l) }
        let m2 = l <= 0.5 ? l * (1 + s) : l + s - l * s
        let m1 = 2 * l - m2
        func v(_ hue: Double) -> Double {
            var hue = hue.truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            if hue < 1.0 / 6 { return m1 + (m2 - m1) * hue * 6 }
            if hue < 0.5 { return m2 }
            if hue < 2.0 / 3 { return m1 + (m2 - m1) * (2.0 / 3 - hue) * 6 }
            return m1
        }
        return pack(v(h + 1.0 / 3), v(h), v(h - 1.0 / 3))
    }

    private static func components(_ c: UInt32) -> (Double, Double, Double) {
        (Double((c >> 16) & 0xFF) / 255, Double((c >> 8) & 0xFF) / 255, Double(c & 0xFF) / 255)
    }

    private static func pack(_ r: Double, _ g: Double, _ b: Double) -> UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(min(255, max(0, (v * 255).rounded()))) }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }
}
