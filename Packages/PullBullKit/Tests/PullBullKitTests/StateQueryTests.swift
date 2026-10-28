import Testing

@testable import PullBullKit

@Suite struct StateQueryTests {
    @Test func everyStateAlone() {
        #expect(SearchQuery.parse("is:open") == .filtered(logins: [], labels: [], words: [], states: [.open]))
        #expect(SearchQuery.parse("is:closed").states == [.closed])
        #expect(SearchQuery.parse("is:merged").states == [.merged])
        #expect(SearchQuery.parse("is:draft").states == [.draft])
    }

    @Test func caseInsensitive() {
        #expect(SearchQuery.parse("IS:Open").states == [.open])
        #expect(SearchQuery.parse("Is:MERGED fix") == .filtered(logins: [], labels: [], words: ["fix"], states: [.merged]))
    }

    @Test func andsWithPeopleLabelsAndWords() {
        #expect(SearchQuery.parse("@alice ~bug is:open login label:ui")
            == .filtered(logins: ["alice"], labels: ["bug", "ui"], words: ["login"], states: [.open]))
    }

    @Test func duplicatesCollapseAndContradictionsStay() {
        #expect(SearchQuery.parse("is:open IS:OPEN").states == [.open])
        #expect(SearchQuery.parse("is:open is:merged").states == [.open, .merged])
    }

    @Test func unknownValueIsAWord() {
        #expect(SearchQuery.parse("is:foo") == .text(["is:foo"]))
        #expect(SearchQuery.parse("is:Foo is:open") == .filtered(logins: [], labels: [], words: ["is:foo"], states: [.open]))
    }

    @Test func bareQualifierIsDropped() {
        #expect(SearchQuery.parse("is:") == .empty)
        #expect(SearchQuery.parse("login is:") == .text(["login"]))
    }

    @Test func insideAWordIsAWord() {
        #expect(SearchQuery.parse("this:open") == .text(["this:open"]))
    }

    @Test func openLabelQuoteEndsBeforeIt() {
        #expect(SearchQuery.parse(#"~"good first is:open"#)
            == .filtered(logins: [], labels: ["good first"], words: [], states: [.open]))
    }

    @Test func pendingStateExcluded() {
        let text = "login is:op"
        #expect(SearchQuery.parse(text, excluding: text.range(of: "is:op")) == .text(["login"]))
    }

    @Test func tokenListNamesStatesLast() {
        #expect(SearchQuery.tokenList(logins: ["a"], labels: ["bug"], states: [.open]) == "@a, ~bug and is:open")
        #expect(SearchQuery.tokenList(logins: [], labels: [], states: [.merged]) == "is:merged")
    }

    @Test func emptyMessagesNameTheState() {
        let done = SearchResults(openPRs: [], closedPRs: [], issues: [], phase: .done)
        #expect(done.emptyMessage(org: "o", query: SearchQuery.parse("is:draft"), mode: .pullRequests) == "No pull requests with is:draft")
        #expect(done.emptyMessage(org: "o", query: SearchQuery.parse("@a is:closed fix"), mode: .pullRequests)
            == "No pull requests with @a and is:closed match “fix”")
    }

    @Test func contextLine() {
        #expect(SearchContext.text(
            logins: [], labels: ["bug"], states: [.open], words: ["fix"], org: "acme",
            startedOnTab: nil) == "~bug and is:open · “fix” in all of acme")
        #expect(SearchContext.accessibilityLabel(logins: ["a"], states: [.merged], words: [], org: "acme")
            == "Filtered by @a, state merged, in all of acme")
        #expect(SearchContext.accessibilityLabel(logins: [], states: [.open, .draft], words: [], org: "acme")
            == "Filtered by states open and draft, in all of acme")
    }
}
