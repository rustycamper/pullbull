import Foundation

/// One PR the viewer has reviewed, with what the Stats screen needs to date and time those reviews.
public struct ReviewedPR: Equatable, Sendable {
    public let repo: String
    public let author: String?
    /// When the PR last changed; the reviewed search is sorted by it. Nil when GitHub didn't say.
    public let updatedAt: Date?
    public let requests: [ReviewRequestEvent]
    public let myReviews: [MyReview]

    public init(
        repo: String, author: String?, updatedAt: Date?, requests: [ReviewRequestEvent], myReviews: [MyReview]
    ) {
        self.repo = repo
        self.author = author
        self.updatedAt = updatedAt
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

    /// The first local day whose reviews are all loaded when a cap cut in, or nil when nothing was loaded
    /// (no PR with an `updatedAt`). The search returns PRs most recently updated first, and a review
    /// updates its PR, so a PR not loaded has every review at or before the oldest loaded `updatedAt`:
    /// every review from then on is loaded. That is the first day starting at or after it.
    public static func loadedFrom(_ prs: [ReviewedPR], calendar: Calendar) -> Date? {
        guard let oldest = prs.compactMap(\.updatedAt).min() else { return nil }
        let day = calendar.startOfDay(for: oldest)
        if day == oldest { return day }
        return calendar.date(byAdding: .day, value: 1, to: day)
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
