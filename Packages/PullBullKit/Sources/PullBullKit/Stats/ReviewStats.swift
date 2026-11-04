import Foundation

/// One PR the viewer has reviewed, with what the Stats screen needs to date and time those reviews.
public struct ReviewedPR: Equatable, Sendable {
    public let repo: String
    public let author: String?
    public let requests: [ReviewRequestEvent]
    public let myReviews: [MyReview]

    public init(repo: String, author: String?, requests: [ReviewRequestEvent], myReviews: [MyReview]) {
        self.repo = repo
        self.author = author
        self.requests = requests
        self.myReviews = myReviews
    }
}

/// A review request on a PR. `reviewer` is nil when GitHub didn't say who was asked.
public struct ReviewRequestEvent: Equatable, Sendable {
    public let at: Date
    public let reviewer: Reviewer?

    public init(at: Date, reviewer: Reviewer?) {
        self.at = at
        self.reviewer = reviewer
    }
}

/// A review the viewer wrote. A pending one is unsent and doesn't count.
public struct MyReview: Equatable, Sendable {
    public let submittedAt: Date?
    public let pending: Bool

    public init(submittedAt: Date?, pending: Bool) {
        self.submittedAt = submittedAt
        self.pending = pending
    }
}

/// The viewer's reviews in a period: when they were submitted, and how long each answered request took.
public struct ReviewStats: Equatable, Sendable {
    public let reviewDates: [Date]
    public let turnarounds: [TimeInterval]

    public init(reviewDates: [Date], turnarounds: [TimeInterval]) {
        self.reviewDates = reviewDates
        self.turnarounds = turnarounds
    }

    /// Reviews submitted in `window` on PRs `me` didn't author. A review is a turnaround sample when it is
    /// the first answer to the latest request, at or before it, that names `me` or one of `myTeams`.
    /// A review nobody asked for, or a second one on the same request, is counted but not timed.
    public static func make(_ prs: [ReviewedPR], window: StatsWindow, me: String, myTeams: Set<String>) -> ReviewStats {
        let teams = Set(myTeams.map { $0.lowercased() })
        var dates: [Date] = []
        var turnarounds: [TimeInterval] = []
        for pr in prs where !isOwn(pr, me: me) {
            let sent = sentDates(pr)
            let asked = pr.requests
                .filter { names($0.reviewer, me: me, teams: teams) }
                .map(\.at).sorted()
            for review in sent where window.contains(review) {
                dates.append(review)
                guard let request = asked.last(where: { $0 <= review }) else { continue }
                let between = sent.contains { $0 > request && $0 < review }
                if !between { turnarounds.append(review.timeIntervalSince(request)) }
            }
        }
        return ReviewStats(reviewDates: dates.sorted(), turnarounds: turnarounds)
    }

    /// The first local day whose reviews are all loaded, or nil when no PR has a review in `window`.
    /// Contributions come newest PR first, each dated by its latest review, so a PR not loaded has its
    /// latest review on or before the earliest of the loaded ones: that day may be missing reviews.
    public static func loadedFrom(_ prs: [ReviewedPR], window: StatsWindow, me: String, calendar: Calendar) -> Date? {
        let newest = prs.filter { !isOwn($0, me: me) }
            .compactMap { sentDates($0).filter(window.contains).max() }
        guard let earliest = newest.min() else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: earliest))
    }

    private static func isOwn(_ pr: ReviewedPR, me: String) -> Bool {
        pr.author?.lowercased() == me.lowercased()
    }

    private static func sentDates(_ pr: ReviewedPR) -> [Date] {
        pr.myReviews.compactMap { $0.pending ? nil : $0.submittedAt }.sorted()
    }

    private static func names(_ reviewer: Reviewer?, me: String, teams: Set<String>) -> Bool {
        switch reviewer {
        case .user(let login): login.lowercased() == me.lowercased()
        case .team(let slug, _): teams.contains(slug.lowercased())
        case nil: false
        }
    }
}
