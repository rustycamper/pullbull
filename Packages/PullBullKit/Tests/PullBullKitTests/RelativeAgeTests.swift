import Foundation
import Testing
@testable import PullBullKit

@Suite struct RelativeAgeTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func shortIsUnchanged() {
        #expect(RelativeAge.short(from: t0, to: t0 + 30) == "now")
        #expect(RelativeAge.short(from: t0, to: t0 + 6 * 3600) == "6h")
        #expect(RelativeAge.short(from: t0, to: t0 + 3 * 86_400) == "3d")
        #expect(RelativeAge.ago(t0, now: t0 + 12 * 60) == "12m ago")
    }

    @Test func spokenSpellsOutUnits() {
        #expect(RelativeAge.spoken(from: t0, to: t0 + 30) == "under a minute")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 60) == "1 minute")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 20 * 60) == "20 minutes")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 3600) == "1 hour")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 86_400) == "1 day")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 4 * 86_400) == "4 days")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 60 * 86_400) == "2 months")
        #expect(RelativeAge.spoken(from: t0, to: t0 + 400 * 86_400) == "1 year")
    }
}
