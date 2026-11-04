import Foundation
import Testing
@testable import PullBullKit

@Suite struct StatsReportTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let hour: TimeInterval = 3600
    let day: TimeInterval = 86_400
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// `count` PRs reviewed `daysAgo` days back, the first `asked` of them after a request `wait` hours before.
    func reviewed(_ count: Int, asked: Int, daysAgo: Double, wait: Double = 3) -> [ReviewedPR] {
        (0..<count).map { i in
            let at = now.addingTimeInterval(-daysAgo * day)
            let requests = i < asked
                ? [ReviewRequestEvent(at: at.addingTimeInterval(-wait * hour), reviewer: .user("me"))] : []
            return ReviewedPR(
                repo: "acme/app", author: "dana", updatedAt: at, requests: requests,
                myReviews: [MyReview(submittedAt: at, pending: false)])
        }
    }

    func facts(
        reviewed: Result<Capped<ReviewedPR>, StatsFailure>? = nil,
        reviewedBefore: Result<Capped<ReviewedPR>, StatsFailure>? = nil,
        opened: Result<CountedList<OpenedPR>, StatsFailure> = .success(CountedList(total: 0, items: [])),
        merged: Result<CountedList<MergedPR>, StatsFailure> = .success(CountedList(total: 0, items: [])),
        comments: Result<Capped<Date>, StatsFailure> = .success(Capped(items: [], capped: false))
    ) -> StatsFacts {
        StatsFacts(
            reviewed: reviewed ?? .success(Capped(items: self.reviewed(12, asked: 9, daysAgo: 1), capped: false)),
            reviewedBefore: reviewedBefore
                ?? .success(Capped(items: self.reviewed(9, asked: 9, daysAgo: 8, wait: 5), capped: false)),
            opened: opened, openedBefore: .success(CountedList(total: 0, items: [])),
            merged: merged, mergedBefore: .success(CountedList(total: 0, items: [])),
            closed: .success(2), closedBefore: .success(1),
            issuesOpened: .success(3), issuesOpenedBefore: .success(0),
            comments: comments)
    }

    func build(_ facts: StatsFacts, period: StatsPeriod = .week) -> StatsReport {
        StatsReport.build(facts, period: period, me: "me", myTeams: [], now: now, calendar: calendar)
    }

    @Test func fullReport() {
        let report = build(facts())
        #expect(report.reviews.text == "12")
        #expect(report.reviews.comparison == "last week 9")
        #expect(report.turnaround.text == "3 h")
        #expect(report.turnaround.comparison == "last week 5 h")
        #expect(report.turnaround.hover == "Median of 9 reviews you were asked for")
        #expect(report.isComplete)
        #expect(!report.anyCapped)
        #expect(report.footerCapNote == nil)
        #expect(report.issuesClosed.text == "2")
        #expect(report.issuesClosed.comparison == "last week 1")
        #expect(report.issuesOpened.comparison == "last week 0")
        #expect(report.comments.comparison == nil)
        #expect(report.bars != nil)
        #expect(report.topReviewers == [])
    }

    @Test func noSamples() {
        let report = build(facts(reviewed: .success(Capped(items: reviewed(4, asked: 0, daysAgo: 1), capped: false))))
        #expect(report.turnaround.text == "–")
        #expect(report.turnaround.spoken == "not available")
        #expect(report.turnaround.comparison == nil)
        #expect(report.turnaround.hover == "No reviews you were asked for in this period")
    }

    @Test func failedComparisonDropsComparison() {
        let report = build(facts(reviewedBefore: .failure(StatsFailure(message: "rate limited"))))
        #expect(report.reviews.comparison == nil)
        #expect(report.turnaround.comparison == nil)
        #expect(report.reviews.text == "12")
        #expect(report.failures == ["rate limited"])
        #expect(!report.isComplete)
    }

    @Test func failedSourceIsUnknown() {
        let report = build(facts(reviewed: .failure(StatsFailure(message: "boom"))))
        #expect(report.reviews.text == "–")
        #expect(report.reviews.spoken == "not available")
        #expect(report.turnaround.text == "–")
        #expect(report.bars == nil)
        #expect(report.issuesClosed.text == "2")
    }

    @Test func failuresDeduplicated() {
        let fail = StatsFailure(message: "offline")
        let report = build(facts(reviewed: .failure(fail), reviewedBefore: .failure(fail), merged: .failure(fail)))
        #expect(report.failures == ["offline"])
        #expect(report.topReviewers == [])
    }

    @Test func cappedTally() {
        let items = reviewed(137, asked: 0, daysAgo: 1)
        let report = build(facts(reviewed: .success(Capped(items: items, capped: true))))
        #expect(report.reviews.text == "137+")
        #expect(report.reviews.capped)
        #expect(report.anyCapped)
        #expect(report.footerCapNote == "· from latest 100")
        #expect(report.reviews.hover?.hasSuffix("From the latest 100 PRs") == true)
        #expect(report.turnaround.hover?.hasSuffix("From the latest 100 PRs") == true)
    }

    @Test func cappedBarsHideUnloadedDays() {
        var prs = reviewed(3, asked: 0, daysAgo: 1)
        prs += reviewed(1, asked: 0, daysAgo: 3)
        let report = build(facts(reviewed: .success(Capped(items: prs, capped: true))))
        #expect(report.bars?.counts.first == .some(nil))
    }

    @Test func cappedWithNothingLoadedMarksEveryDayNotLoaded() {
        let report = build(facts(reviewed: .success(Capped(items: [], capped: true))))
        #expect(report.bars?.counts == Array(repeating: nil, count: 7))
    }

    @Test func cappedBarsLoadFromTheOldestUpdate() {
        let at = now.addingTimeInterval(-3 * day)
        let pr = ReviewedPR(
            repo: "acme/app", author: "dana", updatedAt: now.addingTimeInterval(-1 * day), requests: [],
            myReviews: [MyReview(submittedAt: at, pending: false)])
        let report = build(facts(reviewed: .success(Capped(items: [pr], capped: true))))
        #expect(report.reviews.text == "1+")
        #expect(report.bars?.counts == [nil, nil, nil, nil, nil, nil, 0])
    }

    @Test func reviewOnPRUpdatedLaterFillsItsDay() {
        let pr = ReviewedPR(
            repo: "acme/app", author: "dana", updatedAt: now, requests: [],
            myReviews: [MyReview(submittedAt: now.addingTimeInterval(-3 * day), pending: false)])
        let report = build(facts(reviewed: .success(Capped(items: [pr], capped: false))))
        #expect(report.reviews.text == "1")
        #expect(report.bars?.counts == [0, 0, 0, 1, 0, 0, 0])
    }

    @Test func cappedTurnaroundHoverJoinsTheCapSentence() {
        let items = reviewed(12, asked: 9, daysAgo: 1)
        let report = build(facts(reviewed: .success(Capped(items: items, capped: true))))
        #expect(report.turnaround.hover == "Median of 9 reviews you were asked for. From the latest 100 PRs")
    }

    @Test func cappedTurnaroundHoverWithNoSamples() {
        let items = reviewed(4, asked: 0, daysAgo: 1)
        let report = build(facts(reviewed: .success(Capped(items: items, capped: true))))
        #expect(report.turnaround.hover == "No reviews you were asked for in this period. From the latest 100 PRs")
    }

    @Test func timeToMergeHasNoHoverWithNothingMerged() {
        let report = build(facts(merged: .success(CountedList(total: 0, items: []))))
        #expect(report.timeToMerge.text == "–")
        #expect(report.timeToMerge.hover == nil)
    }

    @Test func timeToMergeHoverUncapped() {
        let prs = (0..<3).map { _ in
            MergedPR(createdAt: now.addingTimeInterval(-3 * day), mergedAt: now.addingTimeInterval(-2 * day))
        }
        let report = build(facts(merged: .success(CountedList(total: 3, items: prs))))
        #expect(report.timeToMerge.hover == "Median of 3 merged PRs")
    }

    @Test func cappedComparison() {
        let before = Capped(items: reviewed(137, asked: 0, daysAgo: 8), capped: true)
        let report = build(facts(reviewedBefore: .success(before)))
        #expect(report.reviews.comparison == "last week 137+")
    }

    @Test func commentsOnlyCapped() {
        let dates = (0..<500).map { now.addingTimeInterval(-Double($0)) }
        let report = build(facts(comments: .success(Capped(items: dates, capped: true))))
        #expect(report.comments.text == "500+")
        #expect(report.comments.hover == "From your latest 500 comments")
        #expect(report.anyCapped)
        #expect(report.footerCapNote == "· from latest 500 comments")
        #expect(report.reviews.hover == nil)
    }

    func opened(waitHours: Double?, open: Bool = true) -> OpenedPR {
        let created = now.addingTimeInterval(-2 * day)
        let reviews = waitHours.map {
            [OpenedPRReview(
                author: "dana", avatarURL: nil, byBot: false,
                submittedAt: created.addingTimeInterval($0 * hour), pending: false)]
        } ?? []
        return OpenedPR(createdAt: created, isDraft: false, isOpen: open, readyAt: nil, reviews: reviews)
    }

    @Test func firstReviewHover() {
        let prs = (0..<6).map { _ in opened(waitHours: 3) } + [opened(waitHours: nil), opened(waitHours: nil)]
        let report = build(facts(opened: .success(CountedList(total: 8, items: prs))))
        #expect(report.firstReview.text == "3 h")
        #expect(report.firstReview.hover
            == "Median of 6 PRs. 2 of your PRs opened in this period still wait for a first review.")
        #expect(report.topReviewers == [TopReviewer(login: "dana", avatarURL: nil, prCount: 6)])
    }

    @Test func mergedExact() {
        let prs = (0..<3).map { _ in
            MergedPR(createdAt: now.addingTimeInterval(-3 * day), mergedAt: now.addingTimeInterval(-2 * day))
        }
        let report = build(facts(merged: .success(CountedList(total: 140, items: prs))))
        #expect(report.merged.text == "140")
        #expect(report.merged.hover == nil)
        #expect(report.timeToMerge.text == "1 d")
        #expect(report.timeToMerge.hover == "Median of 3 merged PRs. From the latest 100 PRs")
        #expect(report.anyCapped)
    }

    @Test func comparisonSplitsIntoLabelAndValue() {
        let merged = (0..<5).map { _ in
            MergedPR(createdAt: now.addingTimeInterval(-3 * day), mergedAt: now.addingTimeInterval(-2 * day))
        }
        let report = build(facts(merged: .success(CountedList(total: 5, items: merged))), period: .quarter)
        #expect(report.merged.previous == StatComparison(label: "previous 90 days", value: "0"))
        #expect(report.merged.comparison == "previous 90 days 0")
        #expect(build(facts()).turnaround.previous == StatComparison(label: "last week", value: "5 h"))
        #expect(report.timeToMerge.previous == nil)
        #expect(report.timeToMerge.comparison == nil)
    }

    @Test func cardHintJoinsTheHoversAndSaysTheCapOnce() {
        let items = reviewed(137, asked: 9, daysAgo: 1)
        let report = build(facts(reviewed: .success(Capped(items: items, capped: true))))
        #expect(report.cardHint(.reviews)
            == "From the latest 100 PRs. Median of 9 reviews you were asked for")
    }

    @Test func cardHintKeepsASentencesOwnPeriod() {
        let prs = (0..<6).map { _ in opened(waitHours: 3) } + [opened(waitHours: nil), opened(waitHours: nil)]
        let merged = (0..<3).map { _ in
            MergedPR(createdAt: now.addingTimeInterval(-3 * day), mergedAt: now.addingTimeInterval(-2 * day))
        }
        let report = build(facts(
            opened: .success(CountedList(total: 8, items: prs)), merged: .success(CountedList(total: 3, items: merged))))
        #expect(report.cardHint(.pullRequests)
            == "Median of 3 merged PRs. Median of 6 PRs. 2 of your PRs opened in this period still wait for a first review.")
    }

    @Test func cardHintNilWithoutHovers() {
        #expect(build(facts()).cardHint(.issues) == nil)
    }

    @Test func topReviewersNilWhenOpenedFailed() {
        let report = build(facts(opened: .failure(StatsFailure(message: "x"))))
        #expect(report.topReviewers == nil)
        #expect(report.firstReview.text == "–")
    }

    @Test func reviewsSpeech() {
        let report = build(facts())
        #expect(report.cardSpeech(.reviews)
            == "Your reviews, this week: 12 reviews, last week 9. Median turnaround 3 hours, last week 5 hours.")
    }

    @Test func issuesSpeech() {
        let dates = (0..<14).map { now.addingTimeInterval(-Double($0)) }
        let report = build(facts(comments: .success(Capped(items: dates, capped: false))))
        #expect(report.cardSpeech(.issues)
            == "Issues, this week: 2 closed, last week 1. 3 opened, last week 0. 14 comments.")
    }

    @Test func pullRequestsSpeech() {
        let prs = [opened(waitHours: 3), opened(waitHours: 3)]
        let merged = (0..<5).map { _ in
            MergedPR(createdAt: now.addingTimeInterval(-3 * day), mergedAt: now.addingTimeInterval(-2 * day))
        }
        let report = build(facts(opened: .success(CountedList(total: 2, items: prs)), merged: .success(CountedList(total: 5, items: merged))), period: .quarter)
        #expect(report.cardSpeech(.pullRequests)
            == "Your pull requests, the last 90 days: 5 merged, previous 90 days 0. Median time to merge 1 day. Median first review 3 hours. Top reviewers: dana 2.")
    }
}
