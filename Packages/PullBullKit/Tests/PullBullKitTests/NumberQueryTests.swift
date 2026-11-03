import Foundation
import Testing

@testable import PullBullKit

@Suite struct NumberQueryTests {
    private static func numbered(_ numbers: [Int], states: [StateFilter] = [], words: [String] = []) -> SearchQuery {
        .filtered(SearchFilter(include: SearchTerms(states: states, numbers: numbers), words: words))
    }

    @Test func numberCombinesWithAQualifier() {
        #expect(SearchQuery.parse("is:open #894") == Self.numbered([894], states: [.open]))
        #expect(SearchQuery.parse("#894 is:open") == Self.numbered([894], states: [.open]))
    }

    @Test func numberCombinesWithWords() {
        #expect(SearchQuery.parse("#894 fix") == Self.numbered([894], words: ["fix"]))
        #expect(SearchQuery.parse("revert #894") == Self.numbered([894], words: ["revert"]))
    }

    /// Without `#`, digits next to other terms are a title word, as before.
    @Test func bareDigitsStayAWord() {
        #expect(SearchQuery.parse("412 fix") == .text(["412", "fix"]))
        #expect(SearchQuery.parse("is:open 894") == .filtered(logins: [], labels: [], words: ["894"], states: [.open]))
    }

    @Test func onItsOwnItIsStillANumber() {
        #expect(SearchQuery.parse("#894") == .number(894))
    }

    @Test func repeatsCollapse() {
        #expect(SearchQuery.parse("#12 #12 is:open") == Self.numbered([12], states: [.open]))
        #expect(SearchQuery.parse("#12 #13") == Self.numbered([12, 13]))
    }

    @Test func notANumberIsAWord() {
        #expect(SearchQuery.parse("#12a is:open") == .filtered(logins: [], labels: [], words: ["#12a"], states: [.open]))
        #expect(SearchQuery.parse("-#894 is:open")
            == .filtered(logins: [], labels: [], words: ["-#894"], states: [.open]))
        #expect(SearchQuery.parse("#99999999999 is:open")
            == .filtered(logins: [], labels: [], words: ["#99999999999"], states: [.open]))
    }

    @Test func emptyMessageNamesTheNumber() {
        let done = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(done.emptyMessage(org: "o", query: .parse("is:open #894"), mode: .pullRequests)
            == "No pull requests with is:open and #894")
        #expect(done.emptyMessage(org: "o", query: .parse("#894 fix"), mode: .issues)
            == "No issues with #894 match “fix”")
    }

    @Test func contextLineNamesTheNumber() throws {
        let filter = try #require(SearchQuery.parse("is:open #894").filter)
        #expect(SearchContext.text(filter: filter, org: "initech", startedOnTab: nil) == "is:open and #894 in all of initech")
        #expect(SearchContext.accessibilityLabel(filter: filter, org: "initech")
            == "Filtered by state open, number 894, in all of initech")
    }

    private static let viewer = "me"
    private static func pr(_ number: Int, state: PRState = .open, title: String = "Fix login") -> PullRequest {
        PullRequest(
            key: PRKey(repo: "initech/gadgets", number: number), title: title,
            url: URL(string: "https://github.com/initech/gadgets/pull/\(number)")!, author: "alice",
            authorAvatarURL: nil, state: state, isDraft: false, createdAt: .distantPast, updatedAt: .distantPast,
            closedAt: nil, headRef: "a", baseRef: "main", ci: .none, headCommitDate: nil, commentCount: 0,
            lastCommentAuthor: nil, latestReviews: [], reviewRequests: [])
    }

    private static func issue(_ number: Int, open: Bool = true) -> BoardIssue {
        BoardIssue(
            key: PRKey(repo: "initech/gadgets", number: number), title: "Fix login",
            url: URL(string: "https://github.com/initech/gadgets/issues/\(number)")!, isOpen: open,
            updatedAt: nil, status: nil)
    }

    @Test func matchesOnlyThatNumber() {
        let q = SearchQuery.parse("is:open #894")
        #expect(q.matches(Self.pr(894), viewer: Self.viewer))
        #expect(!q.matches(Self.pr(895), viewer: Self.viewer))
        #expect(!q.matches(Self.pr(894, state: .merged), viewer: Self.viewer))
        #expect(q.matches(Self.issue(894), viewer: Self.viewer))
        #expect(!q.matches(Self.issue(894, open: false), viewer: Self.viewer))
    }

    @Test func wordsStillHaveToBeInTheTitle() {
        let q = SearchQuery.parse("#894 login")
        #expect(q.matches(Self.pr(894), viewer: Self.viewer))
        #expect(!q.matches(Self.pr(894, title: "Other"), viewer: Self.viewer))
    }

    @Test func twoNumbersMatchNothing() {
        let q = SearchQuery.parse("#894 #895")
        #expect(!q.matches(Self.pr(894), viewer: Self.viewer))
        #expect(!q.matches(Self.pr(895), viewer: Self.viewer))
    }

    @Test func cacheKeyCoversTheNumber() {
        let account = AccountRef(login: "alice", source: .gh)
        func key(_ raw: String) -> SearchCache.Key {
            SearchCache.Key(account: account, scope: .org("initech"), query: .parse(raw))
        }
        #expect(key("is:open #894") != key("is:open #895"))
        #expect(key("is:open #894") != key("is:open"))
        #expect(key("is:open #894") == key("#894 IS:OPEN"))
    }
}
