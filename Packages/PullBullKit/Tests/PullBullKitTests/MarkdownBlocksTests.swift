import Foundation
import Testing
@testable import PullBullKit

private func parse(_ source: String) -> [MarkdownBlock] { MarkdownBlock.parse(source) }

@Suite struct MarkdownBlocksTests {
    @Test func emptyAndBlankSourceHaveNoBlocks() {
        #expect(parse("").isEmpty)
        #expect(parse("\n  \n\n").isEmpty)
    }

    @Test func paragraphsSplitOnBlankLinesAndKeepLineBreaks() {
        #expect(parse("one\ntwo\n\nthree") == [.paragraph("one\ntwo"), .paragraph("three")])
    }

    @Test func crlfIsNormalised() {
        #expect(parse("# T\r\n\r\nbody\r\nmore") == [.heading(level: 1, text: "T"), .paragraph("body\nmore")])
    }

    @Test func atxHeadings() {
        #expect(parse("# One\n## Two ##\n###### Six\n####### seven") == [
            .heading(level: 1, text: "One"),
            .heading(level: 2, text: "Two"),
            .heading(level: 6, text: "Six"),
            .paragraph("####### seven"),
        ])
        #expect(parse("#hashtag") == [.paragraph("#hashtag")])
    }

    @Test func setextHeadings() {
        #expect(parse("Title\n=====\nSub\n---") == [.heading(level: 1, text: "Title"), .heading(level: 2, text: "Sub")])
    }

    @Test func thematicBreak() {
        #expect(parse("a\n\n---\n\nb") == [.paragraph("a"), .rule, .paragraph("b")])
        #expect(parse("* * *") == [.rule])
    }

    @Test func bulletList() {
        #expect(parse("- one\n* two\n+ three") == [.list([
            .init(indent: 0, marker: .bullet, text: "one"),
            .init(indent: 0, marker: .bullet, text: "two"),
            .init(indent: 0, marker: .bullet, text: "three"),
        ])])
    }

    @Test func orderedListKeepsNumbers() {
        #expect(parse("1. one\n2) two\n10. ten") == [.list([
            .init(indent: 0, marker: .ordered(1), text: "one"),
            .init(indent: 0, marker: .ordered(2), text: "two"),
            .init(indent: 0, marker: .ordered(10), text: "ten"),
        ])])
    }

    @Test func nestedListItemsCarryIndent() {
        #expect(parse("- a\n  - b\n    - c\n- d") == [.list([
            .init(indent: 0, marker: .bullet, text: "a"),
            .init(indent: 1, marker: .bullet, text: "b"),
            .init(indent: 2, marker: .bullet, text: "c"),
            .init(indent: 0, marker: .bullet, text: "d"),
        ])])
    }

    @Test func taskItems() {
        #expect(parse("- [ ] todo\n- [x] done\n- [X] Done\n- [y] not a task") == [.list([
            .init(indent: 0, marker: .bullet, task: false, text: "todo"),
            .init(indent: 0, marker: .bullet, task: true, text: "done"),
            .init(indent: 0, marker: .bullet, task: true, text: "Done"),
            .init(indent: 0, marker: .bullet, text: "[y] not a task"),
        ])])
    }

    @Test func listItemContinuationLinesJoin() {
        #expect(parse("- first\n  wrapped\n- second") == [.list([
            .init(indent: 0, marker: .bullet, text: "first\nwrapped"),
            .init(indent: 0, marker: .bullet, text: "second"),
        ])])
    }

    @Test func looseListStaysOneList() {
        #expect(parse("- a\n\n- b") == [.list([
            .init(indent: 0, marker: .bullet, text: "a"),
            .init(indent: 0, marker: .bullet, text: "b"),
        ])])
    }

    @Test func paragraphAfterListEndsIt() {
        #expect(parse("- a\n\nafter") == [.list([.init(indent: 0, marker: .bullet, text: "a")]), .paragraph("after")])
    }

    @Test func numberInsideParagraphIsNotAList() {
        #expect(parse("Fixes the bug in\n2024. Really.") == [.paragraph("Fixes the bug in\n2024. Really.")])
    }

    @Test func fencedCodeKeepsContentVerbatim() {
        let source = "before\n```swift\nlet a = 1\n\n# not a heading\n```\nafter"
        #expect(parse(source) == [
            .paragraph("before"),
            .code(language: "swift", text: "let a = 1\n\n# not a heading"),
            .paragraph("after"),
        ])
    }

    @Test func tildeFenceAndUnclosedFence() {
        #expect(parse("~~~\nx\n~~~") == [.code(language: nil, text: "x")])
        #expect(parse("```\nopen\nforever") == [.code(language: nil, text: "open\nforever")])
    }

    @Test func indentedCode() {
        #expect(parse("text\n\n    code 1\n      code 2\n\nmore") == [
            .paragraph("text"),
            .code(language: nil, text: "code 1\n  code 2"),
            .paragraph("more"),
        ])
    }

    @Test func blockQuoteParsesItsContent() {
        #expect(parse("> # Q\n> - item\n>\n> text") == [.quote([
            .heading(level: 1, text: "Q"),
            .list([.init(indent: 0, marker: .bullet, text: "item")]),
            .paragraph("text"),
        ])])
    }

    @Test func htmlCommentsAreDropped() {
        let source = "## Summary\n<!-- Describe\nthe change -->\nReal text <!-- inline --> here"
        #expect(parse(source) == [.heading(level: 2, text: "Summary"), .paragraph("Real text  here")])
    }

    @Test func htmlCommentInsideCodeIsKept() {
        #expect(parse("```\n<!-- keep -->\n```") == [.code(language: nil, text: "<!-- keep -->")])
    }

    @Test func typicalTemplate() {
        let source = """
        ## What
        Adds **cache** sync.

        ## Checklist
        - [x] Tests
        - [ ] Docs

        ```bash
        make test
        ```
        """
        #expect(parse(source) == [
            .heading(level: 2, text: "What"),
            .paragraph("Adds **cache** sync."),
            .heading(level: 2, text: "Checklist"),
            .list([
                .init(indent: 0, marker: .bullet, task: true, text: "Tests"),
                .init(indent: 0, marker: .bullet, task: false, text: "Docs"),
            ]),
            .code(language: "bash", text: "make test"),
        ])
    }

    // MARK: Comments (N5)

    @Test func unclosedCommentKeepsTheText() {
        #expect(parse("Strip `<!--` markers from templates.\n\n## Testing\n\n- ran the suite") == [
            .paragraph("Strip `<!--` markers from templates."),
            .heading(level: 2, text: "Testing"),
            .list([.init(indent: 0, marker: .bullet, text: "ran the suite")]),
        ])
        #expect(parse("<!-- never closed\n\n## Testing") == [
            .paragraph("<!-- never closed"),
            .heading(level: 2, text: "Testing"),
        ])
        #expect(parse("text <!-- open\nmore -->") == [.paragraph("text <!-- open\nmore -->")])
    }

    @Test func commentInsideCodeSpanIsKept() {
        #expect(parse("use `<!-- x -->` here") == [.paragraph("use `<!-- x -->` here")])
        #expect(parse("a <!-- gone --> `<!-- kept -->`") == [.paragraph("a  `<!-- kept -->`")])
    }

    @Test func textAfterAClosedCommentBlockStays() {
        #expect(parse("<!-- hint\nmore -->tail\nnext") == [.paragraph("tail\nnext")])
    }

    // MARK: Tables

    private typealias Table = MarkdownBlock.Table

    @Test func simpleTable() {
        let source = """
        | Header | Value | Why / what was checked |
        |---|---|---|
        | CI | green | ran `make test` |
        | Docs | **yes** | README |
        """
        #expect(parse(source) == [.table(Table(
            alignments: [.leading, .leading, .leading],
            header: ["Header", "Value", "Why / what was checked"],
            rows: [["CI", "green", "ran `make test`"], ["Docs", "**yes**", "README"]]))])
    }

    @Test func alignments() {
        let source = "| a | b | c | d |\n| :--- | :---: | ---: | --- |\n| 1 | 2 | 3 | 4 |"
        #expect(parse(source) == [.table(Table(
            alignments: [.leading, .center, .trailing, .leading],
            header: ["a", "b", "c", "d"],
            rows: [["1", "2", "3", "4"]]))])
    }

    @Test func noOuterPipes() {
        #expect(parse("a | b\n--- | ---\n1 | 2") == [.table(Table(
            alignments: [.leading, .leading], header: ["a", "b"], rows: [["1", "2"]]))])
    }

    @Test func escapedPipeAndCodeSpan() {
        #expect(parse("| x | y |\n|---|---|\n| `a|b` | a \\| b |") == [.table(Table(
            alignments: [.leading, .leading], header: ["x", "y"], rows: [["`a|b`", "a | b"]]))])
    }

    @Test func raggedRows() {
        #expect(parse("| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |\nlone") == [.table(Table(
            alignments: [.leading, .leading], header: ["a", "b"],
            rows: [["1", ""], ["1", "2"], ["lone", ""]]))])
    }

    @Test func mismatchedDelimiterIsNotATable() {
        #expect(parse("| a | b | c |\n|---|---|\n| 1 | 2 | 3 |") == [.paragraph("| a | b | c |\n|---|---|\n| 1 | 2 | 3 |")])
    }

    @Test func tableEndsAtBlankLineAndAtBlock() {
        let table = MarkdownBlock.table(Table(alignments: [.leading], header: ["a"], rows: [["1"]]))
        #expect(parse("| a |\n|---|\n| 1 |\n\nafter") == [table, .paragraph("after")])
        #expect(parse("| a |\n|---|\n| 1 |\n# Next") == [table, .heading(level: 1, text: "Next")])
        #expect(parse("| a |\n|---|\n| 1 |\n- item") == [table, .list([.init(indent: 0, marker: .bullet, text: "item")])])
    }

    @Test func tableAfterParagraphLine() {
        #expect(parse("intro text\n| a | b |\n|---|---|\n| 1 | 2 |") == [
            .paragraph("intro text"),
            .table(Table(alignments: [.leading, .leading], header: ["a", "b"], rows: [["1", "2"]])),
        ])
    }

    @Test func tableInQuote() {
        #expect(parse("> | a |\n> |---|\n> | 1 |") == [.quote([
            .table(Table(alignments: [.leading], header: ["a"], rows: [["1"]])),
        ])])
    }

    @Test func pipeWithoutDelimiterIsParagraph() {
        #expect(parse("a | b") == [.paragraph("a | b")])
        #expect(parse("a | b\nmore") == [.paragraph("a | b\nmore")])
    }

    @Test func columnCap() {
        let cells = (0..<40).map { "c\($0)" }
        let source = "| " + cells.joined(separator: " | ") + " |\n"
            + String(repeating: "|---", count: 40) + "|\n"
            + "| " + cells.joined(separator: " | ") + " |"
        guard case .table(let table)? = parse(source).first else { Issue.record("expected a table"); return }
        #expect(table.header == Array(cells.prefix(MarkdownBlock.maxTableColumns)))
        #expect(table.alignments.count == MarkdownBlock.maxTableColumns)
        #expect(table.rows == [Array(cells.prefix(MarkdownBlock.maxTableColumns))])
    }

    @Test func setextUnderlineAndIndentedLinesAreNotTables() {
        #expect(parse("| a |\n---") == [.heading(level: 2, text: "| a |")])
        #expect(parse("text\n    | a | b |\n    |---|---|") == [.paragraph("text\n| a | b |\n|---|---|")])
    }

    /// Our choice, not GitHub parity: GitHub may keep these lines as lazy text of the item. List items are
    /// flat text here, so a table there would show as raw pipes; ending the list renders it as a table.
    @Test func tableEndsAnOpenList() {
        #expect(parse("- item\n| a |\n|---|\n| 1 |") == [
            .list([.init(indent: 0, marker: .bullet, text: "item")]),
            .table(Table(alignments: [.leading], header: ["a"], rows: [["1"]])),
        ])
    }

    @Test func tableInitFitsColumnsToTheHeader() {
        let table = Table(alignments: [.center], header: ["a", "b"], rows: [["1"], ["1", "2", "3"]])
        #expect(table.alignments == [.center, .leading])
        #expect(table.rows == [["1", ""], ["1", "2"]])
        #expect(Table(alignments: [.center, .trailing], header: ["a"], rows: []).alignments == [.center])
    }

    // MARK: Details

    private static func bullets(_ texts: String...) -> MarkdownBlock {
        .list(texts.map { .init(indent: 0, marker: .bullet, text: $0) })
    }

    @Test func detailsWithTagsOnTheirOwnLines() {
        let source = "Intro\n\n<details>\n<summary>Verification</summary>\n\n- Ran `make test`\n- Built the app\n\n</details>\n\nAfter"
        #expect(parse(source) == [
            .paragraph("Intro"),
            .details(summary: "Verification", blocks: [Self.bullets("Ran `make test`", "Built the app")], open: false),
            .paragraph("After"),
        ])
    }

    @Test func detailsAndSummaryOnOneLine() {
        #expect(parse("<details><summary>**Verification**</summary>\n\nBody\n\n</details>") == [
            .details(summary: "**Verification**", blocks: [.paragraph("Body")], open: false),
        ])
    }

    @Test func detailsClosedRightAfterContent() {
        #expect(parse("<details>\n<summary>X</summary>\nline one\nline two\n</details>\nafter") == [
            .details(summary: "X", blocks: [.paragraph("line one\nline two")], open: false),
            .paragraph("after"),
        ])
        #expect(parse("<details>\n<summary>X</summary>\n\n| a |\n|---|\n| 1 |\n</details>") == [
            .details(summary: "X", blocks: [.table(Table(alignments: [.leading], header: ["a"], rows: [["1"]]))], open: false),
        ])
        #expect(parse("<details>\n<summary>X</summary>\n\n- a\n- b\n</details>") == [
            .details(summary: "X", blocks: [Self.bullets("a", "b")], open: false),
        ])
    }

    @Test func detailsHoldListsCodeAndTables() {
        let source = """
        <details>
        <summary>Verification</summary>

        - [x] Tests
        ```swift
        let a = 1
        </details>
        ```
        | Check | Result |
        |---|---|
        | CI | green |

        </details>
        """
        #expect(parse(source) == [.details(summary: "Verification", blocks: [
            .list([.init(indent: 0, marker: .bullet, task: true, text: "Tests")]),
            .code(language: "swift", text: "let a = 1\n</details>"),
            .table(Table(alignments: [.leading, .leading], header: ["Check", "Result"], rows: [["CI", "green"]])),
        ], open: false)])
    }

    @Test func nestedDetails() {
        let source = "<details>\n<summary>Outer</summary>\n\n<details>\n<summary>Inner</summary>\n\ndeep\n</details>\n\nshallow\n</details>"
        #expect(parse(source) == [.details(summary: "Outer", blocks: [
            .details(summary: "Inner", blocks: [.paragraph("deep")], open: false),
            .paragraph("shallow"),
        ], open: false)])
    }

    @Test func commentsInsideDetailsAreDropped() {
        let source = "<details>\n<summary>Verification</summary>\n<!-- Say how you checked it -->\n\nBody <!-- hint -->\n</details>"
        #expect(parse(source) == [.details(summary: "Verification", blocks: [.paragraph("Body")], open: false)])
    }

    @Test func detailsOpenAttributeAndTagCase() {
        #expect(parse("<details open>\n<summary>A</summary>\nx\n</details>") == [
            .details(summary: "A", blocks: [.paragraph("x")], open: true),
        ])
        #expect(parse("<DETAILS class=\"note\" Open>\n<Summary>A</SUMMARY>\nx\n</Details>") == [
            .details(summary: "A", blocks: [.paragraph("x")], open: true),
        ])
        #expect(parse("<details class=\"opener\">\n<summary>A</summary>\nx\n</details>") == [
            .details(summary: "A", blocks: [.paragraph("x")], open: false),
        ])
    }

    @Test func detailsSummaryDefaultsAndPlacement() {
        #expect(parse("<details>\nx\n</details>") == [.details(summary: "Details", blocks: [.paragraph("x")], open: false)])
        #expect(parse("<details><summary> </summary>\nx\n</details>") == [
            .details(summary: "Details", blocks: [.paragraph("x")], open: false),
        ])
        #expect(parse("<details>\n\n<summary>\nVerification\n</summary>\n\nx\n</details>") == [
            .details(summary: "Verification", blocks: [.paragraph("x")], open: false),
        ])
        #expect(parse("  <details>\n  <summary>A</summary>\n  x\n  </details>") == [
            .details(summary: "A", blocks: [.paragraph("x")], open: false),
        ])
        #expect(parse("<details>\n<summary>A</summary>\n</details>") == [.details(summary: "A", blocks: [], open: false)])
    }

    @Test func detailsEndParagraphsAndLists() {
        #expect(parse("text\n<details>\nx\n</details>") == [
            .paragraph("text"),
            .details(summary: "Details", blocks: [.paragraph("x")], open: false),
        ])
        #expect(parse("- a\n<details>\nx\n</details>") == [
            Self.bullets("a"),
            .details(summary: "Details", blocks: [.paragraph("x")], open: false),
        ])
        #expect(parse("| a |\n|---|\n| 1 |\n<details>\nx\n</details>") == [
            .table(Table(alignments: [.leading], header: ["a"], rows: [["1"]])),
            .details(summary: "Details", blocks: [.paragraph("x")], open: false),
        ])
    }

    @Test func tagsInCodeStayLiteral() {
        #expect(parse("```\n<details>\n<summary>X</summary>\n</details>\n```") == [
            .code(language: nil, text: "<details>\n<summary>X</summary>\n</details>"),
        ])
        #expect(parse("    <details>\n    x\n    </details>") == [.code(language: nil, text: "<details>\nx\n</details>")])
        #expect(parse("Use `<details>` and `</details>`") == [.paragraph("Use `<details>` and `</details>`")])
        #expect(parse("> <details>\n> x\n</details>") == [.quote([.paragraph("<details>\nx")]), .paragraph("</details>")])
    }

    @Test func unclosedAndStrayTagsStayLiteral() {
        #expect(parse("<details>\n<summary>X</summary>\n\nBody") == [
            .paragraph("<details>\n<summary>X</summary>"), .paragraph("Body"),
        ])
        // A closer hidden in a fence does not close the section.
        #expect(parse("<details>\n```\n</details>\n```") == [
            .paragraph("<details>"), .code(language: nil, text: "</details>"),
        ])
        #expect(parse("</details>") == [.paragraph("</details>")])
        #expect(parse("<summary>X</summary>") == [.paragraph("<summary>X</summary>")])
        #expect(parse("<detailsx>\nx\n</details>") == [.paragraph("<detailsx>\nx\n</details>")])
    }

    // MARK: Nesting (N2)

    private static func quoteDepth(_ blocks: [MarkdownBlock]) -> Int {
        blocks.map { block in
            if case .quote(let inner) = block { 1 + quoteDepth(inner) } else { 0 }
        }.max() ?? 0
    }

    @Test func deepQuotesAreCappedAndKeepTheRestAsText() {
        let blocks = parse(String(repeating: ">", count: 60_000) + " x")
        #expect(Self.quoteDepth(blocks) == MarkdownBlock.maxNesting)
        let twelve = parse(String(repeating: "> ", count: 12) + "x")
        var inner = twelve
        for _ in 0..<MarkdownBlock.maxNesting {
            guard case .quote(let next)? = inner.first else { Issue.record("expected a quote"); return }
            inner = next
        }
        #expect(inner == [.paragraph("> > > > x")])
    }

    @Test func deepListsAreCappedAndDeeperMarkersStayText() {
        let source = (0..<12).map { String(repeating: " ", count: $0 * 2) + "- l\($0)" }.joined(separator: "\n")
        guard case .list(let items)? = parse(source).first else { Issue.record("expected a list"); return }
        #expect(items.count == MarkdownBlock.maxNesting)
        #expect(items.map(\.indent) == Array(0..<MarkdownBlock.maxNesting))
        #expect(items.last?.text == "l7\n- l8\n- l9\n- l10\n- l11")
    }

    @Test func deepDetailsAreCappedAndKeepTheRestAsText() {
        let source = String(repeating: "<details>\n", count: 12) + "x\n" + String(repeating: "</details>\n", count: 12)
        var inner = parse(source)
        for _ in 0..<MarkdownBlock.maxNesting {
            guard case .details(_, let next, _)? = inner.first, inner.count == 1 else {
                Issue.record("expected one details section"); return
            }
            inner = next
        }
        #expect(inner == [.paragraph("<details>\n<details>\n<details>\n<details>\nx\n</details>\n</details>\n</details>\n</details>")])
    }

    @Test func detailsInsideAQuote() {
        #expect(parse("> <details>\n> <summary>A</summary>\n> x\n> </details>") == [
            .quote([.details(summary: "A", blocks: [.paragraph("x")], open: false)]),
        ])
    }

    // MARK: Size and speed (N1, N6)

    @Test func inputIsCappedAtGitHubsBodyLimit() {
        let blocks = parse(String(repeating: "a", count: 70_000))
        #expect(blocks == [.paragraph(String(repeating: "a", count: MarkdownBlock.maxInputLength))])
    }

    /// Each generator builds a hostile input from a repeat count `n`; the count below is the full-size case.
    typealias HostileInput = (name: String, full: Int, make: @Sendable (Int) -> String)

    static let hostileInputs: [HostileInput] = [
        ("spaces in a heading", 65_000, { "# a" + String(repeating: " ", count: $0) + "b" }),
        ("tabs in a heading", 32_000, { "# a" + String(repeating: " \t", count: $0) + "b #" }),
        ("quote markers", 65_000, { String(repeating: ">", count: $0) }),
        ("dashes", 65_000, { String(repeating: "-", count: $0) }),
        ("spaced dashes", 32_000, { String(repeating: "- ", count: $0) + "x" }),
        ("hashes", 65_000, { String(repeating: "#", count: $0) }),
        ("backticks", 65_000, { String(repeating: "`", count: $0) }),
        ("growing backtick runs", 350, { (1...$0).map { String(repeating: "`", count: $0) + "a" }.joined() }),
        ("comment openers", 16_000, { String(repeating: "<!--", count: $0) + "-->" }),
        ("comment lines", 13_000, { String(repeating: "<!--\n", count: $0) }),
        ("short lines", 32_000, { String(repeating: "a\n", count: $0) }),
        ("list lines", 16_000, { String(repeating: "- a\n", count: $0) }),
        ("lazy continuation", 32_000, { "- a\n" + String(repeating: "b\n", count: $0) }),
        ("nested list lines", 6_000, { (0..<$0).map { String(repeating: " ", count: $0 % 20) + "- a" }.joined(separator: "\n") }),
        ("fences", 16_000, { String(repeating: "```\n", count: $0) }),
        ("ordered markers", 21_000, { String(repeating: "1. ", count: $0) }),
        ("pipes", 65_000, { String(repeating: "|", count: $0) }),
        ("pipe rows", 8_000, { String(repeating: "|a|\n|-|\n", count: $0) }),
        ("wide table", 10_000, {
            String(repeating: "|a", count: $0) + "\n" + String(repeating: "|-", count: $0)
                + "\n" + String(repeating: "|`b`", count: $0 / 2)
        }),
        ("mismatched delimiters", 10_000, { String(repeating: "a|b\n-\n", count: $0) }),
        ("escaped pipes and backticks", 16_000, { String(repeating: "\\|`|", count: $0) }),
        ("details openers", 6_500, { String(repeating: "<details>\n", count: $0) }),
        ("nested details", 3_200, { String(repeating: "<details>\n", count: $0) + String(repeating: "</details>\n", count: $0) }),
        ("details closers", 5_900, { String(repeating: "</details>\n", count: $0) }),
        ("unclosed summaries", 6_000, { "<details>\n" + String(repeating: "<summary>\n", count: $0) + "</details>" }),
        ("details sections", 1_500, { String(repeating: "<details><summary>s</summary>\nx\n</details>\n", count: $0) }),
    ]

    /// The fastest of several runs of each size, which drops scheduler noise from parallel tests and busy CI
    /// runners. The sizes take turns, so a slow stretch slows both rather than skewing their ratio.
    private static func bestParseTimes(small: String, large: String) -> (small: Duration, large: Duration) {
        let clock = ContinuousClock()
        var best = (small: Duration.seconds(Int64.max), large: Duration.seconds(Int64.max))
        for _ in 0..<5 {
            best.small = min(best.small, clock.measure { _ = MarkdownBlock.parse(small) })
            best.large = min(best.large, clock.measure { _ = MarkdownBlock.parse(large) })
        }
        return best
    }

    /// Parsing 4x the input must cost well under the 16x a quadratic parser would. Linear is about 4x, so 10x
    /// leaves room for cache effects without hiding a super-linear pass. Judging the ratio rather than a fixed
    /// time keeps the test independent of machine speed. A run too short to time reliably passes outright.
    @Test(arguments: hostileInputs)
    func hostileInputScalesLinearly(input: HostileInput) {
        let (small, large) = Self.bestParseTimes(small: input.make(input.full / 4), large: input.make(input.full))
        #expect(large < .seconds(2), "\(input.name) took \(large)")
        guard large > .milliseconds(20) else { return }
        let ratio = large / max(small, .milliseconds(1))
        #expect(ratio < 10, "\(input.name) grew \(ratio)x for 4x the input (\(small) to \(large))")
    }
}

@Suite struct LinkPolicyTests {
    @Test func onlyWebSchemesOpen() {
        #expect(LinkPolicy.canOpen(URL(string: "https://github.com/o/r")!))
        #expect(LinkPolicy.canOpen(URL(string: "HTTP://example.com")!))
        #expect(!LinkPolicy.canOpen(URL(string: "file:///etc/passwd")!))
        #expect(!LinkPolicy.canOpen(URL(string: "x-apple.systempreferences:com.apple")!))
        #expect(!LinkPolicy.canOpen(URL(string: "javascript:alert(1)")!))
        #expect(!LinkPolicy.canOpen(URL(string: "/relative/path")!))
        #expect(!LinkPolicy.canOpen(URL(string: "mailto:a@b.c")!))
    }
}
