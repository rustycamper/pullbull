import Foundation

/// The text colour for a button filled with the user's accent colour. The accent can be anything from
/// graphite to yellow, so white is kept only while it reads on the fill; past that, black does.
public enum OnAccentText {
    /// The lowest white-on-fill contrast that still gets white text. It is under WCAG AA's 4.5 on purpose:
    /// the system's prominent buttons keep white on the default blue, which is 4.0 in light and 3.7 in dark.
    /// Below it black is used, and black then reads at 5.2 or more.
    public static let whiteFloor = 3.5

    /// Whether black text reads better than white on a fill of sRGB components in 0...1.
    public static func prefersBlack(red: Double, green: Double, blue: Double) -> Bool {
        contrast(luminance: luminance(red: red, green: green, blue: blue), with: 1) < whiteFloor
    }

    /// WCAG relative luminance of an sRGB colour.
    public static func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between a luminance and white (1) or black (0).
    public static func contrast(luminance: Double, with other: Double) -> Double {
        let (hi, lo) = (max(luminance, other), min(luminance, other))
        return (hi + 0.05) / (lo + 0.05)
    }
}
