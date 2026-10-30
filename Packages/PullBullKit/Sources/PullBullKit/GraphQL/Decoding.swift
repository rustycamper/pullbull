import Foundation

public enum Decoding {
    public struct DecodingError: Error, Sendable {
        public let message: String
    }

    public static func pullRequests(
        fromSearch json: Data
    ) throws -> (prs: [PullRequest], endCursor: String?, hasNextPage: Bool) {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
              let data = root["data"] as? [String: Any],
              let search = data["search"] as? [String: Any],
              let nodes = search["nodes"] as? [Any]
        else { throw DecodingError(message: "missing data.search.nodes") }
        let pageInfo = search["pageInfo"] as? [String: Any]
        let prs = try nodes.compactMap { raw -> PullRequest? in
            guard let node = raw as? [String: Any], !node.isEmpty else { return nil }
            return try pullRequest(from: node)
        }
        return (prs, pageInfo?["endCursor"] as? String, pageInfo?["hasNextPage"] as? Bool ?? false)
    }

    public static func pullRequest(from node: [String: Any]) throws -> PullRequest {
        let repo = try string(node, "repository", "nameWithOwner")
        let number = try int(node, "number")
        let author = node["author"] as? [String: Any]
        let comments = node["comments"] as? [String: Any]
        let commentNodes = comments?["nodes"] as? [[String: Any]] ?? []
        let lastCommenter = commentNodes.last?["author"] as? [String: Any]
        let commit = ((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["commit"]
            as? [String: Any]
        let reviewNodes = (node["latestReviews"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let requestNodes = (node["reviewRequests"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let labelNodes = (node["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let labels = labels(labelNodes)

        let stateRaw = try string(node, "state")
        guard let state = PRState(rawValue: stateRaw.lowercased()) else {
            throw DecodingError(message: "unknown PR state \(stateRaw)")
        }
        guard let url = URL(string: try string(node, "url")) else {
            throw DecodingError(message: "bad url")
        }

        return PullRequest(
            key: PRKey(repo: repo, number: number),
            title: try string(node, "title"),
            url: url,
            author: author?["login"] as? String ?? "ghost",
            authorAvatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
            state: state,
            isDraft: node["isDraft"] as? Bool ?? false,
            createdAt: try date(try string(node, "createdAt")),
            updatedAt: try date(try string(node, "updatedAt")),
            closedAt: try optionalDate(node["closedAt"]),
            headRef: try string(node, "headRefName"),
            baseRef: try string(node, "baseRefName"),
            ci: ciState(rollup: commit?["statusCheckRollup"]),
            headCommitDate: try optionalDate(commit?["committedDate"]),
            commentCount: comments?["totalCount"] as? Int ?? 0,
            lastCommentAuthor: lastCommenter?["login"] as? String,
            latestReviews: try reviewNodes.map(review),
            reviewRequests: requestNodes.compactMap(reviewer),
            headCommitOid: commit?["oid"] as? String,
            labels: labels.map(\.name), labelColors: labels.map(\.color),
            mergedBy: (node["mergedBy"] as? [String: Any])?["login"] as? String,
            mergeable: (node["mergeable"] as? String).flatMap(Mergeable.init(rawValue:)),
            lastCommentByBot: lastCommenter.map { $0["__typename"] as? String == "Bot" }
        )
    }

    /// An issue node (`issueRowFields`); nil without number, title, url or repo. `status` and
    /// `boardItemId` come from the board item around it. With a `viewer`, `myAssignment` is the
    /// latest AssignedEvent in the node's `timelineItems` that added that login.
    public static func issue(
        from node: [String: Any], status: BoardStatusValue? = nil, boardItemId: Int? = nil,
        assignmentFor viewer: String? = nil
    ) -> BoardIssue? {
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let url = (node["url"] as? String).flatMap(URL.init(string:)),
              let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String
        else { return nil }
        let labelNodes = (node["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let labels = labels(labelNodes)
        let lastComment = (((node["lastComment"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last?["author"]
            as? [String: Any])
        let assigneeNodes = (node["assignees"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        return BoardIssue(
            key: PRKey(repo: repo, number: number), title: title, url: url,
            isOpen: node["state"] as? String == "OPEN",
            author: (node["author"] as? [String: Any])?["login"] as? String,
            stateReason: stateReason(node["stateReason"] as? String),
            createdAt: lenientDate(node["createdAt"]),
            updatedAt: lenientDate(node["updatedAt"]),
            closedAt: lenientDate(node["closedAt"]),
            commentCount: (node["comments"] as? [String: Any])?["totalCount"] as? Int ?? 0,
            lastCommentAuthor: lastComment?["login"] as? String,
            lastCommentByBot: lastComment.map { $0["__typename"] as? String == "Bot" },
            labels: labels.map(\.name), labelColors: labels.map(\.color),
            assignees: assigneeNodes.compactMap { node in
                guard let login = node["login"] as? String else { return nil }
                return Assignee(login: login, avatarURL: (node["avatarUrl"] as? String).flatMap(URL.init(string:)))
            },
            status: status,
            boardItemId: boardItemId,
            myAssignment: viewer.flatMap { assignment(node, viewer: $0) },
            statusMoves: timeline(node, "statusMoves").compactMap(statusMove),
            lastReopen: timeline(node, "lastReopen").last.flatMap(stateChange),
            lastClose: timeline(node, "lastClose").last.flatMap(stateChange)
        )
    }

    /// The nodes of the timeline connection aliased `alias`; empty when it wasn't selected.
    private static func timeline(_ node: [String: Any], _ alias: String) -> [[String: Any]] {
        (node[alias] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    }

    /// A ProjectV2ItemStatusChangedEvent; nil without a date or project. An empty status (the card was
    /// just added, or its Status cleared) reads as none.
    private static func statusMove(_ node: [String: Any]) -> StatusMove? {
        guard let at = lenientDate(node["createdAt"]),
              let project = node["project"] as? [String: Any],
              let number = project["number"] as? Int,
              let owner = (project["owner"] as? [String: Any])?["login"] as? String
        else { return nil }
        let from = (node["previousStatus"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let to = (node["status"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let actor = node["actor"] as? [String: Any]
        return StatusMove(
            actor: actor?["login"] as? String, byBot: actor?["__typename"] as? String == "Bot",
            from: from, to: to, at: at, project: number, owner: owner)
    }

    /// A ClosedEvent or ReopenedEvent; nil without a date.
    private static func stateChange(_ node: [String: Any]) -> IssueStateChange? {
        lenientDate(node["createdAt"]).map {
            IssueStateChange(actor: (node["actor"] as? [String: Any])?["login"] as? String, at: $0)
        }
    }

    /// Each label node's name with its colour, in GitHub's order; a node without a name is left out.
    private static func labels(_ nodes: [[String: Any]]) -> [(name: String, color: String?)] {
        nodes.compactMap { label in (label["name"] as? String).map { ($0, label["color"] as? String) } }
    }

    /// An Ask search node (`Queries.askSearch`); nil without `__typename`, number, title, repo or a
    /// readable created/updated date. A draft PR that is still open reads "draft".
    public static func askItem(from node: [String: Any]) -> AskItem? {
        let kind: AskItem.Kind
        switch node["__typename"] as? String {
        case "PullRequest": kind = .pr
        case "Issue": kind = .issue
        default: return nil
        }
        guard let number = node["number"] as? Int,
              let title = node["title"] as? String,
              let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String,
              let state = node["state"] as? String,
              let created = (node["createdAt"] as? String).flatMap({ try? date($0) }),
              let updated = (node["updatedAt"] as? String).flatMap({ try? date($0) })
        else { return nil }
        let labelNodes = (node["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        let isDraft = node["isDraft"] as? Bool == true
        return AskItem(
            key: PRKey(repo: repo, number: number), kind: kind,
            state: kind == .pr && isDraft && state == "OPEN" ? "draft" : state.lowercased(),
            author: (node["author"] as? [String: Any])?["login"] as? String,
            created: created, updated: updated,
            labels: labelNodes.compactMap { $0["name"] as? String },
            title: title, body: node["body"] as? String ?? "",
            mergedAt: lenientDate(node["mergedAt"]),
            baseRef: node["baseRefName"] as? String)
    }

    /// A board item's `fieldValueByName` value; nil unless both name and optionId are present.
    public static func statusValue(_ raw: Any?) -> BoardStatusValue? {
        guard let value = raw as? [String: Any],
              let name = value["name"] as? String,
              let optionId = value["optionId"] as? String
        else { return nil }
        return BoardStatusValue(optionId: optionId, name: name)
    }

    static func stateReason(_ raw: String?) -> IssueStateReason? {
        switch raw {
        case "COMPLETED": .completed
        case "NOT_PLANNED": .notPlanned
        case "DUPLICATE": .duplicate
        case "REOPENED": .reopened
        default: nil
        }
    }

    private static func assignment(_ node: [String: Any], viewer: String) -> Assignment? {
        let events = (node["timelineItems"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        return events.compactMap { event -> Assignment? in
            guard let assignee = event["assignee"] as? [String: Any],
                  assignee["__typename"] as? String == "User",
                  let login = assignee["login"] as? String,
                  login.caseInsensitiveCompare(viewer) == .orderedSame,
                  let at = lenientDate(event["createdAt"])
            else { return nil }
            return Assignment(actor: (event["actor"] as? [String: Any])?["login"] as? String, at: at)
        }.max { $0.at < $1.at }
    }

    private static func lenientDate(_ raw: Any?) -> Date? {
        (raw as? String).flatMap { try? date($0) }
    }

    /// A `statusCheckRollup` object. GitHub rolls skipped and neutral runs up as SUCCESS; when the
    /// context counts (`Queries.rollupCounts`) show that every check was one of those, it is `.skipped`.
    static func ciState(rollup raw: Any?) -> CIState {
        let rollup = raw as? [String: Any]
        let state = ciState(rollup?["state"] as? String)
        guard state == .success,
              let contexts = rollup?["contexts"] as? [String: Any],
              let runs = contexts["checkRunCount"] as? Int, runs > 0,
              contexts["statusContextCount"] as? Int == 0,
              let byState = contexts["checkRunCountsByState"] as? [[String: Any]]
        else { return state }
        let skipped = byState.reduce(0) { total, entry in
            ["SKIPPED", "NEUTRAL"].contains(entry["state"] as? String) ? total + (entry["count"] as? Int ?? 0) : total
        }
        return skipped == runs ? .skipped : state
    }

    static func ciState(_ raw: String?) -> CIState {
        switch raw {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
    }

    static func review(_ node: [String: Any]) throws -> Review {
        let raw = try string(node, "state")
        let state: ReviewState
        switch raw {
        case "APPROVED": state = .approved
        case "CHANGES_REQUESTED": state = .changesRequested
        case "COMMENTED": state = .commented
        case "DISMISSED": state = .dismissed
        case "PENDING": state = .pending
        default: throw DecodingError(message: "unknown review state \(raw)")
        }
        return Review(
            author: (node["author"] as? [String: Any])?["login"] as? String ?? "ghost",
            state: state,
            submittedAt: try optionalDate(node["submittedAt"]),
            commitOid: (node["commit"] as? [String: Any])?["oid"] as? String
        )
    }

    private static func reviewer(_ node: [String: Any]) -> Reviewer? {
        guard let r = node["requestedReviewer"] as? [String: Any] else { return nil }
        switch r["__typename"] as? String {
        case "User": return (r["login"] as? String).map(Reviewer.user)
        case "Team": return (r["slug"] as? String).map(Reviewer.team)
        default: return nil
        }
    }

    private static func string(_ node: [String: Any], _ keys: String...) throws -> String {
        var current: Any? = node
        for key in keys { current = (current as? [String: Any])?[key] }
        guard let value = current as? String else {
            throw DecodingError(message: "missing \(keys.joined(separator: "."))")
        }
        return value
    }

    private static func int(_ node: [String: Any], _ key: String) throws -> Int {
        guard let value = node[key] as? Int else { throw DecodingError(message: "missing \(key)") }
        return value
    }

    static func date(_ raw: String) throws -> Date {
        guard let date = try? Date(raw, strategy: .iso8601) else {
            throw DecodingError(message: "bad date \(raw)")
        }
        return date
    }

    private static func optionalDate(_ raw: Any?) throws -> Date? {
        guard let raw = raw as? String else { return nil }
        return try date(raw)
    }
}
