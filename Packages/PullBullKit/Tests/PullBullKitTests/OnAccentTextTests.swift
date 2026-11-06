import Testing
@testable import PullBullKit

@Suite struct OnAccentTextTests {
    private func black(_ hex: UInt32) -> Bool {
        OnAccentText.prefersBlack(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    @Test func darkAccentsKeepWhiteText() {
        #expect(!black(0x007AFF))  // macOS blue, light
        #expect(!black(0x0A84FF))  // macOS blue, dark
        #expect(!black(0x7A3DD3))  // purple
        #expect(!black(0x000000))
    }

    @Test func lightAccentsGetBlackText() {
        #expect(black(0xFFCC00))  // yellow
        #expect(black(0x34C759))  // green
        #expect(black(0xFF9500))  // orange
        #expect(black(0xFF5257))  // red, light
        #expect(black(0xF74F9E))  // pink, light
        #expect(black(0xFFFFFF))
    }

    @Test func graphiteGetsBlackText() {
        #expect(black(0x989898))  // graphite, dark appearance
        #expect(black(0x8C8C8C))
    }

    @Test func chosenTextIsAlwaysAtLeastThreeAndAHalfToOne() {
        for r in stride(from: 0.0, through: 1.0, by: 0.125) {
            for g in stride(from: 0.0, through: 1.0, by: 0.125) {
                for b in stride(from: 0.0, through: 1.0, by: 0.125) {
                    let l = OnAccentText.luminance(red: r, green: g, blue: b)
                    let against = OnAccentText.prefersBlack(red: r, green: g, blue: b) ? 0.0 : 1.0
                    #expect(OnAccentText.contrast(luminance: l, with: against) >= 3.5)
                }
            }
        }
    }
}
