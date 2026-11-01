import Foundation

/// How long an open PR's review has waited, and on whom: "@georgi 3d", "@acme/ios +1 4d",
/// "No reviewer 5d", or on the Review tab just "2d". An unknown time shows no age, never a guessed one.
public struct ReviewWait: Equatable, Sendable {
    /// "@georgi", "@georgi +1", "@acme/ios", "You", "No reviewer"; nil in the Review tab's short form.
    public let who: String?
    /// Short age ("3d"); nil when unknown.
    public let age: String?
    /// Hover and VoiceOver wording.
    public let label: String

    /// `who` and `age` joined by a space.
    public var text: String { [who, age].compactMap { $0 }.joined(separator: " ") }

    /// What the row shows, or nil: only open, non-draft PRs that are waiting on a review.
    /// `reviewLayout`: the row is drawn with Review-tab chips; the short form needs a pending request
    /// to `me` or one of `myTeams` as well.
    public static func make(
        for pr: PullRequest, me: String, myTeams: Set<String>, reviewLayout: Bool, now: Date
    ) -> ReviewWait? {
        guard pr.state == .open, !pr.isDraft else { return nil }
        let requests = pr.reviewRequests.map { (reviewer: $0, at: pr.reviewRequestTimes[$0.key]) }
        let name = { (reviewer: Reviewer) in displayName(reviewer, me: me, repo: pr.key.repo) }

        if reviewLayout {
            let teams = Set(myTeams.map { $0.lowercased() })
            let own = requests.first { if case .user(let login) = $0.reviewer { login.lowercased() == me.lowercased() } else { false } }
            let teamRequests = requests.filter {
                if case .team(let slug, _) = $0.reviewer { teams.contains(slug.lowercased()) } else { false }
            }
            if own != nil || !teamRequests.isEmpty {
                let chosen = own.map { [$0] } ?? teamRequests
                guard let oldest = oldest(chosen) else { return nil }
                let from = own != nil ? "you" : name(oldest.reviewer)
                return ReviewWait(
                    who: nil, age: RelativeAge.short(from: oldest.at, to: now),
                    label: "Requested from \(from) \(RelativeAge.spoken(from: oldest.at, to: now)) ago")
            }
        }

        if let first = requests.first {
            let more = requests.count > 1 ? " +\(requests.count - 1)" : ""
            guard let oldest = oldest(requests) else {
                let names = requests.map { name($0.reviewer) }.joined(separator: ", ")
                return ReviewWait(who: name(first.reviewer) + more, age: nil, label: "Waiting on review: \(names)")
            }
            let byAge = requests.compactMap { r in r.at.map { (r.reviewer, $0) } }
                .enumerated().sorted { ($0.element.1, $0.offset) < ($1.element.1, $1.offset) }
                .map { "\(name($0.element.0)) \(RelativeAge.spoken(from: $0.element.1, to: now))" }
            return ReviewWait(
                who: name(oldest.reviewer) + more, age: RelativeAge.short(from: oldest.at, to: now),
                label: "Waiting on review: " + byAge.joined(separator: ", "))
        }

        // A bot's review (Copilot, a review app) lands on nearly every PR; it isn't someone reviewing.
        let reviewed = pr.latestReviews.contains { $0.state != .pending && $0.submittedAt != nil && $0.byBot != true }
        guard !reviewed else { return nil }
        let since = pr.readyForReviewAt ?? pr.createdAt
        return ReviewWait(
            who: "No reviewer", age: RelativeAge.short(from: since, to: now),
            label: "No reviewer requested, ready for \(RelativeAge.spoken(from: since, to: now))")
    }

    /// `@org/slug` for a team, or the bare slug when the repo has no owner.
    static func teamPath(_ slug: String, repo: String) -> String {
        (repo.split(separator: "/").first.map { "\($0)/" } ?? "") + slug
    }

    private static func displayName(_ reviewer: Reviewer, me: String, repo: String) -> String {
        switch reviewer {
        case .user(let login): login.lowercased() == me.lowercased() ? "You" : "@\(login)"
        case .team(let slug, _): "@" + teamPath(slug, repo: repo)
        }
    }

    /// The earliest request, first in GitHub's order on a tie; nil when any time is unknown.
    private static func oldest(_ requests: [(reviewer: Reviewer, at: Date?)]) -> (reviewer: Reviewer, at: Date)? {
        var best: (reviewer: Reviewer, at: Date)?
        for request in requests {
            guard let at = request.at else { return nil }
            if best == nil || at < best!.at { best = (request.reviewer, at) }
        }
        return best
    }
}
