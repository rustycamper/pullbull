import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatDurationTests {
    private func seconds(d: Int = 0, h: Int = 0, m: Int = 0, s: Int = 0) -> TimeInterval {
        TimeInterval(d * 86_400 + h * 3600 + m * 60 + s)
    }

    @Test func shortForms() {
        #expect(StatDuration.short(30) == "< 1 m")
        #expect(StatDuration.short(seconds(m: 42)) == "42 m")
        #expect(StatDuration.short(seconds(h: 3, m: 10)) == "3 h 10 m")
        #expect(StatDuration.short(seconds(h: 3)) == "3 h")
        #expect(StatDuration.short(seconds(d: 2, h: 4, m: 59)) == "2 d 4 h")
        #expect(StatDuration.short(seconds(d: 2)) == "2 d")
    }

    @Test func spokenForms() {
        #expect(StatDuration.spoken(30) == "under a minute")
        #expect(StatDuration.spoken(seconds(m: 1)) == "1 minute")
        #expect(StatDuration.spoken(seconds(m: 42)) == "42 minutes")
        #expect(StatDuration.spoken(seconds(h: 3, m: 10)) == "3 hours 10 minutes")
        #expect(StatDuration.spoken(seconds(h: 3)) == "3 hours")
        #expect(StatDuration.spoken(seconds(h: 1, m: 1)) == "1 hour 1 minute")
        #expect(StatDuration.spoken(seconds(d: 2, h: 4, m: 59)) == "2 days 4 hours")
        #expect(StatDuration.spoken(seconds(d: 1, h: 1)) == "1 day 1 hour")
        #expect(StatDuration.spoken(seconds(d: 2)) == "2 days")
    }

    @Test func medianOfNothingIsNil() {
        #expect(Median.of([]) == nil)
    }

    @Test func medianOfOddAndEvenCounts() {
        #expect(Median.of([3, 1, 2]) == 2)
        #expect(Median.of([1, 2, 3, 4]) == 2.5)
    }
}
