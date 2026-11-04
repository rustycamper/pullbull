import Foundation

/// Items from a source with a cap, and whether GitHub had more than the cap let through.
public struct Capped<T: Sendable & Equatable>: Sendable, Equatable {
    public let items: [T]
    public let capped: Bool

    public init(items: [T], capped: Bool) {
        self.items = items
        self.capped = capped
    }
}

/// Items from a search with the search's own total. `capped` when the total is more than the items.
public struct CountedList<T: Sendable & Equatable>: Sendable, Equatable {
    public let total: Int
    public let items: [T]
    public let capped: Bool

    public init(total: Int, items: [T]) {
        self.total = total
        self.items = items
        self.capped = total > items.count
    }
}

extension GitHubAPI {
    private static let reviewedCap = 100
    private static let reviewedPageLimit = 3
    private static let commentPageLimit = 5

    /// The node ID of `org`, which the contributions query needs to keep to one organization.
    public func organizationID(_ org: String) async throws -> String {
        let data = try await execute(StatsQueries.organizationID, ["org": org])
        guard let id = (data["organization"] as? [String: Any])?["id"] as? String else {
            throw APIError.graphQL("missing organization ID")
        }
        return id
    }

    /// The PRs `login` reviewed in `window`, up to 100 in `scope`. An org is one page; the personal scope
    /// drops other owners' PRs and reads up to 3 pages. `capped` when GitHub has pages after the last one read.
    public func reviewedPRs(
        window: StatsWindow, orgID: String?, login: String, scope: FetchScope
    ) async throws -> Capped<ReviewedPR> {
        if scope.org != nil && orgID == nil { throw APIError.graphQL("missing organization ID") }
        let pageLimit = scope.org == nil ? Self.reviewedPageLimit : 1
        var items: [ReviewedPR] = []
        var cursor: String?
        var hasNext = false
        var pages = 0
        repeat {
            let variables: [String: Any] = [
                "from": StatsQueries.timestamp(window.start), "to": StatsQueries.timestamp(window.githubEnd),
                "org": (scope.org == nil ? nil : orgID) ?? NSNull(), "login": login, "after": cursor ?? NSNull(),
            ]
            let data = try await execute(StatsQueries.contributions, variables)
            guard let connection = (((data["viewer"] as? [String: Any])?["contributionsCollection"]
                as? [String: Any])?["pullRequestReviewContributions"] as? [String: Any])
            else { throw APIError.graphQL("missing review contributions") }
            for node in Self.nodes(connection["nodes"]) {
                guard let pr = Self.reviewedPR(node["pullRequest"] as? [String: Any]),
                      scope.covers(pr.repo) else { continue }
                items.append(pr)
            }
            let pageInfo = connection["pageInfo"] as? [String: Any]
            hasNext = pageInfo?["hasNextPage"] as? Bool ?? false
            cursor = pageInfo?["endCursor"] as? String
            pages += 1
        } while hasNext && cursor != nil && pages < pageLimit && items.count < Self.reviewedCap
        return Capped(items: Array(items.prefix(Self.reviewedCap)), capped: hasNext || items.count > Self.reviewedCap)
    }

    /// The viewer's PRs opened in `window`, the newest 100.
    public func openedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<OpenedPR> {
        let search = try await searchResult(StatsQueries.opened, StatsQueries.openedPRs(window: window, scope: scope))
        return CountedList(total: search.total, items: search.nodes.compactMap(Self.openedPR))
    }

    /// The viewer's PRs merged in `window`, the 100 most recently opened (search can't sort by merge time).
    public func mergedPRs(window: StatsWindow, scope: FetchScope) async throws -> CountedList<MergedPR> {
        let search = try await searchResult(StatsQueries.merged, StatsQueries.mergedPRs(window: window, scope: scope))
        return CountedList(total: search.total, items: search.nodes.compactMap(Self.mergedPR))
    }

    /// How many results `query` has; reads none.
    public func issueCount(_ query: String) async throws -> Int {
        let data = try await execute(StatsQueries.count, ["q": query])
        guard let count = (data["search"] as? [String: Any])?["issueCount"] as? Int else {
            throw APIError.graphQL("missing issueCount")
        }
        return count
    }

    /// When the viewer commented in `window`, in `scope`. Reads newest pages first until one reaches back
    /// before the window, up to 5. `capped` when the 5th page still had earlier comments and was all in the window.
    public func myComments(window: StatsWindow, scope: FetchScope) async throws -> Capped<Date> {
        var dates: [Date] = []
        var before: String?
        var capped = false
        for page in 1...Self.commentPageLimit {
            let data = try await execute(StatsQueries.comments, ["before": before ?? NSNull()])
            guard let connection = (data["viewer"] as? [String: Any])?["issueComments"] as? [String: Any] else {
                throw APIError.graphQL("missing issue comments")
            }
            var oldest: Date?
            for node in Self.nodes(connection["nodes"]) {
                guard let at = Decoding.lenientDate(node["createdAt"]) else { continue }
                oldest = min(oldest ?? at, at)
                let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
                if window.contains(at), let repo, Self.inScope(repo, scope) { dates.append(at) }
            }
            let pageInfo = connection["pageInfo"] as? [String: Any]
            let hasPrevious = pageInfo?["hasPreviousPage"] as? Bool ?? false
            before = pageInfo?["startCursor"] as? String
            guard hasPrevious, before != nil, let oldest, oldest >= window.start else { break }
            capped = page == Self.commentPageLimit
        }
        return Capped(items: dates.sorted(), capped: capped)
    }

    /// Nodes that are objects; a null (an item GitHub hides) is skipped, not the whole page.
    private static func nodes(_ raw: Any?) -> [[String: Any]] {
        (raw as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    /// `covers` leaves an org to its searches, which `viewer.issueComments` has none of: its owner is checked here.
    private static func inScope(_ repo: String, _ scope: FetchScope) -> Bool {
        guard let org = scope.org else { return scope.covers(repo) }
        return repo.split(separator: "/", maxSplits: 1).first?.caseInsensitiveCompare(org) == .orderedSame
    }

    private func searchResult(_ query: String, _ q: String) async throws -> (total: Int, nodes: [[String: Any]]) {
        let data = try await execute(query, ["q": q])
        guard let search = data["search"] as? [String: Any], let total = search["issueCount"] as? Int else {
            throw APIError.graphQL("missing search")
        }
        return (total, Self.nodes(search["nodes"]).filter { !$0.isEmpty })
    }

    private static func reviewedPR(_ node: [String: Any]?) -> ReviewedPR? {
        guard let node, let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
        else { return nil }
        let events = Self.nodes((node["timelineItems"] as? [String: Any])?["nodes"])
            .compactMap { event -> ReviewRequestEvent? in
                guard let at = Decoding.lenientDate(event["createdAt"]) else { return nil }
                return ReviewRequestEvent(at: at, reviewer: Decoding.reviewer(event))
            }
        let mine = Self.nodes((node["reviews"] as? [String: Any])?["nodes"])
            .map { review in
                MyReview(
                    submittedAt: Decoding.lenientDate(review["submittedAt"]),
                    pending: review["state"] as? String == "PENDING")
            }
        return ReviewedPR(
            repo: repo, author: (node["author"] as? [String: Any])?["login"] as? String,
            requests: events, myReviews: mine)
    }

    private static func openedPR(_ node: [String: Any]) -> OpenedPR? {
        guard let created = Decoding.lenientDate(node["createdAt"]) else { return nil }
        let ready = Self.nodes((node["readyEvent"] as? [String: Any])?["nodes"]).last
        let reviews = Self.nodes((node["reviews"] as? [String: Any])?["nodes"])
            .map { review -> OpenedPRReview in
                let author = review["author"] as? [String: Any]
                return OpenedPRReview(
                    author: author?["login"] as? String ?? "ghost",
                    avatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
                    byBot: author?["__typename"] as? String == "Bot",
                    submittedAt: Decoding.lenientDate(review["submittedAt"]),
                    pending: review["state"] as? String == "PENDING")
            }
        return OpenedPR(
            createdAt: created, isDraft: node["isDraft"] as? Bool ?? false,
            isOpen: node["state"] as? String == "OPEN",
            readyAt: Decoding.lenientDate(ready?["createdAt"]),
            reviews: reviews)
    }

    private static func mergedPR(_ node: [String: Any]) -> MergedPR? {
        guard let created = Decoding.lenientDate(node["createdAt"]),
              let merged = Decoding.lenientDate(node["mergedAt"])
        else { return nil }
        return MergedPR(createdAt: created, mergedAt: merged)
    }
}
