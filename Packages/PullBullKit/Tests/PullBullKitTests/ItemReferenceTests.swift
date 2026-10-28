import Foundation
import Testing
@testable import PullBullKit

private func item(_ repo: String, _ number: Int) -> SearchQuery { .item(repo: repo, number: number) }

@Suite struct ItemReferenceTests {
    @Test func pullAndIssueLinks() {
        #expect(SearchQuery.parse("https://github.com/initech/widgets/pull/250") == item("initech/widgets", 250))
        #expect(SearchQuery.parse("https://github.com/initech/widgets/issues/12") == item("initech/widgets", 12))
        #expect(SearchQuery.parse("http://github.com/o/r/pull/1") == item("o/r", 1))
        #expect(SearchQuery.parse("https://www.github.com/o/r/pull/1") == item("o/r", 1))
        #expect(SearchQuery.parse("HTTPS://GitHub.com/O/R/pull/1") == item("O/R", 1))
        #expect(SearchQuery.parse("github.com/o/r/pull/1") == item("o/r", 1))
        #expect(SearchQuery.parse("www.github.com/o/r/issues/1") == item("o/r", 1))
    }

    @Test func anythingAfterTheNumberIsIgnored() {
        let base = "https://github.com/o/my.repo_x-1/pull/250"
        for suffix in [
            "/", "/files", "/commits", "/commits/abc123", "/checks", "/files#diff-abc", "?w=1", "?tab=a&b=c",
            "#issuecomment-123", "#pullrequestreview-9", "/files?diff=split#r1",
        ] {
            #expect(SearchQuery.parse(base + suffix) == item("o/my.repo_x-1", 250), "\(suffix)")
        }
    }

    @Test func whitespaceAroundAPastedLink() {
        #expect(SearchQuery.parse("  https://github.com/o/r/pull/7\n") == item("o/r", 7))
        #expect(SearchQuery.parse("\thttps://github.com/o/r/issues/7 ") == item("o/r", 7))
        #expect(SearchQuery.parse("https://github.com/o/r/pull/7 fix")
            == .text(["https://github.com/o/r/pull/7", "fix"]))
    }

    @Test func shorthand() {
        #expect(SearchQuery.parse("initech/widgets#250") == item("initech/widgets", 250))
        #expect(SearchQuery.parse(" o/r#007 ") == item("o/r", 7))
        #expect(SearchQuery.parse("o/r#") == .text(["o/r#"]))
        #expect(SearchQuery.parse("o/r#x") == .text(["o/r#x"]))
        #expect(SearchQuery.parse("r#5") == .text(["r#5"]))
        #expect(SearchQuery.parse("o/r/x#5") == .text(["o/r/x#5"]))
        #expect(SearchQuery.parse("o/#5") == .text(["o/#5"]))
        #expect(SearchQuery.parse("-o/r#5") == .text(["-o/r#5"]))
        #expect(SearchQuery.parse("o/r #5") == .text(["o/r", "#5"]))
    }

    @Test func otherHostsAreNotLinks() {
        for raw in [
            "https://github.example.com/o/r/pull/1", "https://ghe.corp/o/r/pull/1", "https://gitlab.com/o/r/pull/1",
            "https://api.github.com/repos/o/r/pulls/1", "https://gist.github.com/o/r/pull/1",
            "https://github.com.evil.io/o/r/pull/1", "https://github.com:8443/o/r/pull/1",
            "https://user@github.com/o/r/pull/1", "ftp://github.com/o/r/pull/1",
        ] {
            #expect(ItemReference(raw) == nil, "\(raw)")
        }
    }

    @Test func otherPathsAndBadNumbersAreNotLinks() {
        for raw in [
            "https://github.com/o/r", "https://github.com/o/r/pull", "https://github.com/o/r/pull/",
            "https://github.com/o/r/pulls/1", "https://github.com/o/r/commit/1", "https://github.com/o/r/discussions/1",
            "https://github.com/o/r/pull/0", "https://github.com/o/r/pull/-1", "https://github.com/o/r/pull/1a",
            "https://github.com/o/r/pull/2147483648", "https://github.com/o/r/pull/99999999999999999999",
            "https://github.com/o/r/pull/%31", "https://github.com//r/pull/1", "https://github.com/o/../pull/1",
            "https://github.com/o_x/r/pull/1", "o/r#0", "o/r#2147483648",
        ] {
            #expect(ItemReference(raw) == nil, "\(raw)")
        }
        #expect(ItemReference("https://github.com/o/r/pull/2147483647")?.number == 2_147_483_647)
    }

    @Test func numbersAndWordsParseAsBefore() {
        #expect(SearchQuery.parse("#412") == .number(412))
        #expect(SearchQuery.parse("github") == .text(["github"]))
        #expect(SearchQuery.parse("https://github.com/o/r/pull/x") == .text(["https://github.com/o/r/pull/x"]))
    }

    @Test func itemIgnoresTheFocus() {
        let focus = RepoFocus(repo: "o/other")
        #expect(item("o/r", 1).keeping(focus) == nil)
        #expect(SearchQuery.number(1).keeping(focus) == focus)
        #expect(SearchQuery.parse("fix").keeping(focus) == focus)
    }

    @Test func scopeReach() {
        #expect(FetchScope.org("initech").reaches("INITECH/ui"))
        #expect(!FetchScope.org("initech").reaches("someone/ui"))
        #expect(FetchScope.personal(login: "me").reaches("me/dotfiles"))
        #expect(!FetchScope.personal(login: "me").reaches("you/dotfiles"))
        #expect(!FetchScope.personal(login: "me", repos: ["me/a"]).reaches("me/b"))
    }
}
