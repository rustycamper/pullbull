import Testing

@testable import PullBullKit

@Suite struct PersonQueryTests {
    @Test func personAlone() {
        #expect(SearchQuery.parse("@alice") == .filtered(logins: ["alice"], labels: [], words: []))
        #expect(SearchQuery.parse("＠alice") == .filtered(logins: ["alice"], labels: [], words: []))
    }

    @Test func personAndWordsAnyOrder() {
        let expected = SearchQuery.filtered(logins: ["Alice"], labels: [], words: ["login"])
        #expect(SearchQuery.parse("@Alice Login") == expected)
        #expect(SearchQuery.parse("login @Alice") == expected)
    }

    @Test func twoPeopleAnd() {
        #expect(SearchQuery.parse("@a @b").logins == ["a", "b"])
    }

    @Test func duplicateLoginsCollapse() {
        #expect(SearchQuery.parse("@a @A @me @ME").logins == ["a", "me"])
    }

    @Test func bareAtIsDropped() {
        #expect(SearchQuery.parse("@") == .empty)
        #expect(SearchQuery.parse("＠ ") == .empty)
        #expect(SearchQuery.parse("login @") == .text(["login"]))
    }

    @Test func notAPerson() {
        #expect(SearchQuery.parse("a@b") == .text(["a@b"]))
        #expect(SearchQuery.parse("@-x") == .text(["@-x"]))
        #expect(SearchQuery.parse("@a_b") == .text(["@a_b"]))
        let tooLong = "@" + String(repeating: "a", count: 40)
        #expect(SearchQuery.parse(tooLong) == .text([tooLong]))
        // A leading `-` excludes the person.
        #expect(SearchQuery.parse("-@alice").logins.isEmpty)
        #expect(SearchQuery.parse("-@alice").filter?.exclude.logins == ["alice"])
    }

    @Test func numberStaysAlone() {
        #expect(SearchQuery.parse("@alice 412") == .filtered(logins: ["alice"], labels: [], words: ["412"]))
        #expect(SearchQuery.parse("412") == .number(412))
    }

    @Test func pendingExcluded() {
        let a = "login @ge"
        #expect(SearchQuery.parse(a, excluding: a.range(of: "@ge")) == .text(["login"]))
        let b = "@ge"
        #expect(SearchQuery.parse(b, excluding: b.range(of: "@ge")) == .empty)
        let c = "#412 @ge"
        #expect(SearchQuery.parse(c, excluding: c.range(of: "@ge")) == .number(412))
    }

    @Test func wordsAccessor() {
        #expect(SearchQuery.parse("@a fix").words == ["fix"])
        #expect(SearchQuery.parse("fix").words == ["fix"])
        #expect(SearchQuery.parse("4").words == [])
    }
}
