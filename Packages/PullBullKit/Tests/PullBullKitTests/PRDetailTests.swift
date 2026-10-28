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
