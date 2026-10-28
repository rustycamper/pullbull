import Testing

@testable import PullBullKit

@Suite struct LabelQueryTests {
    @Test func labelAlone() {
        #expect(SearchQuery.parse("~bug") == .filtered(logins: [], labels: ["bug"], words: []))
        #expect(SearchQuery.parse("～bug") == .filtered(logins: [], labels: ["bug"], words: []))
    }

    @Test func quotedLabelKeepsSpaces() {
        #expect(SearchQuery.parse(#"~"good first issue""#).labels == ["good first issue"])
        #expect(SearchQuery.parse(#"login ~"good first issue" @alice"#)
            == .filtered(logins: ["alice"], labels: ["good first issue"], words: ["login"]))
    }

    @Test func unclosedQuoteRunsToTheEnd() {
        #expect(SearchQuery.parse(#"~"good first"#).labels == ["good first"])
    }

    @Test func unclosedQuoteEndsBeforeTheNextToken() {
        #expect(SearchQuery.parse(#"~"good first issue @alice"#)
            == .filtered(logins: ["alice"], labels: ["good first issue"], words: []))
        #expect(SearchQuery.parse(#"~"good first ~ui"#).labels == ["good first", "ui"])
        #expect(SearchQuery.parse(#"label:"needs triage label:bug login"#)
            == .filtered(logins: [], labels: ["needs triage", "bug"], words: ["login"]))
        #expect(SearchQuery.parse(#"~"good first #12 fix"#)
            == .filtered(logins: [], labels: ["good first"], words: ["#12", "fix"]))
    }

    @Test func sigilInsideAWordDoesNotEndAnOpenQuote() {
        #expect(SearchQuery.parse(#"~"a@b c"#).labels == ["a@b c"])
    }

    @Test func aliasesWithAndWithoutQuotes() {
        #expect(SearchQuery.parse("label:bug").labels == ["bug"])
        #expect(SearchQuery.parse(#"label:"good first issue""#).labels == ["good first issue"])
        #expect(SearchQuery.parse("Label:bug fix") == .filtered(logins: [], labels: ["bug"], words: ["fix"]))
    }

    @Test func labelsKeepTypedCaseAndCollapseDuplicates() {
        #expect(SearchQuery.parse("~Bug ~bug label:BUG ~ui").labels == ["Bug", "ui"])
    }

    @Test func bareSigilAndAliasAreDropped() {
        #expect(SearchQuery.parse("~") == .empty)
        #expect(SearchQuery.parse("label:") == .empty)
        #expect(SearchQuery.parse(#"~"""#) == .empty)
        #expect(SearchQuery.parse("login ~") == .text(["login"]))
    }

    @Test func tildeInsideAWordIsAWord() {
        #expect(SearchQuery.parse("a~b") == .text(["a~b"]))
        #expect(SearchQuery.parse("mylabel:x") == .text(["mylabel:x"]))
    }

    @Test func numberStaysAlone() {
        #expect(SearchQuery.parse("~bug 412") == .filtered(logins: [], labels: ["bug"], words: ["412"]))
        #expect(SearchQuery.parse("#412") == .number(412))
    }

    @Test func pendingLabelExcluded() {
        let a = "login ~bu"
        #expect(SearchQuery.parse(a, excluding: a.range(of: "~bu")) == .text(["login"]))
        let b = #"~"good fi"#
        #expect(SearchQuery.parse(b, excluding: b.range(of: b)) == .empty)
    }

    @Test func tokenList() {
        #expect(SearchQuery.tokenList(logins: ["a"], labels: ["bug"]) == "@a and ~bug")
        #expect(SearchQuery.tokenList(logins: [], labels: ["bug", "good first issue"])
            == #"~bug and ~"good first issue""#)
        #expect(SearchQuery.tokenList(logins: ["a", "b"], labels: ["ui"]) == "@a, @b and ~ui")
    }

    @Test func labelToken() {
        #expect(SearchQuery.labelToken("bug") == "~bug")
        #expect(SearchQuery.labelToken("good first issue") == #"~"good first issue""#)
    }
}
