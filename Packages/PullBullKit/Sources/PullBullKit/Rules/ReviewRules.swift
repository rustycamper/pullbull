import Foundation

/// Why a PR needs my review.
public enum ReviewReason: Equatable, Sendable {
    /// Requested from me directly, and I haven't reviewed it yet.
    case requested
    /// Requested from me directly again after I reviewed it.
    case reRequested
    /// The head moved past the commit I reviewed.
    case newCommitsSinceReview
    /// Requested from a team of mine (its slug), and I haven't reviewed it yet.
    case teamRequested(String)
}

public enum ReviewStatus: Equatable, Sendable {
    case needsReview(ReviewReason), approvedByMe, reviewedByMe, notRequested

    /// Why the PR needs my review; nil when it doesn't.
    public var reviewReason: ReviewReason? {
        if case .needsReview(let reason) = self { return reason }
        return nil
    }
}

public enum ReviewRules {
    public static func status(of pr: PullRequest, me: String, myTeams: Set<String>) -> ReviewStatus {
        if same(pr.author, me) { return .notRequested }

        // Unsubmitted reviews (pending drafts, or no submission date) are not "my review".
        let mine = pr.latestReviews.first {
            same($0.author, me) && $0.state != .pending && $0.submittedAt != nil
        }

        let directlyRequested = pr.reviewRequests.contains {
            if case .user(let login) = $0 { return same(login, me) }
            return false
        }
        if directlyRequested { return .needsReview(mine == nil ? .requested : .reRequested) }

        guard let mine, let reviewedAt = mine.submittedAt else {
            let teams = Set(myTeams.map { $0.lowercased() })
            let teamSlug = pr.reviewRequests.lazy.compactMap { request -> String? in
                if case .team(let slug) = request, teams.contains(slug.lowercased()) { return slug }
                return nil
            }.first
            return teamSlug.map { .needsReview(.teamRequested($0)) } ?? .notRequested
        }

        // New commits since my review: the reviewed commit is no longer the head. Pushed time isn't
        // available, so without oids the head's commit date is the fallback.
        if let head = pr.headCommitOid, let reviewed = mine.commitOid {
            if head != reviewed { return .needsReview(.newCommitsSinceReview) }
        } else if let head = pr.headCommitDate, head > reviewedAt {
            return .needsReview(.newCommitsSinceReview)
        }
        return mine.state == .approved ? .approvedByMe : .reviewedByMe
    }

    /// An open, non-draft PR without merge conflicts, with at least one approval, no outstanding change
    /// requests and checks that passed, were all skipped or don't exist. PullBull doesn't fetch branch
    /// protection, so this can't know a required review count: one approval stands in for "reviewed",
    /// and a repo with no checks has nothing to wait for. Approvals count as GitHub lists them, stale or
    /// not. An UNKNOWN mergeability (GitHub still computing) doesn't hold it back.
    public static func isReadyToMerge(_ pr: PullRequest) -> Bool {
        guard pr.state == .open, !pr.isDraft, !pr.hasConflicts else { return false }
        guard [.success, .skipped, .none].contains(pr.ci) else { return false }
        let states = pr.latestReviews.map(\.state)
        return states.contains(.approved) && !states.contains(.changesRequested)
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        a.caseInsensitiveCompare(b) == .orderedSame
    }
}
