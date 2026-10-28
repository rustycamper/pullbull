import Foundation
import Testing
@testable import PullBullKit

struct AskQueryTests {
    @Test func matchJoinsQuotedWordsWithOr() {
        #expect(AskQuery.match("Paging bug in the invoice list") == #""paging" OR "bug" OR "invoice" OR "list""#)
    }

    @Test func matchNilForStopwordsOnly() { #expect(AskQuery.match("what's that one?") == nil) }

    @Test func matchQuotesOperators() {
        #expect(AskQuery.match(#"NEAR "foo" -bar: OR baz*"#) == #""near" OR "foo" OR "bar" OR "baz""#)
    }

    @Test func askKeyRoundTrips() {
        #expect(PRKey(repo: "o/r", number: 5).askKey == "o/r#5")
        #expect(PRKey(askKey: "o/r#5") == PRKey(repo: "o/r", number: 5))
        #expect(PRKey(askKey: "acme-ui#105#105") == nil)
        #expect(PRKey(askKey: "r#5") == nil)
    }

    @Test func cardFormat() {
        let item = AskItem(
            key: PRKey(repo: "o/r", number: 7), kind: .pr, state: "merged", author: "ann",
            created: Date(timeIntervalSince1970: 1_759_276_800 + 3_600),  // 2025-10-01 01:00 UTC
            updated: Date(timeIntervalSince1970: 1_759_276_800 + 2 * 86_400 + 82_800),  // 2025-10-03 23:00 UTC
            labels: ["bug", "api"], title: "Fix paging", body: "a  b\n\n c", mergedAt: Date(timeIntervalSince1970: 1_759_276_800 + 2 * 86_400 + 82_800),
            baseRef: "main")
        #expect(AskCard.render(item).hasPrefix(
            "### o/r#7 | PR | merged | @ann | created 2025-10-01 | updated 2025-10-03 | merged 2025-10-03 into main | [bug,api]\nFix paging\na b c"))
    }

    @Test func cardCutsBodyAndHandlesMissingFields() {
        let item = AskItem(
            key: PRKey(repo: "o/r", number: 1), kind: .issue, state: "open", author: nil,
            created: Date(timeIntervalSince1970: 0), updated: Date(timeIntervalSince1970: 0),
            labels: [], title: "T", body: String(repeating: "word ", count: 600))
        let card = AskCard.render(item)
        #expect(card.hasPrefix("### o/r#1 | issue | open | @? | created 1970-01-01 | updated 1970-01-01\nT\n"))
        let header = "### o/r#1 | issue | open | @? | created 1970-01-01 | updated 1970-01-01\nT\n"
        #expect(card.count == header.count + AskCard.bodyLimit)
    }
}
