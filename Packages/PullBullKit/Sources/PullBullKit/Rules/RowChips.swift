import Foundation

/// What a full PR row says about reviews, in two tiers. Only "act on this" states get a tinted capsule;
/// everything informational is a glyph and text in the meta line, so a healthy list stays calm.
public struct RowChips: Equatable, Sendable {
    /// A capsule: the PR needs its author to do something.
    public enum Action: Equatable, Sendable {
        case readyToMerge
        /// The logins whose latest review requests changes.
        case changesRequested(by: [String])
    }

    /// Glyph-and-text metadata in the meta line.
    public enum Info: Equatable, Sendable {
        case approvals(Int)
        /// Who the review waits on and for how long (`ReviewWait`); on every tab, before Conflicts.
        case reviewWait(ReviewWait)
        /// A Review row I approved that doesn't count toward the tab.
        case youApprovedNotCounted
        case reRequested
        case newCommits
        /// Requested from a team of mine: `org/slug`, or the bare slug when the repo has no owner.
        case viaTeam(String)
        /// GitHub reports merge conflicts with the base branch; shown on every tab and in search, last in the row.
        case conflicts

        /// The SF Symbol drawn before the text.
        public var symbol: String {
            switch self {
            case .approvals, .youApprovedNotCounted: "checkmark"
            case .reviewWait: "clock"
            case .reRequested: "arrow.uturn.left"
            case .newCommits: "arrow.triangle.2.circlepath"
            case .viaTeam: "person.2"
            case .conflicts: "exclamationmark.triangle"
            }
        }

        /// The meta-line text: a bare number for counts.
        public var text: String {
            switch self {
            case .approvals(let n): "\(n)"
            case .reviewWait(let wait): wait.text
            case .youApprovedNotCounted: "You approved · not counted"
            case .reRequested: "Re-requested"
            case .newCommits: "New commits"
            case .viaTeam(let team): "via @\(team)"
            case .conflicts: "Conflicts"
            }
        }

        /// The full wording, for VoiceOver and tooltips.
        public var label: String {
            switch self {
            case .approvals(let n): n == 1 ? "1 approval" : "\(n) approvals"
            case .reviewWait(let wait): wait.label
            case .newCommits: "New commits since your review"
            case .viaTeam(let team): "Requested via @\(team)"
            case .conflicts: "Merge conflicts"
            default: text
            }
        }

        /// A warning: its glyph is amber, its text stays gray.
        public var isWarning: Bool { self == .conflicts }

        /// A count sits beside the comment count; other info follows the age after a `·`.
        public var isCount: Bool {
            if case .approvals = self { return true }
            return false
        }

        public var isReviewWait: Bool {
            if case .reviewWait = self { return true }
            return false
        }
    }

    public let action: Action?
    public let info: [Info]

    public init(action: Action?, info: [Info]) {
        self.action = action
        self.info = info
    }

    /// `me` and `myTeams` decide "You" and the Review tab's short wait; `now` measures it.
    public init(row: Row, tab: PRTab, me: String, myTeams: Set<String>, now: Date) {
        let pr = row.pr
        let wait = ReviewWait.make(for: pr, me: me, myTeams: myTeams, reviewLayout: tab == .review, now: now)
            .map(Info.reviewWait)
        let approvals = pr.latestReviews.filter { $0.state == .approved }.count
        let changesRequestedBy = pr.latestReviews.filter { $0.state == .changesRequested }.map(\.author)

        switch tab {
        case .mine:
            let action = Self.action(for: pr, changesRequestedBy: changesRequestedBy)
            var info: [Info] = []
            if approvals > 0 { info.append(.approvals(approvals)) }
            if let wait { info.append(wait) }
            if pr.hasConflicts { info.append(.conflicts) }
            self.init(action: action, info: info)
        case .team:
            var info: [Info] = []
            if approvals > 0 { info.append(.approvals(approvals)) }
            if let wait { info.append(wait) }
            if pr.hasConflicts { info.append(.conflicts) }
            self.init(action: nil, info: info)
        case .review:
            let reason: Info? = if row.dimmed {
                .youApprovedNotCounted
            } else {
                switch row.reviewReason {
                case .reRequested: .reRequested
                case .newCommitsSinceReview: .newCommits
                case .teamRequested(let slug):
                    .viaTeam(ReviewWait.teamPath(slug, repo: pr.key.repo))
                case .requested, nil: nil
                }
            }
            var info = reason.map { [$0] } ?? []
            if let wait { info.append(wait) }
            if pr.hasConflicts { info.append(.conflicts) }
            self.init(action: nil, info: info)
        }
    }

    /// The capsule for a PR's author: ready to merge, else changes requested.
    private static func action(for pr: PullRequest, changesRequestedBy: [String]) -> Action? {
        if ReviewRules.isReadyToMerge(pr) { .readyToMerge }
        else if !changesRequestedBy.isEmpty { .changesRequested(by: changesRequestedBy) }
        else { nil }
    }
}
