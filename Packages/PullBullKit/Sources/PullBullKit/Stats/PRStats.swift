import Foundation

/// A PR the viewer opened, with what Stats needs to time its first review and name its reviewers.
public struct OpenedPR: Equatable, Sendable {
    public let createdAt: Date
    public let isDraft: Bool
    public let isOpen: Bool
    /// When it was last marked ready for review; nil if it never was a draft.
    public let readyAt: Date?
    public let reviews: [OpenedPRReview]

    public init(createdAt: Date, isDraft: Bool, isOpen: Bool, readyAt: Date?, reviews: [OpenedPRReview]) {
        self.createdAt = createdAt
        self.isDraft = isDraft
        self.isOpen = isOpen
        self.readyAt = readyAt
        self.reviews = reviews
    }
}

/// A review on one of the viewer's PRs. A pending one is unsent and doesn't count.
public struct OpenedPRReview: Equatable, Sendable {
    public let author: String
    public let avatarURL: URL?
    public let byBot: Bool
    public let submittedAt: Date?
    public let pending: Bool

    public init(author: String, avatarURL: URL?, byBot: Bool, submittedAt: Date?, pending: Bool) {
        self.author = author
        self.avatarURL = avatarURL
        self.byBot = byBot
        self.submittedAt = submittedAt
        self.pending = pending
    }
}

/// A PR the viewer opened that was merged.
public struct MergedPR: Equatable, Sendable {
    public let createdAt: Date
    public let mergedAt: Date

    public init(createdAt: Date, mergedAt: Date) {
        self.createdAt = createdAt
        self.mergedAt = mergedAt
    }
}

/// How long the viewer's PRs waited for a first review, and how many still wait.
public struct FirstReviewStats: Equatable, Sendable {
    public let waits: [TimeInterval]
    public let stillWaiting: Int

    public init(waits: [TimeInterval], stillWaiting: Int) {
        self.waits = waits
        self.stillWaiting = stillWaiting
    }

    /// The wait runs from ready (or creation) to the earliest sent review by a person other than `me`.
    /// A review from before that start is no sample and the PR isn't waiting. A draft is neither, and
    /// a closed or merged PR without a review is neither.
    public static func make(_ prs: [OpenedPR], me: String) -> FirstReviewStats {
        var waits: [TimeInterval] = []
        var waiting = 0
        for pr in prs where !pr.isDraft {
            let start = pr.readyAt ?? pr.createdAt
            if let first = sentReviews(pr, me: me).map(\.date).min() {
                if first >= start { waits.append(first.timeIntervalSince(start)) }
            } else if pr.isOpen {
                waiting += 1
            }
        }
        return FirstReviewStats(waits: waits, stillWaiting: waiting)
    }

    private static func sentReviews(_ pr: OpenedPR, me: String) -> [(review: OpenedPRReview, date: Date)] {
        pr.reviews.compactMap { review in
            guard !review.pending, !review.byBot, review.author.lowercased() != me.lowercased(),
                let date = review.submittedAt else { return nil }
            return (review, date)
        }
    }
}

/// A person who reviewed the viewer's PRs, and on how many of them.
public struct TopReviewer: Equatable, Sendable {
    public let login: String
    public let avatarURL: URL?
    public let prCount: Int

    public init(login: String, avatarURL: URL?, prCount: Int) {
        self.login = login
        self.avatarURL = avatarURL
        self.prCount = prCount
    }
}

public enum TopReviewers {
    /// The people who reviewed the most of the viewer's PRs, each PR counted once per person; bots and
    /// `me` are left out. Ties go by login, ignoring case.
    public static func make(_ prs: [OpenedPR], me: String, limit: Int = 3) -> [TopReviewer] {
        var counts: [String: (login: String, avatar: URL?, count: Int)] = [:]
        for pr in prs {
            var seen = Set<String>()
            for review in pr.reviews where !review.pending && !review.byBot {
                let key = review.author.lowercased()
                guard key != me.lowercased() else { continue }
                var entry = counts[key] ?? (review.author, nil, 0)
                if entry.avatar == nil { entry.avatar = review.avatarURL }
                if seen.insert(key).inserted { entry.count += 1 }
                counts[key] = entry
            }
        }
        let sorted = counts.values.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.login.lowercased() < $1.login.lowercased()
        }
        return sorted.prefix(max(limit, 0)).map { TopReviewer(login: $0.login, avatarURL: $0.avatar, prCount: $0.count) }
    }
}

public enum MergeTimes {
    /// Creation to merge for each PR.
    public static func make(_ prs: [MergedPR]) -> [TimeInterval] {
        prs.map { $0.mergedAt.timeIntervalSince($0.createdAt) }
    }
}
