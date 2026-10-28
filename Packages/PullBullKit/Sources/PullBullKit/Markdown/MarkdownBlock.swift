import Foundation

/// A block of GitHub-flavoured markdown, as PR descriptions and comments use it. Text inside a block is
/// still inline markdown (bold, code spans, links), rendered by the app per block.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    /// Lines joined with "\n"; GitHub shows single line breaks in PR text as breaks.
    case paragraph(String)
    case list([ListItem])
    case code(language: String?, text: String)
    case quote([MarkdownBlock])
    case rule
    case table(Table)
    /// A collapsible `<details>` section: its `<summary>` text (inline markdown, "Details" when missing),
    /// the blocks inside, and whether it starts expanded (`<details open>`).
    case details(summary: String, blocks: [MarkdownBlock], open: Bool)

    public struct ListItem: Equatable, Sendable {
        public enum Marker: Equatable, Sendable {
            case bullet
            case ordered(Int)
        }

        /// Nesting depth, 0 for a top-level item; below `maxNesting`.
        public let indent: Int
        public let marker: Marker
        /// nil for a plain item; true / false for a checked / unchecked task box.
        public let task: Bool?
        public let text: String

        public init(indent: Int, marker: Marker, task: Bool? = nil, text: String) {
            self.indent = indent
            self.marker = marker
            self.task = task
            self.text = text
        }
    }

    /// A GitHub table: a header row, a delimiter row that sets each column's alignment, and body rows.
    public struct Table: Equatable, Sendable {
        public enum Alignment: Equatable, Sendable {
            case leading
            case center
            case trailing
        }

        /// One per column; the same count as `header`.
        public let alignments: [Alignment]
        /// Header cell text, trimmed; still inline markdown.
        public let header: [String]
        /// Body rows, each with exactly `header.count` cells (short rows padded with "", extra cells dropped).
        public let rows: [[String]]

        /// Fits `alignments` and each row to `header.count`: short ones are padded with `.leading` / "",
        /// extras are dropped.
        public init(alignments: [Alignment], header: [String], rows: [[String]]) {
            self.alignments = TableRow.fitted(alignments, to: header.count, padding: .leading)
            self.header = header
            self.rows = rows.map { TableRow.fitted($0, to: header.count, padding: "") }
        }
    }

    /// Deepest quote, details or list nesting kept as structure; deeper markers stay as literal text.
    public static let maxNesting = 8
    /// GitHub's limit for a PR body or comment; longer input is cut here.
    public static let maxInputLength = 65_536
    /// Widest table kept; cells past this column are dropped.
    public static let maxTableColumns = 32

    /// Splits `source` into blocks in time linear in its length (no backtracking patterns). Complete HTML
    /// comments (the hidden hints in PR templates) are dropped, except inside code; an unclosed `<!--` stays
    /// as text, as does a `<details>` with no matching `</details>`. Never fails: anything unrecognised is a paragraph.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let capped = source.count > maxInputLength ? String(source.prefix(maxInputLength)) : source
        let normalized = capped.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var parser = BlockParser(lines: stripComments(lines), depth: 0)
        return parser.run()
    }
}

/// Which link schemes the detail view opens. PR text is untrusted: `file:`, app and script schemes never open.
public enum LinkPolicy {
    public static func canOpen(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || scheme == "http"
    }
}

// MARK: - Bytes

private let space = UInt8(ascii: " ")
private let tab = UInt8(ascii: "\t")
private let backtick = UInt8(ascii: "`")
private let tilde = UInt8(ascii: "~")
private let hash = UInt8(ascii: "#")
private let greater = UInt8(ascii: ">")
private let less = UInt8(ascii: "<")
private let pipe = UInt8(ascii: "|")
private let backslash = UInt8(ascii: "\\")
private let colon = UInt8(ascii: ":")
private let dash = UInt8(ascii: "-")

private func isSpaceOrTab(_ byte: UInt8) -> Bool { byte == space || byte == tab }

private func isBlank(_ line: Substring) -> Bool {
    line.utf8.allSatisfy { isSpaceOrTab($0) || $0 == 0x0B || $0 == 0x0C }
}

/// Leading indentation in columns (a tab counts as 4) and the text after it.
private func splitIndent(_ line: Substring) -> (Int, Substring) {
    var width = 0
    var index = line.utf8.startIndex
    while index < line.utf8.endIndex {
        let byte = line.utf8[index]
        if byte == space {
            width += 1
        } else if byte == tab {
            width += 4 - width % 4
        } else {
            break
        }
        index = line.utf8.index(after: index)
    }
    return (width, line[index...])
}

/// Drops `columns` of indentation from the start of `line` (fewer when the line has less).
private func dropIndent(_ line: Substring, columns: Int) -> Substring {
    var width = 0
    var index = line.utf8.startIndex
    while index < line.utf8.endIndex, width < columns {
        let byte = line.utf8[index]
        if byte == space {
            width += 1
        } else if byte == tab {
            width += 4 - width % 4
        } else {
            break
        }
        index = line.utf8.index(after: index)
    }
    return line[index...]
}

/// `text` without leading and trailing spaces and tabs.
private func trimmed(_ text: Substring) -> Substring {
    let utf8 = text.utf8
    var start = utf8.startIndex
    while start < utf8.endIndex, isSpaceOrTab(utf8[start]) { start = utf8.index(after: start) }
    var end = utf8.endIndex
    while end > start, isSpaceOrTab(utf8[utf8.index(before: end)]) { end = utf8.index(before: end) }
    return text[start..<end]
}

/// Number of leading bytes equal to `byte`, and the text after them.
private func run(of byte: UInt8, in text: Substring) -> (Int, Substring) {
    var count = 0
    var index = text.utf8.startIndex
    while index < text.utf8.endIndex, text.utf8[index] == byte {
        count += 1
        index = text.utf8.index(after: index)
    }
    return (count, text[index...])
}

private func startsWithSpaceOrTab(_ text: Substring) -> Bool {
    text.utf8.first.map(isSpaceOrTab) ?? false
}

// MARK: - Comments

extension MarkdownBlock {
    /// Drops complete HTML comments outside code: a comment block whose line starts with `<!--` (up to and
    /// including the line holding `-->`), and `<!-- … -->` within one line outside backtick code spans.
    /// Text after a block's `-->` stays. An unclosed `<!--` is literal text.
    static func stripComments(_ lines: [Substring]) -> [Substring] {
        // closing[i]: the first line at or after i that holds "-->", so finding a block's end is O(1).
        var closing = [Int?](repeating: nil, count: lines.count + 1)
        for index in stride(from: lines.count - 1, through: 0, by: -1) {
            closing[index] = lines[index].contains("-->") ? index : closing[index + 1]
        }
        var result: [Substring] = []
        result.reserveCapacity(lines.count)
        var fence: Fence?
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let open = fence {
                result.append(line)
                if open.isClosed(by: line) { fence = nil }
                index += 1
                continue
            }
            if let open = Fence(opening: line) {
                fence = open
                result.append(line)
                index += 1
                continue
            }
            let (indent, body) = splitIndent(line)
            if indent <= 3, body.hasPrefix("<!--") {
                let opener = body.dropFirst(4)
                let end: (line: Int, rest: Substring)?
                if let close = opener.range(of: "-->") {
                    end = (index, opener[close.upperBound...])
                } else if index + 1 < lines.count, let next = closing[index + 1],
                          let close = lines[next].range(of: "-->") {
                    end = (next, lines[next][close.upperBound...])
                } else {
                    end = nil
                }
                if let end {
                    if !isBlank(end.rest) { result.append(stripInlineComments(end.rest) ?? end.rest) }
                    index = end.line + 1
                    continue
                }
                result.append(line)
                index += 1
                continue
            }
            if indent <= 3, let stripped = stripInlineComments(line) {
                // A line that held only comments goes away rather than splitting the paragraph around it.
                if !isBlank(stripped) { result.append(stripped) }
            } else {
                result.append(line)
            }
            index += 1
        }
        return result
    }

    /// `line` without its complete `<!-- … -->` comments outside code spans, or nil when it has none.
    static func stripInlineComments(_ line: Substring) -> Substring? {
        let bytes = Array(line.utf8)
        guard bytes.count >= 7 else { return nil }
        // Every "-->" position, and every backtick run (start, length), each visited once by a cursor.
        var closers: [Int] = []
        var runs: [(start: Int, length: Int)] = []
        var position = 0
        while position < bytes.count {
            if bytes[position] == backtick {
                let start = position
                while position < bytes.count, bytes[position] == backtick { position += 1 }
                runs.append((start, position - start))
                continue
            }
            if position + 2 < bytes.count, bytes[position] == UInt8(ascii: "-"), bytes[position + 1] == UInt8(ascii: "-"),
               bytes[position + 2] == greater {
                closers.append(position)
            }
            position += 1
        }
        guard !closers.isEmpty else { return nil }
        // For each run, the index of the next run with the same length (its closing run), or nil.
        var matching = [Int?](repeating: nil, count: runs.count)
        var lastByLength: [Int: Int] = [:]
        for runIndex in stride(from: runs.count - 1, through: 0, by: -1) {
            matching[runIndex] = lastByLength[runs[runIndex].length]
            lastByLength[runs[runIndex].length] = runIndex
        }

        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var touched = false
        var runCursor = 0
        var closerCursor = 0
        position = 0
        while position < bytes.count {
            while runCursor < runs.count, runs[runCursor].start < position { runCursor += 1 }
            if runCursor < runs.count, runs[runCursor].start == position {
                let current = runs[runCursor]
                var end = position + current.length
                // A code span runs to the next run of the same length; its content is copied untouched.
                if let close = matching[runCursor] { end = runs[close].start + runs[close].length }
                output.append(contentsOf: bytes[position..<end])
                position = end
                continue
            }
            if bytes[position] == less, position + 3 < bytes.count, bytes[position + 1] == UInt8(ascii: "!"),
               bytes[position + 2] == UInt8(ascii: "-"), bytes[position + 3] == UInt8(ascii: "-") {
                while closerCursor < closers.count, closers[closerCursor] < position + 4 { closerCursor += 1 }
                guard closerCursor < closers.count else { break }
                position = closers[closerCursor] + 3
                touched = true
                continue
            }
            output.append(bytes[position])
            position += 1
        }
        if position < bytes.count { output.append(contentsOf: bytes[position...]) }
        return touched ? Substring(String(decoding: output, as: UTF8.self)) : nil
    }
}

// MARK: - Line kinds

struct Fence {
    let character: UInt8
    let length: Int
    let info: Substring

    /// "```lang" or "~~~", indented up to 3 spaces.
    init?(opening line: Substring) {
        let (indent, body) = splitIndent(line)
        guard indent <= 3, let first = body.utf8.first, first == backtick || first == tilde else { return nil }
        let (count, rest) = run(of: first, in: body)
        guard count >= 3 else { return nil }
        if first == backtick && rest.utf8.contains(backtick) { return nil }
        character = first
        length = count
        info = trimmed(rest)
    }

    func isClosed(by line: Substring) -> Bool {
        let (indent, body) = splitIndent(line)
        guard indent <= 3 else { return false }
        let (count, rest) = run(of: character, in: body)
        return count >= length && isBlank(rest)
    }

    var language: String? {
        let word = info.utf8.prefix { !isSpaceOrTab($0) }
        return word.isEmpty ? nil : String(Substring(word))
    }
}

private struct ListMarker {
    let column: Int
    let marker: MarkdownBlock.ListItem.Marker
    let content: Substring
}

private enum LineKind {
    static func atxHeading(_ line: Substring) -> MarkdownBlock? {
        let (indent, body) = splitIndent(line)
        guard indent <= 3 else { return nil }
        let (level, rest) = run(of: hash, in: body)
        guard (1...6).contains(level), rest.isEmpty || startsWithSpaceOrTab(rest) else { return nil }
        var text = trimmed(rest)
        // An optional closing run of "#", preceded by a space or tab (or making up the whole text).
        let utf8 = text.utf8
        var cut = utf8.endIndex
        while cut > utf8.startIndex, utf8[utf8.index(before: cut)] == hash { cut = utf8.index(before: cut) }
        if cut < utf8.endIndex, cut == utf8.startIndex || isSpaceOrTab(utf8[utf8.index(before: cut)]) {
            text = trimmed(text[..<cut])
        }
        return .heading(level: level, text: String(text))
    }

    static func setextLevel(_ line: Substring) -> Int? {
        let (indent, body) = splitIndent(line)
        guard indent <= 3, let first = body.utf8.first, first == UInt8(ascii: "=") || first == UInt8(ascii: "-")
        else { return nil }
        let (_, rest) = run(of: first, in: body)
        guard isBlank(rest) else { return nil }
        return first == UInt8(ascii: "=") ? 1 : 2
    }

    static func isRule(_ line: Substring) -> Bool {
        let (indent, body) = splitIndent(line)
        guard indent <= 3, let first = body.utf8.first,
              first == UInt8(ascii: "*") || first == UInt8(ascii: "-") || first == UInt8(ascii: "_")
        else { return false }
        var count = 0
        for byte in body.utf8 {
            if byte == first {
                count += 1
            } else if !isSpaceOrTab(byte) {
                return false
            }
        }
        return count >= 3
    }

    static func isQuote(_ line: Substring) -> Bool {
        let (indent, body) = splitIndent(line)
        return indent <= 3 && body.utf8.first == greater
    }

    static func listMarker(_ line: Substring) -> ListMarker? {
        let (column, body) = splitIndent(line)
        guard let first = body.utf8.first else { return nil }
        if first == UInt8(ascii: "-") || first == UInt8(ascii: "*") || first == UInt8(ascii: "+") {
            let rest = body.dropFirst()
            guard rest.isEmpty || startsWithSpaceOrTab(rest) else { return nil }
            return ListMarker(column: column, marker: .bullet, content: trimmed(rest))
        }
        var digits = 0
        var number = 0
        var index = body.utf8.startIndex
        while index < body.utf8.endIndex, digits < 10, let digit = digitValue(body.utf8[index]) {
            number = number * 10 + digit
            digits += 1
            index = body.utf8.index(after: index)
        }
        guard (1...9).contains(digits), index < body.utf8.endIndex,
              body.utf8[index] == UInt8(ascii: ".") || body.utf8[index] == UInt8(ascii: ")")
        else { return nil }
        let rest = body[body.utf8.index(after: index)...]
        guard rest.isEmpty || startsWithSpaceOrTab(rest) else { return nil }
        return ListMarker(column: column, marker: .ordered(number), content: trimmed(rest))
    }

    /// "[ ] text", "[x] text" or "[X] text": the box state and the text after it.
    static func task(_ content: Substring) -> (Bool, Substring)? {
        let utf8 = Array(content.utf8.prefix(4))
        guard utf8.count >= 3, utf8[0] == UInt8(ascii: "["), utf8[2] == UInt8(ascii: "]") else { return nil }
        let checked: Bool
        switch utf8[1] {
        case space: checked = false
        case UInt8(ascii: "x"), UInt8(ascii: "X"): checked = true
        default: return nil
        }
        let rest = content.dropFirst(3)
        guard rest.isEmpty || startsWithSpaceOrTab(rest) else { return nil }
        return (checked, trimmed(rest))
    }

    private static func digitValue(_ byte: UInt8) -> Int? {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") ? Int(byte - UInt8(ascii: "0")) : nil
    }
}

// MARK: - Details

private enum DetailsTag {
    private static let detailsName = Array("<details".utf8)
    private static let summaryName = Array("<summary".utf8)
    private static let closing = Array("</details>".utf8)

    /// "<details>", "<details open>" or "<details …attributes…>" (any case) starting a line indented up to 3:
    /// whether it has the `open` attribute, and the text after the tag.
    static func opening(_ line: Substring) -> (open: Bool, rest: Substring)? {
        let (indent, body) = splitIndent(line)
        guard indent <= 3, let (attributes, rest) = tag(detailsName, in: body) else { return nil }
        let open = attributes.split(whereSeparator: { $0 == " " || $0 == "\t" }).contains { attribute in
            attribute.prefix { $0 != "=" }.lowercased() == "open"
        }
        return (open, rest)
    }

    /// "<summary>" (any case, attributes allowed) at the start of `text`: the text after it.
    static func summaryStart(_ text: Substring) -> Substring? {
        tag(summaryName, in: trimmed(text))?.rest
    }

    /// Where each opening line's matching closing line is, counting nested sections and skipping fenced code.
    /// Unmatched openers are absent. One pass with a stack, so linear in the line count.
    static func closers(_ lines: [Substring]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var open: [Int] = []
        var fence: Fence?
        for (index, line) in lines.enumerated() {
            // Only a fence or a tag line matters here, and each starts with one of these bytes.
            let (indent, body) = splitIndent(line)
            guard indent <= 3, let first = body.utf8.first, first == less || first == backtick || first == tilde
            else { continue }
            if let current = fence {
                if current.isClosed(by: line) { fence = nil }
            } else if first != less {
                fence = Fence(opening: line)
            } else if tag(detailsName, in: body) != nil {
                open.append(index)
            } else if isClosing(body), let opener = open.popLast() {
                result[opener] = index
            }
        }
        return result
    }

    /// Whether `body` (a line after its indentation) is only "</details>" in any case, with trailing space.
    private static func isClosing(_ body: Substring) -> Bool {
        let text = trimmed(body)
        return text.utf8.count == closing.count && startsWith(text, closing)
    }

    /// `<name …>` at the start of `text`: the attributes between the name and ">", and the text after ">".
    private static func tag(_ name: [UInt8], in text: Substring) -> (attributes: Substring, rest: Substring)? {
        guard startsWith(text, name) else { return nil }
        let afterName = text.utf8.index(text.utf8.startIndex, offsetBy: name.count)
        guard afterName < text.utf8.endIndex else { return nil }
        let next = text.utf8[afterName]
        guard next == greater || isSpaceOrTab(next),
              let close = text.utf8[afterName...].firstIndex(of: greater)
        else { return nil }
        return (text[afterName..<close], text[text.utf8.index(after: close)...])
    }

    /// Whether `text` starts with the lowercase bytes `prefix`, ignoring ASCII case.
    private static func startsWith(_ text: Substring, _ prefix: [UInt8]) -> Bool {
        var index = text.utf8.startIndex
        for byte in prefix {
            guard index < text.utf8.endIndex else { return false }
            var actual = text.utf8[index]
            if actual >= UInt8(ascii: "A"), actual <= UInt8(ascii: "Z") { actual += 32 }
            guard actual == byte else { return false }
            index = text.utf8.index(after: index)
        }
        return true
    }
}

// MARK: - Tables

private enum TableRow {
    /// A row's cells, split on `|` except `\|` (kept as `|`) and pipes inside backtick code spans, without
    /// one leading and one trailing pipe, each trimmed. `hasPipe` is false when nothing split the line, so
    /// the whole line is one cell.
    static func cells(_ line: Substring) -> (cells: [String], hasPipe: Bool) {
        let bytes = Array(trimmed(line).utf8)
        // Every backtick run (start, length), and for each the next run with the same length (its closing run).
        var runs: [(start: Int, length: Int)] = []
        var position = 0
        while position < bytes.count {
            guard bytes[position] == backtick else {
                position += 1
                continue
            }
            let start = position
            while position < bytes.count, bytes[position] == backtick { position += 1 }
            runs.append((start, position - start))
        }
        var matching = [Int?](repeating: nil, count: runs.count)
        var lastByLength: [Int: Int] = [:]
        for runIndex in stride(from: runs.count - 1, through: 0, by: -1) {
            matching[runIndex] = lastByLength[runs[runIndex].length]
            lastByLength[runs[runIndex].length] = runIndex
        }

        var cells: [String] = []
        var cell: [UInt8] = []
        var hasPipe = false
        var endsWithPipe = false
        var runCursor = 0
        position = 0
        while position < bytes.count {
            let byte = bytes[position]
            endsWithPipe = false
            if byte == backtick {
                while runCursor < runs.count, runs[runCursor].start < position { runCursor += 1 }
                var end = position + 1
                if runCursor < runs.count, runs[runCursor].start == position {
                    end = position + runs[runCursor].length
                    // A code span runs to the next run of the same length; its pipes do not split the row.
                    if let close = matching[runCursor] { end = runs[close].start + runs[close].length }
                }
                appendUnescaped(bytes[position..<end], to: &cell)
                position = end
            } else if byte == backslash, position + 1 < bytes.count {
                if bytes[position + 1] != pipe { cell.append(byte) }
                cell.append(bytes[position + 1])
                position += 2
            } else if byte == pipe {
                cells.append(finish(cell))
                cell = []
                hasPipe = true
                endsWithPipe = true
                position += 1
            } else {
                cell.append(byte)
                position += 1
            }
        }
        cells.append(finish(cell))
        if bytes.first == pipe { cells.removeFirst() }
        if endsWithPipe, !cells.isEmpty { cells.removeLast() }
        return (cells, hasPipe)
    }

    /// A delimiter row's column alignments: cells of `-` with optional `:` at either end, separated by `|`.
    /// nil for any other line, and for a line that is a setext underline or a list item, which win over a table.
    static func alignments(_ line: Substring) -> [MarkdownBlock.Table.Alignment]? {
        let (indent, body) = splitIndent(line)
        guard indent <= 3, LineKind.setextLevel(line) == nil, LineKind.listMarker(line) == nil else { return nil }
        guard body.utf8.allSatisfy({ $0 == pipe || $0 == colon || $0 == dash || isSpaceOrTab($0) }) else {
            return nil
        }
        var text = trimmed(body)
        if text.utf8.first == pipe { text = text.dropFirst() }
        if text.utf8.last == pipe { text = text.dropLast() }
        var result: [MarkdownBlock.Table.Alignment] = []
        for cell in text.split(separator: "|", omittingEmptySubsequences: false) {
            let bytes = trimmed(cell).utf8
            let left = bytes.first == colon
            let right = bytes.count > 1 && bytes.last == colon
            let dashes = bytes.dropFirst(left ? 1 : 0).dropLast(right ? 1 : 0)
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == dash }) else { return nil }
            result.append(left && right ? .center : right ? .trailing : .leading)
        }
        return result
    }

    /// `cells` padded with `padding` or cut to exactly `count`.
    static func fitted<Cell>(_ cells: [Cell], to count: Int, padding: Cell) -> [Cell] {
        cells.count >= count ? Array(cells.prefix(count)) : cells + Array(repeating: padding, count: count - cells.count)
    }

    private static func appendUnescaped(_ bytes: ArraySlice<UInt8>, to cell: inout [UInt8]) {
        var index = bytes.startIndex
        while index < bytes.endIndex {
            if bytes[index] == backslash, index + 1 < bytes.endIndex, bytes[index + 1] == pipe {
                cell.append(pipe)
                index += 2
            } else {
                cell.append(bytes[index])
                index += 1
            }
        }
    }

    private static func finish(_ cell: [UInt8]) -> String {
        String(trimmed(Substring(String(decoding: cell, as: UTF8.self))))
    }
}

// MARK: - Parsing

private struct ItemBuilder {
    let indent: Int
    let marker: MarkdownBlock.ListItem.Marker
    let task: Bool?
    var lines: [Substring]

    var item: MarkdownBlock.ListItem {
        .init(indent: indent, marker: marker, task: task, text: lines.joined(separator: "\n"))
    }
}

private struct BlockParser {
    let lines: [Substring]
    /// Quote and details nesting of these lines; at `maxNesting` a ">" or `<details>` no longer opens one.
    let depth: Int
    /// The closing line of each `<details>` line that has one; worked out when the first such line is reached.
    var detailsClosers: [Int: Int]?
    var index = 0
    var blocks: [MarkdownBlock] = []
    var paragraph: [Substring] = []
    var items: [ItemBuilder] = []
    /// Marker columns of the open list items, outermost first; their count is the next item's depth.
    var columns: [Int] = []
    var blankSinceItem = false

    init(lines: [Substring], depth: Int) {
        self.lines = lines
        self.depth = depth
    }

    mutating func run() -> [MarkdownBlock] {
        while index < lines.count {
            let line = lines[index]
            if isBlank(line) {
                flushParagraph()
                if !items.isEmpty { blankSinceItem = true }
                index += 1
            } else if let fence = Fence(opening: line) {
                flushAll()
                readFence(fence)
            } else if paragraph.isEmpty, items.isEmpty, splitIndent(line).0 >= 4 {
                readIndentedCode()
            } else if depth < MarkdownBlock.maxNesting, let opening = DetailsTag.opening(line),
                      let end = closingLine(of: index) {
                flushAll()
                readDetails(open: opening.open, rest: opening.rest, end: end)
            } else if let heading = LineKind.atxHeading(line) {
                flushAll()
                blocks.append(heading)
                index += 1
            } else if !paragraph.isEmpty, let level = LineKind.setextLevel(line) {
                let text = paragraph.joined(separator: " ")
                paragraph = []
                flushList()
                blocks.append(.heading(level: level, text: text))
                index += 1
            } else if LineKind.isRule(line) {
                flushAll()
                blocks.append(.rule)
                index += 1
            } else if depth < MarkdownBlock.maxNesting, LineKind.isQuote(line) {
                flushAll()
                readQuote()
            } else if let item = LineKind.listMarker(line), paragraph.isEmpty || Self.canInterruptParagraph(item) {
                flushParagraph()
                addItem(item, line: line)
                index += 1
            } else if let (header, alignments) = tableStart() {
                flushAll()
                readTable(header: header, alignments: alignments)
            } else if !items.isEmpty, !blankSinceItem || splitIndent(line).0 >= 2 {
                continueItem(line)
                index += 1
            } else {
                flushList()
                paragraph.append(trimmed(line))
                index += 1
            }
        }
        flushAll()
        return blocks
    }

    // MARK: Blocks

    private mutating func readFence(_ fence: Fence) {
        let indent = splitIndent(lines[index]).0
        index += 1
        var body: [Substring] = []
        while index < lines.count, !fence.isClosed(by: lines[index]) {
            body.append(dropIndent(lines[index], columns: indent))
            index += 1
        }
        index += 1
        blocks.append(.code(language: fence.language, text: body.joined(separator: "\n")))
    }

    private mutating func readIndentedCode() {
        var body: [Substring] = []
        while index < lines.count, isBlank(lines[index]) || splitIndent(lines[index]).0 >= 4 {
            body.append(isBlank(lines[index]) ? "" : dropIndent(lines[index], columns: 4))
            index += 1
        }
        while body.last?.isEmpty == true { body.removeLast() }
        blocks.append(.code(language: nil, text: body.joined(separator: "\n")))
    }

    /// The quoted lines, with one ">" (and one following space) removed, as views into the same text.
    private mutating func readQuote() {
        var inner: [Substring] = []
        while index < lines.count, LineKind.isQuote(lines[index]) {
            var rest = splitIndent(lines[index]).1.dropFirst()
            if rest.utf8.first == space { rest = rest.dropFirst() }
            inner.append(rest)
            index += 1
        }
        var parser = BlockParser(lines: inner, depth: depth + 1)
        blocks.append(.quote(parser.run()))
    }

    private mutating func closingLine(of opener: Int) -> Int? {
        if detailsClosers == nil { detailsClosers = DetailsTag.closers(lines) }
        return detailsClosers?[opener]
    }

    /// A `<details>` section up to its closing line `end`: the summary on the opening line or on the lines
    /// before the content, then the lines between parsed as blocks one level deeper.
    private mutating func readDetails(open: Bool, rest: Substring, end: Int) {
        index += 1
        var summary: [Substring] = []
        var inner: [Substring] = []
        var first = rest
        if isBlank(first) {
            while index < end, isBlank(lines[index]) { index += 1 }
            if index < end, splitIndent(lines[index]).0 <= 3, DetailsTag.summaryStart(lines[index]) != nil {
                first = lines[index]
                index += 1
            }
        }
        if let text = DetailsTag.summaryStart(first) {
            // The summary may span lines; without a "</summary>" before `end` its lines stay as content.
            var parts: [Substring] = [text]
            var cursor = index
            while true {
                if let close = parts[parts.count - 1].range(of: "</summary>", options: .caseInsensitive) {
                    let last = parts[parts.count - 1]
                    parts[parts.count - 1] = last[..<close.lowerBound]
                    summary = parts
                    index = cursor
                    first = last[close.upperBound...]
                    break
                }
                guard cursor < end else { break }
                parts.append(lines[cursor])
                cursor += 1
            }
        }
        if !isBlank(first) { inner.append(first) }
        inner.append(contentsOf: lines[index..<end])
        index = end + 1
        let title = summary.map { trimmed($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        var parser = BlockParser(lines: inner, depth: depth + 1)
        blocks.append(.details(summary: title.isEmpty ? "Details" : title, blocks: parser.run(), open: open))
    }

    /// The header cells and alignments when the current line is a table header: it has a separating pipe,
    /// and the next line is a delimiter row with the same number of cells.
    private func tableStart() -> (header: [String], alignments: [MarkdownBlock.Table.Alignment])? {
        let line = lines[index]
        guard index + 1 < lines.count, splitIndent(line).0 <= 3, line.utf8.contains(pipe),
              let alignments = TableRow.alignments(lines[index + 1])
        else { return nil }
        let (header, hasPipe) = TableRow.cells(line)
        guard hasPipe, header.count == alignments.count else { return nil }
        return (header, alignments)
    }

    /// The header, delimiter and body rows: lines up to a blank line or one that starts another block.
    private mutating func readTable(header: [String], alignments: [MarkdownBlock.Table.Alignment]) {
        let columns = min(header.count, MarkdownBlock.maxTableColumns)
        index += 2
        var rows: [[String]] = []
        while index < lines.count, !isBlank(lines[index]), !Self.startsBlock(lines[index]),
              DetailsTag.opening(lines[index]) == nil {
            rows.append(TableRow.fitted(TableRow.cells(lines[index]).cells, to: columns, padding: ""))
            index += 1
        }
        blocks.append(.table(.init(
            alignments: Array(alignments.prefix(columns)), header: Array(header.prefix(columns)), rows: rows)))
    }

    private static func startsBlock(_ line: Substring) -> Bool {
        Fence(opening: line) != nil || LineKind.atxHeading(line) != nil || LineKind.isRule(line)
            || LineKind.isQuote(line) || LineKind.listMarker(line) != nil
    }

    // MARK: Lists

    private mutating func addItem(_ marker: ListMarker, line: Substring) {
        // `columns` is increasing, so the depth is the count of open items left of this marker.
        let depth = columns.firstIndex { $0 >= marker.column } ?? columns.count
        guard depth < MarkdownBlock.maxNesting else {
            continueItem(line)
            return
        }
        columns.removeSubrange(depth...)
        columns.append(marker.column)
        var task: Bool?
        var text = marker.content
        if let (checked, rest) = LineKind.task(text) {
            task = checked
            text = rest
        }
        items.append(ItemBuilder(indent: depth, marker: marker.marker, task: task, lines: text.isEmpty ? [] : [text]))
        blankSinceItem = false
    }

    private mutating func continueItem(_ line: Substring) {
        guard !items.isEmpty else { return }
        items[items.count - 1].lines.append(trimmed(line))
        blankSinceItem = false
    }

    // MARK: Flushing

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(paragraph.joined(separator: "\n")))
        paragraph = []
    }

    private mutating func flushList() {
        guard !items.isEmpty else { return }
        blocks.append(.list(items.map(\.item)))
        items = []
        columns = []
        blankSinceItem = false
    }

    private mutating func flushAll() {
        flushParagraph()
        flushList()
    }

    /// A bullet, or a numbered item starting at 1, can start a list right after a paragraph line;
    /// "2024. Really." in running text cannot.
    private static func canInterruptParagraph(_ item: ListMarker) -> Bool {
        switch item.marker {
        case .bullet: !item.content.isEmpty
        case .ordered(let n): n == 1 && !item.content.isEmpty
        }
    }
}
