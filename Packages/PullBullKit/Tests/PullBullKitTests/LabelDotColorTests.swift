import Testing
@testable import PullBullKit

@Suite struct LabelDotColorTests {
    private let enhancement: UInt32 = 0xA2EEEF, p1: UInt32 = 0xB60205, bug: UInt32 = 0xD73A4A

    private func hueDistance(_ a: UInt32, _ b: UInt32) -> Double {
        let d = abs(LabelDotColor.hls(a).h - LabelDotColor.hls(b).h)
        return min(d, 1 - d)
    }

    @Test func parsesGitHubHex() {
        #expect(LabelDotColor.parse("d73a4a") == 0xD73A4A)
        #expect(LabelDotColor.parse("#A2EEEF") == 0xA2EEEF)
        #expect(LabelDotColor.parse(nil) == nil)
        #expect(LabelDotColor.parse("") == nil)
        #expect(LabelDotColor.parse("fff") == nil)
        #expect(LabelDotColor.parse("zzzzzz") == nil)
    }

    @Test func rawColoursFailWhereTheAuditSaid() {
        #expect(LabelDotColor.contrast(enhancement, LabelDotColor.lightBackground) < 1.3)
        #expect(LabelDotColor.contrast(p1, LabelDotColor.darkBackground) < 2.2)
    }

    @Test func paleEnhancementDarkensOnLight() {
        let dot = LabelDotColor.tuned(enhancement, for: .light)
        #expect(LabelDotColor.contrast(dot, LabelDotColor.lightBackground) >= 3.2)
        #expect(LabelDotColor.hls(dot).l < LabelDotColor.hls(enhancement).l)
        #expect(hueDistance(dot, enhancement) < 0.01)
    }

    @Test func darkP1LightensOnDark() {
        let dot = LabelDotColor.tuned(p1, for: .dark)
        #expect(LabelDotColor.contrast(dot, LabelDotColor.darkBackground) >= 3.2)
        #expect(LabelDotColor.hls(dot).l > LabelDotColor.hls(p1).l)
        #expect(hueDistance(dot, p1) < 0.01)
    }

    @Test func colourThatAlreadyPassesKeepsItsLightness() {
        // Pale enhancement on dark and dark P1 on light already pass; only saturation is capped.
        #expect(LabelDotColor.tuned(enhancement, for: .dark) == enhancement)
        let p1Light = LabelDotColor.tuned(p1, for: .light)
        #expect(abs(LabelDotColor.hls(p1Light).l - LabelDotColor.hls(p1).l) < 0.01)
        #expect(LabelDotColor.hls(p1Light).s <= 0.72 + 0.01)
    }

    @Test func midColourIsLeftNearlyUnchanged() {
        for appearance in [LabelDotColor.Appearance.light, .dark] {
            let dot = LabelDotColor.tuned(bug, for: appearance)
            #expect(dot == bug)
            #expect(LabelDotColor.contrast(dot, LabelDotColor.background(appearance)) >= 3.2)
        }
    }

    @Test func hueIsPreservedAcrossGitHubDefaults() {
        let defaults: [UInt32] = [0xD73A4A, 0xA2EEEF, 0x0075CA, 0x7057FF, 0x008672, 0xD876E3, 0xB60205, 0xFBCA04]
        for colour in defaults {
            for appearance in [LabelDotColor.Appearance.light, .dark] {
                let dot = LabelDotColor.tuned(colour, for: appearance)
                #expect(hueDistance(dot, colour) < 0.02)
                #expect(LabelDotColor.contrast(dot, LabelDotColor.background(appearance)) >= 3.2)
            }
        }
    }

    @Test func whiteBecomesGrayOnLight() {
        let dot = LabelDotColor.tuned(0xFFFFFF, for: .light)
        #expect(LabelDotColor.hls(dot).s == 0)
        #expect(LabelDotColor.contrast(dot, LabelDotColor.lightBackground) >= 3.2)
    }

    @Test func increaseContrastReachesItsTarget() {
        for colour: UInt32 in [enhancement, p1, bug, 0xFBCA04] {
            for appearance in [LabelDotColor.Appearance.light, .dark] {
                let dot = LabelDotColor.tuned(colour, for: appearance, target: LabelDotColor.highContrastTarget)
                #expect(LabelDotColor.contrast(dot, LabelDotColor.background(appearance)) >= 4.5)
            }
        }
    }

    @Test func matchesTheAuditTable() {
        #expect(LabelDotColor.tuned(enhancement, for: .light) == 0x1A9597)
        #expect(LabelDotColor.tuned(p1, for: .dark) == 0xDD3134)
        #expect(LabelDotColor.tuned(0xFFFFFF, for: .light) == 0x868686)
    }
}
