import Foundation
import Testing
@testable import PullBullKit

private let updated = Date(timeIntervalSince1970: 1_800_000_000)
private let key = PRKey(repo: "o/r", number: 7)

private func pr(updatedAt: Date = updated, ci: CIState = .success) -> PullRequest {
    PullRequest(
        key: key, title: "t", url: URL(string: "https://x/7")!,
        author: "alice", authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: updated, updatedAt: updatedAt, closedAt: nil,
        headRef: "h", baseRef: "main", ci: ci, headCommitDate: nil, commentCount: 0,
        lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
}

private func detail(updatedAt: Date?, ci: CIState?) -> PRDetail {
    PRDetail(
        key: key, body: "", checks: [], reviews: [], comments: [], files: [],
        updatedAt: updatedAt, ci: ci)
}

@Suite struct PRDetailTests {
    @Test func legacyPRDetailHasNoLinkedIssues() throws {
        let linked = RelatedIssues(items: [], totalCount: 0, returned: 0)
        let current = PRDetail(key: key, body: "", checks: [], reviews: [], comments: [], files: [], linkedIssues: linked)
        let data = try JSONEncoder().encode(current)
        #expect(try JSONDecoder().decode(PRDetail.self, from: data).linkedIssues == linked)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["linkedIssues"] = nil
        let old = try JSONDecoder().decode(PRDetail.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.linkedIssues == nil)
    }

    @Test func prDetailQueryAsksForClosingIssues() {
        #expect(Queries.detail.contains("closingIssuesReferences(first:20)"))
        #expect(Queries.detail.contains("fragment relatedIssue on Issue"))
    }

    @Test func currentWhenUpdatedAtAndCIMatch() {
        #expect(detail(updatedAt: updated, ci: .success).isCurrent(for: pr()))
    }

    @Test func staleWhenPRUpdatedSince() {
        #expect(!detail(updatedAt: updated, ci: .success).isCurrent(for: pr(updatedAt: updated + 60)))
    }

    /// A finished CI run does not bump the PR's updatedAt, so the rollup state is compared too.
    @Test func staleWhenCIChanged() {
        #expect(!detail(updatedAt: updated, ci: .pending).isCurrent(for: pr(ci: .failure)))
    }

    @Test func staleWhenFreshnessUnknown() {
        #expect(!detail(updatedAt: nil, ci: .success).isCurrent(for: pr()))
        #expect(!detail(updatedAt: updated, ci: nil).isCurrent(for: pr()))
    }

    /// Details cached before updatedAt/ci were stored still load (as unknown freshness).
    @Test func legacyCachedDetailDecodes() throws {
        let json = #"{"key":{"repo":"o/r","number":7},"body":"b","checks":[],"reviews":[],"comments":[],"files":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(PRDetail.self, from: Data(json.utf8))
        #expect(decoded.body == "b")
        #expect(decoded.updatedAt == nil)
        #expect(decoded.ci == nil)
        #expect(decoded.changedFiles == nil)
        #expect(decoded.additions == nil)
        #expect(decoded.deletions == nil)
        #expect(decoded.checkCount == nil)
    }

    /// Without PR-level totals (an old cached detail) the totals are the sums of the fetched lists.
    /// A detail cached before the comment total was stored counts only what it holds: no "earlier" line.
    @Test func commentTotalFallsBackToTheList() {
        let comment = Comment(author: "a", body: "x", createdAt: Date(timeIntervalSince1970: 0))
        let old = PRDetail(key: key, body: "", checks: [], reviews: [], comments: [comment], files: [])
        #expect(old.commentTotal == 1)
        #expect(old.earlierCommentCount == 0)
    }

    @Test func totalsFallBackToTheLists() {
        let files = [ChangedFile(path: "a", additions: 3, deletions: 1), ChangedFile(path: "b", additions: 2, deletions: 4)]
        let checks = [Check(name: "c", state: .success, url: nil)]
        let old = PRDetail(key: key, body: "", checks: checks, reviews: [], comments: [], files: files)
        #expect(old.fileTotal == 2)
        #expect(old.additionsTotal == 5)
        #expect(old.deletionsTotal == 5)
        #expect(old.checkTotal == 1)
        #expect(!old.filesTruncated)
        #expect(!old.checksTruncated)
    }

    @Test func totalsPreferPRLevelCountsAndFlagTruncation() {
        let files = [ChangedFile(path: "a", additions: 3, deletions: 1)]
        let checks = [Check(name: "c", state: .success, url: nil)]
        let detail = PRDetail(
            key: key, body: "", checks: checks, reviews: [], comments: [], files: files,
            changedFiles: 140, additions: 900, deletions: 80, checkCount: 51)
        #expect(detail.fileTotal == 140)
        #expect(detail.additionsTotal == 900)
        #expect(detail.deletionsTotal == 80)
        #expect(detail.checkTotal == 51)
        #expect(detail.filesTruncated)
        #expect(detail.checksTruncated)
    }

    @Test func storeKeepsTotals() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir)
        let detail = PRDetail(
            key: key, body: "", checks: [], reviews: [], comments: [], files: [],
            changedFiles: 3, additions: 10, deletions: 2, checkCount: 4)
        try await store.saveDetail(detail, account: "me")
        let back = try #require(await store.loadDetail(key, account: "me"))
        #expect(back.changedFiles == 3)
        #expect(back.additions == 10)
        #expect(back.deletions == 2)
        #expect(back.checkCount == 4)
    }

    @Test func storeKeepsFreshnessFields() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SnapshotStore(directory: dir)
        try await store.saveDetail(detail(updatedAt: updated, ci: .failure), account: "me")
        let back = try #require(await store.loadDetail(key, account: "me"))
        #expect(back.updatedAt == updated)
        #expect(back.ci == .failure)
    }
}

private final class DetailTransport: GraphQLTransport, @unchecked Sendable {
    let data: Data
    private let lock = NSLock()
    private var recordedSentAt: Date?
    private let delay: Duration?
    init(_ json: String, delay: Duration? = nil) {
        data = Data(json.utf8)
        self.delay = delay
    }

    /// When `send` was called; nil until it was.
    var sentAt: Date? { lock.withLock { recordedSentAt } }

    func send(_ body: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recordedSentAt = Date() }
        if let delay { try await Task.sleep(for: delay) }
        return (data, HTTPURLResponse(
            url: URL(string: "https://api.github.com/graphql")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func detailJSON(author: String = #"{"login":"alice"}"#) -> String {
    #"""
    {"data":{"repository":{"pullRequest":{
      "body":"b","updatedAt":"2026-11-02T10:00:00Z","headRefOid":"abc123","state":"MERGED","author":\#(author),
      "commits":{"nodes":[]},
      "latestReviews":{"nodes":[
        {"author":{"login":"bob"},"state":"CHANGES_REQUESTED","submittedAt":"2026-11-02T10:00:00Z","body":"Please fix","commit":{"oid":"abc123"}}]},
      "reviewRequests":{"nodes":[]},"comments":{"totalCount":0,"nodes":[]},"files":{"totalCount":0,"nodes":[]}}}}}
    """#
}

private func fetched(_ json: String) async throws -> PRDetail {
    try await GitHubAPI(transport: DetailTransport(json), auth: StaticTokenSource("t")).detail(key)
}

@Suite struct PRDetailHeadTests {
    @Test func detailKeepsHeadAuthorState() async throws {
        let d = try await fetched(detailJSON())
        #expect(d.headOid == "abc123")
        #expect(d.author == "alice")
        #expect(d.state == .merged)
    }

    @Test func detailKeepsReviewBody() async throws {
        let d = try await fetched(detailJSON())
        #expect(d.reviews.first?.body == "Please fix")
        #expect(d.reviews.first?.commitOid == "abc123")
    }

    @Test func deletedAuthorReadsGhost() async throws {
        let d = try await fetched(detailJSON(author: "null"))
        #expect(d.author == "ghost")
    }

    @Test func detailCachedBeforeHeadDecodes() throws {
        let json = #"{"key":{"repo":"o/r","number":7},"body":"b","checks":[],"reviews":[],"comments":[],"files":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(PRDetail.self, from: Data(json.utf8))
        #expect(decoded.headOid == nil)
        #expect(decoded.author == nil)
        #expect(decoded.state == nil)
    }
}


private func group(_ content: String, count: Int, viewer: Bool, logins: [String]) -> String {
    let nodes = logins.map { #"{"login":"\#($0)"}"# }.joined(separator: ",")
    return #"{"content":"\#(content)","viewerHasReacted":\#(viewer),"reactors":{"totalCount":\#(count),"nodes":[\#(nodes)]}}"#
}

private func reactionsJSON(_ id: String, can: Bool = true, groups: [String]) -> String {
    #""id":"\#(id)","viewerCanReact":\#(can),"reactionGroups":[\#(groups.joined(separator: ","))]"#
}

private func reactedDetailJSON(descriptionGroups: [String]) -> String {
    let thumbs = group("THUMBS_UP", count: 2, viewer: true, logins: ["bob", "me"])
    let heart = group("HEART", count: 5, viewer: false, logins: ["a", "b", "c"])
    let zero = group("EYES", count: 0, viewer: false, logins: [])
    return #"""
    {"data":{"repository":{"pullRequest":{
      \#(reactionsJSON("PR_1", groups: descriptionGroups)),
      "body":"b","updatedAt":"2026-11-02T10:00:00Z","headRefOid":"abc123","state":"OPEN","author":{"login":"alice"},
      "commits":{"nodes":[]},
      "latestReviews":{"nodes":[
        {\#(reactionsJSON("PRR_1", can: false, groups: [heart])),"author":{"login":"bob"},"state":"APPROVED","submittedAt":"2026-11-02T10:00:00Z","body":"ok","commit":{"oid":"abc123"}}]},
      "reviewRequests":{"nodes":[]},
      "comments":{"totalCount":1,"nodes":[
        {\#(reactionsJSON("IC_1", groups: [zero, thumbs])),"author":{"login":"carol"},"body":"hi","createdAt":"2026-11-02T10:00:00Z"}]},
      "files":{"totalCount":0,"nodes":[]}}}}}
    """#
}

@Suite struct PRDetailReactionsTests {
    @Test func readsReactionsOnTheDescriptionCommentsAndReviews() async throws {
        let thumbs = group("THUMBS_UP", count: 2, viewer: true, logins: ["bob", "me"])
        let d = try await fetched(reactedDetailJSON(descriptionGroups: [thumbs]))
        #expect(d.reactions == Reactions(
            subjectId: "PR_1",
            groups: [ReactionGroup(content: .thumbsUp, count: 2, viewerHasReacted: true, reactors: ["bob", "me"])],
            viewerCanReact: true))
        let review = try #require(d.reviews.first?.reactions)
        #expect(review.subjectId == "PRR_1")
        #expect(!review.viewerCanReact)
        #expect(review.groups == [ReactionGroup(content: .heart, count: 5, viewerHasReacted: false, reactors: ["a", "b", "c"])])
        #expect(d.reviews.first?.id == "PRR_1")
        let comment = try #require(d.comments.first?.reactions)
        #expect(comment.subjectId == "IC_1")
        #expect(comment.groups.map(\.content) == [.thumbsUp, .eyes])
        #expect(comment.groups.map(\.count) == [2, 0])
        #expect(comment.groups.first?.viewerHasReacted == true)
    }

    @Test func stampsFetchedAtBeforeTheRequest() async throws {
        let transport = DetailTransport(detailJSON(), delay: .milliseconds(50))
        let d = try await GitHubAPI(transport: transport, auth: StaticTokenSource("t")).detail(key)
        let sentAt = try #require(transport.sentAt)
        let fetchedAt = try #require(d.fetchedAt)
        #expect(fetchedAt <= sentAt)
        #expect(fetchedAt < sentAt.addingTimeInterval(0.05))
    }

    @Test func aGroupWithAnUnknownContentIsDropped() async throws {
        let unknown = group("CONFETTI", count: 1, viewer: false, logins: ["x"])
        let heart = group("HEART", count: 1, viewer: false, logins: ["y"])
        let d = try await fetched(reactedDetailJSON(descriptionGroups: [unknown, heart]))
        #expect(d.reactions?.groups.map(\.content) == [.heart])
    }

    @Test func noReactionFieldsLeavesReactionsNil() async throws {
        let d = try await fetched(detailJSON())
        #expect(d.reactions == nil)
        #expect(d.reviews.first?.reactions == nil)
    }

    @Test func detailQuerySpreadsReactableFourWays() {
        #expect(Queries.detail.components(separatedBy: "...reactable").count - 1 == 3)
        #expect(Queries.detail.components(separatedBy: "fragment reactable on Reactable").count - 1 == 1)
        #expect(Queries.issueDetail.components(separatedBy: "...reactable").count - 1 == 2)
        #expect(Queries.issueDetail.components(separatedBy: "fragment reactable on Reactable").count - 1 == 1)
    }
}
