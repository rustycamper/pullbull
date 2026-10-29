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
        case noReviews
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
            case .noReviews: "clock"
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
            case .noReviews: "No reviews"
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
            case .noReviews: "No reviews yet"
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
    }

    public let action: Action?
    public let info: [Info]

    public init(action: Action?, info: [Info]) {
        self.action = action
        self.info = info
    }

    public init(row: Row, tab: PRTab) {
        let pr = row.pr
        let approvals = pr.latestReviews.filter { $0.state == .approved }.count
        let changesRequestedBy = pr.latestReviews.filter { $0.state == .changesRequested }.map(\.author)

        switch tab {
        case .mine:
            let action: Action? =
                if ReviewRules.isReadyToMerge(pr) { .readyToMerge }
                else if !changesRequestedBy.isEmpty { .changesRequested(by: changesRequestedBy) }
                else { nil }
            var info: [Info] = []
            if approvals > 0 { info.append(.approvals(approvals)) }
            if approvals == 0 && changesRequestedBy.isEmpty { info.append(.noReviews) }
            if pr.hasConflicts { info.append(.conflicts) }
            self.init(action: action, info: info)
        case .team:
            var info: [Info] = []
            if approvals > 0 { info.append(.approvals(approvals)) }
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
                    .viaTeam((pr.key.repo.split(separator: "/").first.map { "\($0)/" } ?? "") + slug)
                case .requested, nil: nil
                }
            }
            var info = reason.map { [$0] } ?? []
            if pr.hasConflicts { info.append(.conflicts) }
            self.init(action: nil, info: info)
        }
    }

    /// A search result's review state: only what holds whichever tab the PR sits on. Changes requested and
    /// conflicts on any open PR, ready to merge on the viewer's own; no counts and none of Review's reasons,
    /// which the role suffix stands in for. An ended PR has none.
    public init(searchResult pr: PullRequest, viewer: String) {
        guard pr.state == .open else {
            self.init(action: nil, info: [])
            return
        }
        let changesRequestedBy = pr.latestReviews.filter { $0.state == .changesRequested }.map(\.author)
        let own = pr.author.caseInsensitiveCompare(viewer) == .orderedSame
        let action: Action? =
            if own && ReviewRules.isReadyToMerge(pr) { .readyToMerge }
            else if !changesRequestedBy.isEmpty { .changesRequested(by: changesRequestedBy) }
            else { nil }
        self.init(action: action, info: pr.hasConflicts ? [.conflicts] : [])
    }
}
