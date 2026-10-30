import Foundation
import Testing
@testable import PullBullKit

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func node(_ name: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
}

@Suite struct DecodingTests {
    @Test func decodesSearchPage() throws {
        let page = try Decoding.pullRequests(fromSearch: fixture("search_page"))
        #expect(page.prs.count == 2)
        let first = page.prs[0]
        #expect(first.key == PRKey(repo: "initech/gadgets", number: 412))
        #expect(first.ci == .failure)
        #expect(first.author == "alice")
        #expect(first.commentCount == 3)
        #expect(first.lastCommentAuthor == "bob")
        #expect(first.latestReviews[0].state == .approved)
        #expect(first.latestReviews[0].author == "bob")
        #expect(first.latestReviews[1].author == "ghost")
        #expect(first.latestReviews[1].state == .changesRequested)
        #expect(first.reviewRequests.contains(.team("backend")))
        #expect(first.reviewRequests.contains(.user("carol")))
        #expect(first.headCommitDate != nil)
        #expect(page.prs[1].isDraft)
        #expect(page.prs[1].ci == .success)
        #expect(page.endCursor == "Y3Vyc29yOjI=")
        #expect(page.hasNextPage == false)
    }

    @Test func decodesCommitOids() throws {
        let json = """
        {"number":5,"title":"t","url":"https://github.com/o/r/pull/5","isDraft":false,"state":"OPEN",\
        "createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z","closedAt":null,\
        "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"o/r"},"author":{"login":"al"},\
        "comments":{"totalCount":0,"nodes":[]},\
        "commits":{"nodes":[{"commit":{"oid":"head1","committedDate":"2026-10-24T10:00:00Z","statusCheckRollup":null}}]},\
        "latestReviews":{"nodes":[{"author":{"login":"me"},"state":"APPROVED","submittedAt":"2026-10-24T11:00:00Z",\
        "commit":{"oid":"old1"}},{"author":{"login":"x"},"state":"COMMENTED","submittedAt":null,"commit":null}]},\
        "reviewRequests":{"nodes":[]}}
        """
        let node = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let pr = try Decoding.pullRequest(from: node)
        #expect(pr.headCommitOid == "head1")
        #expect(pr.latestReviews.map(\.commitOid) == ["old1", nil])
        #expect(Queries.prFields.contains("commit{oid committedDate"))
        #expect(Queries.prFields.contains("submittedAt commit{oid}"))
    }

    @Test func decodesPRLabels() throws {
        let json = """
        {"number":5,"title":"t","url":"https://github.com/o/r/pull/5","isDraft":false,"state":"OPEN",\
        "createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z","closedAt":null,\
        "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"o/r"},"author":{"login":"al"},\
        "labels":{"nodes":[{"name":"bug","color":"d73a4a"},{"name":"good first issue"}]}}
        """
        let node = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let pr = try Decoding.pullRequest(from: node)
        #expect(pr.labels == ["bug", "good first issue"])
        #expect(pr.labelColors == ["d73a4a", nil])
        #expect(pr.labelColor(at: 0) == "d73a4a")
        #expect(pr.labelColor(at: 1) == nil)
        #expect(pr.labelColor(at: 2) == nil)
        #expect(Queries.prFields.contains("labels(first:20){nodes{name color}}"))
    }

    @Test func decodesWhoMergedAPR() throws {
        let json = """
        {"number":5,"title":"t","url":"https://github.com/o/r/pull/5","isDraft":false,"state":"MERGED",\
        "createdAt":"2026-10-20T09:00:00Z","updatedAt":"2026-10-25T14:03:11Z","closedAt":"2026-10-25T14:03:11Z",\
        "headRefName":"a","baseRefName":"main","repository":{"nameWithOwner":"o/r"},"author":{"login":"al"},\
        "mergedBy":{"login":"anna"}}
        """
        let merged = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(try Decoding.pullRequest(from: merged).mergedBy == "anna")
        #expect(try Decoding.pullRequest(from: node("pr_ghost_author")).mergedBy == nil)
        #expect(Queries.prFields.contains("mergedBy{login}"))
    }

    @Test func prWithoutLabelsDecodesEmpty() throws {
        #expect(try Decoding.pullRequest(from: node("pr_ghost_author")).labels == [])
    }

    @Test func cachedPRWithoutLabelsDecodes() throws {
        let pr = PullRequest(
            key: PRKey(repo: "o/r", number: 1), title: "t", url: URL(string: "https://x/1")!, author: "a",
            authorAvatarURL: nil, state: .open, isDraft: false, createdAt: .now, updatedAt: .now, closedAt: nil,
            headRef: "h", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: [], reviewRequests: [], labels: ["bug"], labelColors: ["d73a4a"])
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(pr)) as? [String: Any])
        #expect(object["labels"] as? [String] == ["bug"])
        let current = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(current.labelColor(at: 0) == "d73a4a")
        object["labelColors"] = nil
        let beforeColors = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(beforeColors.labels == ["bug"])
        #expect(beforeColors.labelColor(at: 0) == nil)
        object["labels"] = nil
        let old = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.labels == [])
        #expect(old.title == "t")
    }

    @Test func lastCommentBot() throws {
        var n = try node("pr_ghost_author")
        n["comments"] = ["totalCount": 1, "nodes": [["author": ["__typename": "Bot", "login": "dependabot"]]]]
        let pr = try Decoding.pullRequest(from: n)
        #expect(pr.lastCommentAuthor == "dependabot")
        #expect(pr.lastCommentByBot == true)
        n["comments"] = ["totalCount": 1, "nodes": [["author": ["__typename": "User", "login": "frank"]]]]
        #expect(try Decoding.pullRequest(from: n).lastCommentByBot == false)
        #expect(Queries.prFields.contains("comments(last:1){totalCount nodes{author{__typename login}}}"))
        #expect(Queries.lastCommentAuthor.contains("author{__typename login}"))
    }

    @Test func oldCacheDecodesWithoutNewFields() throws {
        let pr = try Decoding.pullRequest(from: node("pr_ghost_author"))
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(pr)) as? [String: Any])
        object["lastCommentByBot"] = nil
        let old = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.lastCommentByBot == nil)
    }

    @Test func ghostAuthorDecodes() throws {
        let pr = try Decoding.pullRequest(from: node("pr_ghost_author"))
        #expect(pr.author == "ghost")
        #expect(pr.authorAvatarURL == nil)
        #expect(pr.ci == .none)
        #expect(pr.headCommitDate == nil)
        #expect(pr.lastCommentAuthor == nil)
    }

    @Test func mergedStateWins() throws {
        var n = try node("pr_ghost_author")
        n["state"] = "MERGED"
        n["closedAt"] = "2026-10-03T09:00:00Z"
        let pr = try Decoding.pullRequest(from: n)
        #expect(pr.state == .merged)
        #expect(pr.closedAt != nil)
    }

    @Test func ciRollupMapping() throws {
        func ci(_ state: String?) throws -> CIState {
            var n = try node("pr_ghost_author")
            let rollup: Any = state.map { ["state": $0] as [String: Any] } ?? NSNull()
            n["commits"] = ["nodes": [["commit": ["committedDate": "2026-10-02T08:00:00Z", "statusCheckRollup": rollup]]]]
            return try Decoding.pullRequest(from: n).ci
        }
        #expect(try ci("FAILURE") == .failure)
        #expect(try ci("ERROR") == .failure)
        #expect(try ci("PENDING") == .pending)
        #expect(try ci("EXPECTED") == .pending)
        #expect(try ci("SUCCESS") == .success)
        #expect(try ci(nil) == .none)
    }

    @Test func ciRollupOfOnlySkippedOrNeutralRunsIsSkipped() throws {
        func ci(_ state: String, runs: Int, statuses: Int = 0, byState: [(String, Int)]) throws -> CIState {
            var n = try node("pr_ghost_author")
            let contexts: [String: Any] = [
                "checkRunCount": runs, "statusContextCount": statuses,
                "checkRunCountsByState": byState.map { ["state": $0.0, "count": $0.1] },
            ]
            n["commits"] = ["nodes": [["commit": ["statusCheckRollup": ["state": state, "contexts": contexts]]]]]
            return try Decoding.pullRequest(from: n).ci
        }
        #expect(try ci("SUCCESS", runs: 3, byState: [("SKIPPED", 2), ("NEUTRAL", 1)]) == .skipped)
        #expect(try ci("SUCCESS", runs: 1, byState: [("SKIPPED", 1)]) == .skipped)
        // One run that passed, or a status context beside the skipped runs, is a real pass.
        #expect(try ci("SUCCESS", runs: 3, byState: [("SKIPPED", 2), ("SUCCESS", 1)]) == .success)
        #expect(try ci("SUCCESS", runs: 2, statuses: 1, byState: [("SKIPPED", 2)]) == .success)
        // Only a SUCCESS rollup is reinterpreted; no runs, or no counts (older shapes), keep it.
        #expect(try ci("FAILURE", runs: 2, byState: [("SKIPPED", 2)]) == .failure)
        #expect(try ci("SUCCESS", runs: 0, byState: []) == .success)
        var n = try node("pr_ghost_author")
        n["commits"] = ["nodes": [["commit": ["statusCheckRollup": ["state": "SUCCESS"]]]]]
        #expect(try Decoding.pullRequest(from: n).ci == .success)
        #expect(Queries.prFields.contains("statusCheckRollup{state contexts{\(Queries.rollupCounts)}}"))
    }

    @Test func decodesMergeable() throws {
        func mergeable(_ raw: String?) throws -> PullRequest {
            var n = try node("pr_ghost_author")
            n["mergeable"] = raw
            return try Decoding.pullRequest(from: n)
        }
        #expect(try mergeable("CONFLICTING").mergeable == .conflicting)
        #expect(try mergeable("CONFLICTING").hasConflicts)
        #expect(try mergeable("MERGEABLE").mergeable == .mergeable)
        #expect(try !mergeable("MERGEABLE").hasConflicts)
        // UNKNOWN is GitHub still computing: not a conflict.
        #expect(try mergeable("UNKNOWN").mergeable == .unknown)
        #expect(try !mergeable("UNKNOWN").hasConflicts)
        #expect(try mergeable(nil).mergeable == nil)
        #expect(try mergeable("SOMETHING_NEW").mergeable == nil)
        #expect(Queries.prFields.contains("isDraft state mergeable"))
    }

    @Test func cachedPRWithoutMergeableDecodes() throws {
        let pr = PullRequest(
            key: PRKey(repo: "o/r", number: 1), title: "t", url: URL(string: "https://x/1")!, author: "a",
            authorAvatarURL: nil, state: .open, isDraft: false, createdAt: .now, updatedAt: .now, closedAt: nil,
            headRef: "h", baseRef: "main", ci: .skipped, headCommitDate: nil, commentCount: 0, lastCommentAuthor: nil,
            latestReviews: [], reviewRequests: [], mergeable: .conflicting)
        let data = try JSONEncoder().encode(pr)
        #expect(try JSONDecoder().decode(PullRequest.self, from: data) == pr)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["mergeable"] as? String == "CONFLICTING")
        object["mergeable"] = nil
        let old = try JSONDecoder().decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.mergeable == nil)
        #expect(!old.hasConflicts)
        #expect(old.ci == .skipped)
    }

    @Test func malformedNodeThrows() throws {
        var n = try node("pr_ghost_author")
        n["createdAt"] = "not a date"
        #expect(throws: (any Error).self) { try Decoding.pullRequest(from: n) }
    }
}
