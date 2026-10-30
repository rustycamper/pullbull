import Foundation

/// ⇧⌘↩ and the row menu's files item: a PR's Files changed page, or on a PR with new commits since my
/// review, only the changes from the commit I reviewed to the head. A force-pushed reviewed commit can
/// land on GitHub's error page; that is accepted.
public struct FilesLink: Equatable, Sendable {
    public let url: URL
    /// Whether `url` compares my reviewed commit with the head.
    public let sinceReview: Bool

    public var menuTitle: String { sinceReview ? "Open Changes Since My Review" : "Open Files Changed" }

    /// `…/pull/N/files`, for a PR whose list data (and review) is not at hand.
    public static func plain(_ key: PRKey) -> FilesLink {
        FilesLink(url: OpenTargets.pullPage(key, "files"), sinceReview: false)
    }

    /// `…/pull/N/files/<reviewed>..<head>` when the PR needs my review for new commits and both oids are
    /// known; `…/pull/N/files` otherwise.
    public static func target(for pr: PullRequest, me: String, myTeams: Set<String>) -> FilesLink {
        let files = plain(pr.key).url
        guard ReviewRules.status(of: pr, me: me, myTeams: myTeams).reviewReason == .newCommitsSinceReview,
              let head = pr.headCommitOid, let reviewed = ReviewRules.myReview(pr, me: me)?.commitOid,
              head != reviewed
        else { return FilesLink(url: files, sinceReview: false) }
        return FilesLink(url: files.appendingPathComponent("\(reviewed)..\(head)"), sinceReview: true)
    }
}

/// ⌃⌘C and the row menu's Copy Checkout Command.
public enum CheckoutCommand {
    public static func text(for key: PRKey) -> String {
        "gh pr checkout \(key.number) -R \(key.repo)"
    }
}

/// Open Failing Check: the first failed check's page, else the PR's Checks tab.
public enum FailingCheck {
    /// The first `.failure` check with a URL; `…/pull/N/checks` when none has one.
    public static func url(in checks: [Check], key: PRKey) -> URL {
        checks.first { $0.state == .failure && $0.url != nil }?.url ?? OpenTargets.pullPage(key, "checks")
    }

    /// Whether any of `checks` failed, which shows the detail's Open Failing Check.
    public static func hasFailure(_ checks: [Check]) -> Bool {
        checks.contains { $0.state == .failure }
    }
}

enum OpenTargets {
    /// A tab of the PR's page: `…/pull/N/<tab>`.
    static func pullPage(_ key: PRKey, _ tab: String) -> URL {
        GitHubLinks.pullRequest(key).appendingPathComponent(tab)
    }
}
