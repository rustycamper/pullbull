import Foundation

/// github.com pages the popover links to.
public enum GitHubLinks {
    public static let pulls = URL(string: "https://github.com/pulls")!
    public static let issuesAssigned = URL(string: "https://github.com/issues/assigned")!
    public static let issues = URL(string: "https://github.com/issues")!

    /// A pull request's page, for one whose list data (and URL) is not at hand.
    public static func pullRequest(_ key: PRKey) -> URL {
        page(key, kind: "pull")
    }

    /// An issue's page, for one whose list data (and URL) is not at hand.
    public static func issue(_ key: PRKey) -> URL {
        page(key, kind: "issues")
    }

    private static func page(_ key: PRKey, kind: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(key.repo)/\(kind)/\(key.number)"
        return components.url ?? issues
    }

    /// One repo's pull requests page.
    public static func repoPulls(_ repo: String) -> URL {
        repoPage(repo, kind: "pulls")
    }

    /// One repo's issues page.
    public static func repoIssues(_ repo: String) -> URL {
        repoPage(repo, kind: "issues")
    }

    private static func repoPage(_ repo: String, kind: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(repo)/\(kind)"
        return components.url ?? issues
    }

    /// A Projects board: `/orgs/<org>/projects/<n>` for an org's, `/users/<login>/projects/<n>` for a
    /// personal one.
    public static func board(_ board: BoardRef) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        let kind = board.owner.isUser ? "users" : "orgs"
        components.path = "/\(kind)/\(board.owner.login)/projects/\(board.number)"
        return components.url ?? issues
    }

    /// The board with the item's side pane open when its id is known, else the board.
    public static func boardItem(_ board: BoardRef, itemId: Int?) -> URL {
        let url = self.board(board)
        guard let itemId,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = [URLQueryItem(name: "pane", value: "issue"), URLQueryItem(name: "itemId", value: String(itemId))]
        return components.url ?? url
    }

    /// The board link's name while the board's title is unknown or too long for the footer.
    public static let boardShortTitle = "Board"

    /// The footer link for the tab on screen. A focus links to its repo's PRs or issues, except on Board.
    /// Without one, Review links to review requests, Mine to github.com/pulls, Team to the org's open PRs;
    /// Assigned and Created to a search for the org's open issues assigned to or opened by the user, or
    /// without an org to the assigned or all-issues page; Board to the board when one is chosen. Each is
    /// named short enough to fit beside the refresh status, never by its long URL; the board by its title,
    /// or `boardShortTitle` while the title is unknown (the board can't be read). A focus is named as
    /// `RepoFocus.displayName(among: choices, org:)` names it.
    public static func footer(
        mode: PopoverMode, prTab: PRTab = .mine, issueTab: IssueTab, org: String?, board: BoardRef?,
        boardTitle: String?, focus: RepoFocus? = nil, choices: [RepoChoice] = []
    ) -> (title: String, url: URL) {
        let focusName = focus?.displayName(among: choices, org: org ?? "")
        switch (mode, issueTab) {
        case (.pullRequests, _):
            if let focus, let focusName { return ("\(focusName) PRs", repoPulls(focus.repo)) }
            switch prTab {
            case .review: return ("Review requests on GitHub", pullsReviewRequested)
            case .mine: return ("PRs on GitHub", pulls)
            case .team:
                // Team lists only the other members' PRs, but naming every member doesn't fit a query.
                guard let org else { return ("PRs on GitHub", pulls) }
                return ("\(org) PRs on GitHub", searching(pulls, for: "is:pr is:open org:\(org)"))
            }
        case (.issues, .assigned):
            if let focus, let focusName { return ("\(focusName) issues", repoIssues(focus.repo)) }
            guard let org else { return ("Assigned on GitHub", issuesAssigned) }
            return ("Assigned on GitHub", issueSearch("is:issue is:open assignee:@me org:\(org)"))
        case (.issues, .created):
            if let focus, let focusName { return ("\(focusName) issues", repoIssues(focus.repo)) }
            guard let org else { return ("Issues on GitHub", issues) }
            return ("Created on GitHub", issueSearch("is:issue is:open author:@me org:\(org)"))
        case (.issues, .board):
            guard let board else { return ("Issues on GitHub", issues) }
            let url = self.board(board)
            let title = boardTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (title.isEmpty ? boardShortTitle : title, url)
        }
    }

    static let pullsReviewRequested = URL(string: "https://github.com/pulls/review-requested")!
    static let search = URL(string: "https://github.com/search")!

    /// github.com/search for `query` among issues. The newer github.com/issues dashboard has no
    /// documented `q` link; the classic github.com/pulls dashboard honours one.
    static func issueSearch(_ query: String) -> URL {
        searching(search, for: query, type: "issues")
    }

    /// What a `q` value holds unescaped: RFC 3986's unreserved characters. Everything else is
    /// percent-encoded: spaces, `:`, `@`, `"`, `<`, `>`, non-ASCII as UTF-8, and `+`, which GitHub would
    /// read as a space.
    private static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `page` with `?q=<query>`, then `&type=<type>` when given.
    static func searching(_ page: URL, for query: String, type: String? = nil) -> URL {
        guard var components = URLComponents(url: page, resolvingAgainstBaseURL: false),
              let value = query.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return page }
        components.percentEncodedQuery = "q=\(value)" + (type.map { "&type=\($0)" } ?? "")
        return components.url ?? page
    }
}
