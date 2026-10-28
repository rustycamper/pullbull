import Foundation
import Testing
@testable import PullBullKit

private let key = PRKey(repo: "initech/widgets", number: 250)
private let url = URL(string: "https://github.com/initech/widgets/pull/250")!

@Suite struct MarkdownLinkTests {
    @Test func titleThenReferenceInParentheses() {
        #expect(MarkdownLink.item(title: "Fix token refresh", key: key, url: url)
            == "[Fix token refresh (initech/widgets#250)](https://github.com/initech/widgets/pull/250)")
    }

    @Test func bracketsAndBackslashesInTheTitleAreEscaped() {
        #expect(MarkdownLink.item(title: #"[WIP] a\b ]["#, key: key, url: url)
            == #"[\[WIP\] a\\b \]\[ (initech/widgets#250)](https://github.com/initech/widgets/pull/250)"#)
    }

    @Test func otherMarkdownInTheTitleIsLeftAsTyped() {
        #expect(MarkdownLink.item(title: "Use `fetch` for *all* (most) calls", key: key, url: url)
            == "[Use `fetch` for *all* (most) calls (initech/widgets#250)](https://github.com/initech/widgets/pull/250)")
    }

    @Test func lineBreaksAndRunsOfSpaceBecomeOneSpace() {
        #expect(MarkdownLink.item(title: "  Fix\n\ttoken   refresh \r\n", key: key, url: url)
            == "[Fix token refresh (initech/widgets#250)](https://github.com/initech/widgets/pull/250)")
    }

    @Test func noTitleIsTheReferenceAlone() {
        #expect(MarkdownLink.item(title: nil, key: key, url: url)
            == "[initech/widgets#250](https://github.com/initech/widgets/pull/250)")
        #expect(MarkdownLink.item(title: " \n ", key: key, url: url)
            == "[initech/widgets#250](https://github.com/initech/widgets/pull/250)")
    }

    @Test func parenthesesAndSpacesInTheURLArePercentEncoded() {
        let odd = URL(string: "https://example.com/a(b)c%20d")!
        #expect(MarkdownLink.item(title: "T", key: key, url: odd)
            == "[T (initech/widgets#250)](https://example.com/a%28b%29c%20d)")
    }
}
