import Foundation
import Testing
@testable import PullBullKit

@Suite struct SearchContextTests {
    @Test func footerTextAddsMatches() {
        #expect(SearchContext.footerText("Titles in all of acme", matches: 3) == "Titles in all of acme · 3 matches")
        #expect(SearchContext.footerText("Titles in all of acme", matches: 1) == "Titles in all of acme · 1 match")
        #expect(SearchContext.footerText("Titles in all of acme", matches: nil) == "Titles in all of acme")
    }

    /// A focused search names the repo instead of the whole org; the rest of the line is unchanged.
    @Test func focusedNamesTheRepo() {
        #expect(SearchContext.text(
            logins: ["alice"], words: ["fix"], org: "acme", repo: "widgets", startedOnTab: nil)
            == "@alice · “fix” in widgets")
        #expect(SearchContext.accessibilityLabel(logins: ["alice"], words: [], org: "acme", repo: "widgets")
            == "Filtered by @alice, in widgets")
    }

    @Test func plain() {
        #expect(SearchContext.text(logins: ["alice"], words: [], org: "acme", startedOnTab: nil)
            == "@alice in all of acme")
    }

    @Test func wordsList() {
        #expect(SearchContext.text(
            logins: ["a", "b", "c"], words: ["login", "bug"], org: "acme", startedOnTab: nil)
            == "@a, @b and @c · “login bug” in all of acme")
    }

    @Test func typeAnywherePrefixAndNoOrg() {
        #expect(SearchContext.text(logins: ["a", "b"], words: [], org: "", startedOnTab: "Review")
            == "Started typing on Review · @a and @b in all of the organization")
    }

    @Test func accessibility() {
        #expect(SearchContext.accessibilityLabel(logins: ["alice"], words: [], org: "acme")
            == "Filtered by @alice, in all of acme")
        #expect(SearchContext.accessibilityLabel(logins: ["a", "b"], words: ["x", "y"], org: "acme")
            == "Filtered by @a and @b, titles matching x y, in all of acme")
    }

    @Test func startedOnTabWords() {
        #expect(SearchContext.text(
            logins: ["alice"], words: ["login"], org: "acme", startedOnTab: "Team")
            == "Started typing on Team · @alice · “login” in all of acme")
    }
    @Test func labels() {
        #expect(SearchContext.text(
            logins: [], labels: ["bug"], words: [], org: "acme", startedOnTab: nil)
            == "~bug in all of acme")
        #expect(SearchContext.text(
            logins: ["a"], labels: ["good first issue"], words: ["fix"], org: "acme",
            startedOnTab: nil)
            == #"@a and ~"good first issue" · “fix” in all of acme"#)
    }

    @Test func labelsAccessibility() {
        #expect(SearchContext.accessibilityLabel(logins: [], labels: ["bug"], words: [], org: "acme")
            == "Filtered by label bug, in all of acme")
        #expect(SearchContext.accessibilityLabel(logins: ["a"], labels: ["bug", "ui"], words: ["x"], org: "acme")
            == "Filtered by @a, labels bug and ui, titles matching x, in all of acme")
    }

    @Test func negatedContext() throws {
        let filter = try #require(SearchQuery.parse("@ann -@bot fix").filter)
        #expect(SearchContext.text(filter: filter, org: "acme", repo: nil, startedOnTab: nil)
            == "@ann and -@bot · “fix” in all of acme")
        let label = SearchContext.accessibilityLabel(filter: filter, org: "acme", repo: nil)
        #expect(label.contains("Filtered by @ann, excluding @bot"))
        #expect(label == "Filtered by @ann, excluding @bot, titles matching fix, in all of acme")
        let excludedOnly = try #require(SearchQuery.parse("-@bot -~wontfix").filter)
        #expect(SearchContext.accessibilityLabel(filter: excludedOnly, org: "acme", repo: nil)
            == "Filtered, excluding @bot and label wontfix, in all of acme")
    }
}
