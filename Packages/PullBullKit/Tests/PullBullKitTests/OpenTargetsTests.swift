import Foundation
import Testing
@testable import PullBullKit

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private let key = PRKey(repo: "acme/web", number: 412)

private func pr(
    head: String?, reviews: [Review], author: String = "alice", requests: [Reviewer] = []
) -> PullRequest {
    PullRequest(
        key: key, title: "t", url: URL(string: "https://github.com/acme/web/pull/412")!,
        author: author, authorAvatarURL: nil, state: .open, isDraft: false,
        createdAt: t0, updatedAt: t0, closedAt: nil, headRef: "h", baseRef: "main",
        ci: .none, headCommitDate: t0.addingTimeInterval(3600), commentCount: 0, lastCommentAuthor: nil,
        latestReviews: reviews, reviewRequests: requests, headCommitOid: head)
}

private func review(_ oid: String?, by author: String = "me", state: ReviewState = .approved) -> Review {
    Review(author: author, state: state, submittedAt: t0, commitOid: oid)
}

private func target(_ pr: PullRequest) -> FilesLink {
    FilesLink.target(for: pr, me: "me", myTeams: [])
}

@Suite struct OpenTargetsTests {
    static let files = URL(string: "https://github.com/acme/web/pull/412/files")!

    @Test func filesSinceReview() {
        let link = target(pr(head: "bbb", reviews: [review("aaa")]))
        #expect(link.url == URL(string: "https://github.com/acme/web/pull/412/files/aaa..bbb")!)
        #expect(link.sinceReview)
        #expect(link.menuTitle == "Open Changes Since My Review")
    }

    @Test(arguments: [
        pr(head: "aaa", reviews: [review("aaa")]),
        pr(head: "bbb", reviews: []),
        pr(head: "bbb", reviews: [review(nil)]),
        pr(head: nil, reviews: [review("aaa")]),
        pr(head: "bbb", reviews: [review("aaa", by: "bob")]),
    ])
    func filesPlain(_ pr: PullRequest) {
        let link = target(pr)
        #expect(link.url == Self.files)
        #expect(!link.sinceReview)
        #expect(link.menuTitle == "Open Files Changed")
    }

    @Test func pendingReviewIgnored() {
        let link = target(pr(head: "bbb", reviews: [review("aaa", state: .pending)]))
        #expect(link.url == Self.files)
        #expect(!link.sinceReview)
    }

    @Test func myOwnPRIsPlain() {
        let link = FilesLink.target(for: pr(head: "bbb", reviews: [review("aaa")], author: "me"), me: "me", myTeams: [])
        #expect(link.url == Self.files)
    }

    @Test func myReviewMatchesCaseInsensitively() {
        let link = FilesLink.target(for: pr(head: "bbb", reviews: [review("aaa", by: "Me")]), me: "me", myTeams: [])
        #expect(link.sinceReview)
    }

    @Test func reRequestedWithNewCommitsIsPlain() {
        let link = target(pr(head: "bbb", reviews: [review("aaa")], requests: [.user("me")]))
        #expect(link.url == Self.files)
        #expect(!link.sinceReview)
        #expect(link.menuTitle == "Open Files Changed")
    }

    @Test func plainForBareKey() {
        let link = FilesLink.plain(key)
        #expect(link.url == Self.files)
        #expect(!link.sinceReview)
        #expect(link.menuTitle == "Open Files Changed")
    }

    @Test func checkout() {
        #expect(CheckoutCommand.text(for: key) == "gh pr checkout 412 -R acme/web")
    }

    @Test func failingCheck() {
        let checks = [
            Check(name: "lint", state: .success, url: URL(string: "https://ci.example/lint")!),
            Check(name: "build", state: .pending, url: URL(string: "https://ci.example/build")!),
            Check(name: "unit", state: .failure, url: nil),
            Check(name: "ui", state: .failure, url: URL(string: "https://ci.example/ui")!),
            Check(name: "e2e", state: .failure, url: URL(string: "https://ci.example/e2e")!),
        ]
        #expect(FailingCheck.url(in: checks, key: key) == URL(string: "https://ci.example/ui")!)
    }

    @Test func failingCheckFallsBackToChecksPage() {
        let checks = [
            Check(name: "lint", state: .success, url: URL(string: "https://ci.example/lint")!),
            Check(name: "build", state: .pending, url: URL(string: "https://ci.example/build")!),
            Check(name: "unit", state: .failure, url: nil),
        ]
        let page = URL(string: "https://github.com/acme/web/pull/412/checks")!
        #expect(FailingCheck.url(in: checks, key: key) == page)
        #expect(FailingCheck.url(in: [], key: key) == page)
    }

    @Test func hasFailure() {
        #expect(FailingCheck.hasFailure([Check(name: "unit", state: .failure, url: nil)]))
        #expect(!FailingCheck.hasFailure([Check(name: "lint", state: .success, url: nil)]))
    }
}
