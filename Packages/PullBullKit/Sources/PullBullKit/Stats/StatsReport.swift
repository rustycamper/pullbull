import Foundation

/// Why one Stats source couldn't be loaded, in words fit for the footer.
public struct StatsFailure: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Everything fetched for one period, one result per source so a failed one hides only its own values.
/// The "Before" sources cover the comparison window.
public struct StatsFacts: Sendable {
    public var reviewed, reviewedBefore: Result<Capped<ReviewedPR>, StatsFailure>
    public var opened, openedBefore: Result<CountedList<OpenedPR>, StatsFailure>
    public var merged, mergedBefore: Result<CountedList<MergedPR>, StatsFailure>
    public var closed, closedBefore, issuesOpened, issuesOpenedBefore: Result<Int, StatsFailure>
    public var comments: Result<Capped<Date>, StatsFailure>

    public init(
        reviewed: Result<Capped<ReviewedPR>, StatsFailure>,
        reviewedBefore: Result<Capped<ReviewedPR>, StatsFailure>,
        opened: Result<CountedList<OpenedPR>, StatsFailure>,
        openedBefore: Result<CountedList<OpenedPR>, StatsFailure>,
        merged: Result<CountedList<MergedPR>, StatsFailure>,
        mergedBefore: Result<CountedList<MergedPR>, StatsFailure>,
        closed: Result<Int, StatsFailure>,
        closedBefore: Result<Int, StatsFailure>,
        issuesOpened: Result<Int, StatsFailure>,
        issuesOpenedBefore: Result<Int, StatsFailure>,
        comments: Result<Capped<Date>, StatsFailure>
    ) {
        self.reviewed = reviewed
        self.reviewedBefore = reviewedBefore
        self.opened = opened
        self.openedBefore = openedBefore
        self.merged = merged
        self.mergedBefore = mergedBefore
        self.closed = closed
        self.closedBefore = closedBefore
        self.issuesOpened = issuesOpened
        self.issuesOpenedBefore = issuesOpenedBefore
        self.comments = comments
    }
}

/// The previous period's figure beside a value: the period's name, "last week", and the figure, "5 h".
public struct StatComparison: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// One figure on a card. `text` is "–" when the value is unknown: missing beats wrong.
public struct StatValue: Equatable, Sendable {
    public let text: String
    /// The same figure for VoiceOver: "3 hours 10 minutes", or "not available".
    public let spoken: String
    /// The previous period's figure in its parts, for a column too narrow for one line; nil when either
    /// side is unknown.
    public let previous: StatComparison?
    /// The comparison for VoiceOver: "last week 5 hours".
    public let comparisonSpoken: String?
    public let hover: String?
    /// Whether a source cap cut into this figure.
    public let capped: Bool

    /// The previous period's figure on one line, "last week 5 h"; nil when either side is unknown.
    public var comparison: String? {
        previous.map { "\($0.label) \($0.value)" }
    }

    public init(
        text: String, spoken: String, previous: StatComparison? = nil, comparisonSpoken: String? = nil,
        hover: String? = nil, capped: Bool = false
    ) {
        self.text = text
        self.spoken = spoken
        self.previous = previous
        self.comparisonSpoken = comparisonSpoken
        self.hover = hover
        self.capped = capped
    }

    static let unknown = StatValue(text: "–", spoken: "not available")
    var isUnknown: Bool { text == "–" }
}

/// The three cards of the Stats screen.
public enum StatsCard: Sendable {
    case reviews, pullRequests, issues
}

/// What a period's Stats screen shows, worked out from fetched facts.
public struct StatsReport: Equatable, Sendable {
    public let period: StatsPeriod
    public let fetchedAt: Date
    public let reviews, turnaround, merged, timeToMerge, firstReview, issuesClosed, issuesOpened, comments: StatValue
    /// Reviews per day; nil when the reviewed source failed.
    public let bars: ReviewBars?
    /// nil when the opened source failed; empty when nobody reviewed yet.
    public let topReviewers: [TopReviewer]?
    public let anyCapped: Bool
    /// "· from latest 100", or "· from latest 500 comments" when only comments were capped.
    public let footerCapNote: String?
    public let failures: [String]
    public var isComplete: Bool { failures.isEmpty }

    private static let prCap = "From the latest 100 PRs"
    private static let commentCap = "From your latest 500 comments"

    public init(
        period: StatsPeriod, fetchedAt: Date,
        reviews: StatValue, turnaround: StatValue, merged: StatValue, timeToMerge: StatValue,
        firstReview: StatValue, issuesClosed: StatValue, issuesOpened: StatValue, comments: StatValue,
        bars: ReviewBars?, topReviewers: [TopReviewer]?, anyCapped: Bool, footerCapNote: String?, failures: [String]
    ) {
        self.period = period
        self.fetchedAt = fetchedAt
        self.reviews = reviews
        self.turnaround = turnaround
        self.merged = merged
        self.timeToMerge = timeToMerge
        self.firstReview = firstReview
        self.issuesClosed = issuesClosed
        self.issuesOpened = issuesOpened
        self.comments = comments
        self.bars = bars
        self.topReviewers = topReviewers
        self.anyCapped = anyCapped
        self.footerCapNote = footerCapNote
        self.failures = failures
    }

    public static func build(
        _ facts: StatsFacts, period: StatsPeriod, me: String, myTeams: Set<String>, now: Date, calendar: Calendar
    ) -> StatsReport {
        let window = period.window(now: now, calendar: calendar)
        let before = period.comparisonWindow(now: now, calendar: calendar)

        let current = (try? facts.reviewed.get()).map {
            (stats: ReviewStats.make($0.items, window: window, me: me, myTeams: myTeams), capped: $0.capped, prs: $0.items)
        }
        let previous = (try? facts.reviewedBefore.get()).map {
            (stats: ReviewStats.make($0.items, window: before, me: me, myTeams: myTeams), capped: $0.capped)
        }

        let reviews = count(current.map { Tally(n: $0.stats.reviewDates.count, capped: $0.capped) },
                            previous.map { Tally(n: $0.stats.reviewDates.count, capped: $0.capped) },
                            period: period, hover: current?.capped == true ? prCap : nil)

        let turnaround = duration(
            current.map { Median.of($0.stats.turnarounds) }.flatMap { $0 },
            previous.map { Median.of($0.stats.turnarounds) }.flatMap { $0 },
            period: period,
            hover: current.map { sampled in
                let text = sampled.stats.turnarounds.isEmpty
                    ? "No reviews you were asked for in this period"
                    : "Median of \(sampled.stats.turnarounds.count) \(sampled.stats.turnarounds.count == 1 ? "review" : "reviews") you were asked for"
                return sampled.capped ? "\(text). \(prCap)" : text
            }, capped: current?.capped == true)

        let mergedNow = try? facts.merged.get()
        let mergedBefore = try? facts.mergedBefore.get()
        let mergedValue = count(mergedNow.map { Tally(n: $0.total, capped: false) },
                                mergedBefore.map { Tally(n: $0.total, capped: false) }, period: period, hover: nil)
        let mergeTimes = mergedNow.map { MergeTimes.make($0.items) }
        let timeToMerge = duration(
            mergeTimes.flatMap(Median.of), mergedBefore.map { MergeTimes.make($0.items) }.flatMap(Median.of),
            period: period,
            hover: mergedNow.flatMap { list in
                guard !list.items.isEmpty else { return nil }
                let text = "Median of \(list.items.count) merged \(list.items.count == 1 ? "PR" : "PRs")"
                return list.capped ? "\(text). \(prCap)" : text
            }, capped: mergedNow?.capped == true)

        let openedNow = try? facts.opened.get()
        let firstNow = openedNow.map { FirstReviewStats.make($0.items, me: me) }
        let firstBefore = (try? facts.openedBefore.get()).map { FirstReviewStats.make($0.items, me: me) }
        let firstReview = duration(
            firstNow.flatMap { Median.of($0.waits) }, firstBefore.flatMap { Median.of($0.waits) },
            period: period,
            hover: firstNow.map { first in
                var parts: [String] = []
                if !first.waits.isEmpty { parts.append("Median of \(first.waits.count) \(first.waits.count == 1 ? "PR" : "PRs").") }
                if first.stillWaiting > 0 {
                    parts.append(first.stillWaiting == 1
                        ? "1 of your PRs opened in this period still waits for a first review."
                        : "\(first.stillWaiting) of your PRs opened in this period still wait for a first review.")
                }
                if openedNow?.capped == true { parts.append(prCap) }
                return parts.isEmpty ? nil : parts.joined(separator: " ")
            }.flatMap { $0 }, capped: openedNow?.capped == true)

        let commentsNow = try? facts.comments.get()
        let comments = count(commentsNow.map { Tally(n: $0.items.count, capped: $0.capped) }, nil, period: period,
                             hover: commentsNow?.capped == true ? commentCap : nil)

        let prSourcesCapped = current?.capped == true || mergedNow?.capped == true || openedNow?.capped == true
        let commentsCapped = commentsNow?.capped == true
        let note: String? = prSourcesCapped ? "· from latest 100" : commentsCapped ? "· from latest 500 comments" : nil

        var bars: ReviewBars?
        if let current {
            let from = current.capped
                ? ReviewStats.loadedFrom(current.prs, calendar: calendar) : nil
            bars = ReviewBars.make(
                reviewDates: current.stats.reviewDates, window: window, loadedFrom: from, capped: current.capped,
                calendar: calendar)
        }

        return StatsReport(
            period: period, fetchedAt: now,
            reviews: reviews, turnaround: turnaround, merged: mergedValue, timeToMerge: timeToMerge,
            firstReview: firstReview,
            issuesClosed: exact(facts.closed, facts.closedBefore, period: period),
            issuesOpened: exact(facts.issuesOpened, facts.issuesOpenedBefore, period: period),
            comments: comments, bars: bars,
            topReviewers: openedNow.map { TopReviewers.make($0.items, me: me) },
            anyCapped: prSourcesCapped || commentsCapped, footerCapNote: note,
            failures: failureMessages(facts))
    }

    /// One sentence per card for VoiceOver, since the card's parts are read as one element.
    public func cardSpeech(_ card: StatsCard) -> String {
        let span = period == .quarter ? "the last 90 days" : period.title.lowercased()
        switch card {
        case .reviews:
            return "\(card.title), \(span): \(counted(reviews, noun: "review", plural: "reviews")). "
                + "\(median("Median turnaround", turnaround))."
        case .pullRequests:
            var text = "\(card.title), \(span): \(counted(merged, noun: "merged", plural: "merged")). "
                + "\(median("Median time to merge", timeToMerge)). \(median("Median first review", firstReview))."
            if let top = topReviewers, !top.isEmpty {
                text += " Top reviewers: " + top.map { "\($0.login) \($0.prCount)" }.joined(separator: ", ") + "."
            }
            return text
        case .issues:
            return "\(card.title), \(span): \(counted(issuesClosed, noun: "closed", plural: "closed")). "
                + "\(counted(issuesOpened, noun: "opened", plural: "opened")). "
                + "\(counted(comments, noun: "comment", plural: "comments"))."
        }
    }

    /// The card's value hovers for VoiceOver, which can't hover: their sentences joined by ". ", a
    /// sentence that ends with its own full stop followed by a space only, and a sentence two hovers
    /// share (the cap note) said once. Nil when the card has none.
    public func cardHint(_ card: StatsCard) -> String? {
        let values: [StatValue] = switch card {
        case .reviews: [reviews, turnaround]
        case .pullRequests: [merged, timeToMerge, firstReview]
        case .issues: [issuesClosed, issuesOpened, comments]
        }
        var seen = Set<String>()
        let sentences = values.compactMap(\.hover)
            .flatMap { $0.components(separatedBy: ". ") }
            .filter { !$0.isEmpty && seen.insert($0.hasSuffix(".") ? String($0.dropLast()) : $0).inserted }
        guard var text = sentences.first else { return nil }
        for sentence in sentences.dropFirst() {
            text += (text.hasSuffix(".") ? " " : ". ") + sentence
        }
        return text
    }

    private func counted(_ value: StatValue, noun: String, plural: String) -> String {
        guard !value.isUnknown else { return "\(plural) not available" }
        let exact = value.spoken == "1"
        var text = "\(value.spoken) \(exact ? noun : plural)"
        if let comparison = value.comparisonSpoken { text += ", \(comparison)" }
        return text
    }

    private func median(_ label: String, _ value: StatValue) -> String {
        guard !value.isUnknown else { return "\(label) not available" }
        var text = "\(label) \(value.spoken)"
        if let comparison = value.comparisonSpoken { text += ", \(comparison)" }
        return text
    }

    // MARK: - Building values

    private struct Tally {
        let n: Int
        let capped: Bool
        var text: String { capped ? "\(n)+" : "\(n)" }
        var spoken: String { capped ? "\(n) or more" : "\(n)" }
    }

    private static func count(_ now: Tally?, _ before: Tally?, period: StatsPeriod, hover: String?) -> StatValue {
        guard let now else { return .unknown }
        return StatValue(
            text: now.text, spoken: now.spoken,
            previous: before.map { StatComparison(label: period.comparisonName, value: $0.text) },
            comparisonSpoken: before.map { StatsComparison.text($0.spoken, period: period) },
            hover: hover, capped: now.capped)
    }

    private static func exact(
        _ now: Result<Int, StatsFailure>, _ before: Result<Int, StatsFailure>, period: StatsPeriod
    ) -> StatValue {
        count((try? now.get()).map { Tally(n: $0, capped: false) },
              (try? before.get()).map { Tally(n: $0, capped: false) }, period: period, hover: nil)
    }

    private static func duration(
        _ now: TimeInterval?, _ before: TimeInterval?, period: StatsPeriod, hover: String?, capped: Bool
    ) -> StatValue {
        guard let now else { return StatValue(text: "–", spoken: "not available", hover: hover, capped: capped) }
        return StatValue(
            text: StatDuration.short(now), spoken: StatDuration.spoken(now),
            previous: before.map { StatComparison(label: period.comparisonName, value: StatDuration.short($0)) },
            comparisonSpoken: before.map { StatsComparison.text(StatDuration.spoken($0), period: period) },
            hover: hover, capped: capped)
    }

    /// The message of each failed source once, in the order the facts are declared.
    private static func failureMessages(_ facts: StatsFacts) -> [String] {
        let results: [Result<Void, StatsFailure>] = [
            facts.reviewed.map { _ in }, facts.reviewedBefore.map { _ in },
            facts.opened.map { _ in }, facts.openedBefore.map { _ in },
            facts.merged.map { _ in }, facts.mergedBefore.map { _ in },
            facts.closed.map { _ in }, facts.closedBefore.map { _ in },
            facts.issuesOpened.map { _ in }, facts.issuesOpenedBefore.map { _ in },
            facts.comments.map { _ in },
        ]
        var seen = Set<String>()
        return results.compactMap { result in
            guard case .failure(let failure) = result, seen.insert(failure.message).inserted else { return nil }
            return failure.message
        }
    }
}
