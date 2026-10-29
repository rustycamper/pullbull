import Foundation
import Testing
@testable import PullBullKit

@Suite struct EndedAgeTests {
    static let utc = TimeZone(identifier: "UTC")!
    static let locale = Locale(identifier: "en_US")
    // 2023-11-14 22:13:20 UTC
    static let now = Date(timeIntervalSince1970: 1_700_000_000)
    static let day: TimeInterval = 86_400

    static func text(_ state: PRState, closedAgo: TimeInterval?, now: Date = now) -> String? {
        EndedAge.text(
            state: state, closedAt: closedAgo.map { now.addingTimeInterval(-$0) }, now: now,
            locale: locale, timeZone: utc)
    }

    @Test func recentIsRelative() {
        #expect(Self.text(.merged, closedAgo: 10) == "merged just now")
        #expect(Self.text(.merged, closedAgo: 12 * 60) == "merged 12m ago")
        #expect(Self.text(.closed, closedAgo: 5 * 3600) == "closed 5h ago")
        #expect(Self.text(.merged, closedAgo: 3 * Self.day) == "merged 3d ago")
    }

    @Test func sevenDaysExactlyIsStillRelative() {
        #expect(Self.text(.merged, closedAgo: 7 * Self.day) == "merged 7d ago")
    }

    @Test func pastSevenDaysIsAbsolute() {
        // now - 7d - 1s = 2023-11-07 22:13:19 UTC
        #expect(Self.text(.merged, closedAgo: 7 * Self.day + 1) == "merged Nov 7")
        #expect(Self.text(.closed, closedAgo: 33 * Self.day) == "closed Oct 12")
    }

    @Test func otherYearAddsTheYear() {
        #expect(Self.text(.merged, closedAgo: 400 * Self.day) == "merged Oct 10, 2022")
    }

    @Test func dayBoundaryFollowsTheTimeZone() {
        // 2023-10-12 02:00 UTC is still Oct 11 in Los Angeles.
        let closed = Date(timeIntervalSince1970: 1_697_076_000)
        let la = TimeZone(identifier: "America/Los_Angeles")!
        #expect(EndedAge.text(state: .closed, closedAt: closed, now: Self.now, locale: Self.locale, timeZone: la)
            == "closed Oct 11")
        #expect(EndedAge.text(state: .closed, closedAt: closed, now: Self.now, locale: Self.locale, timeZone: Self.utc)
            == "closed Oct 12")
    }

    @Test func futureCloseDateReadsAsJustNow() {
        #expect(Self.text(.closed, closedAgo: -30) == "closed just now")
    }

    @Test func openOrUndatedHasNoText() {
        #expect(Self.text(.open, closedAgo: 60) == nil)
        #expect(Self.text(.merged, closedAgo: nil) == nil)
    }
}
