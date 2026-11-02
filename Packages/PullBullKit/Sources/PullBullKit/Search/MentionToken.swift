import Foundation

/// The `@…` token ending at the caret in comment text. Offsets are UTF-16.
public struct MentionToken: Equatable, Sendable {
    public let range: Range<Int>
    public let prefix: String

    public static func at(_ text: String, caret: Int) -> MentionToken? {
        let units = Array(text.utf16)
        guard caret >= 0, caret <= units.count else { return nil }
        var slashes = 0
        var i = caret
        while i > 0 {
            let u = units[i - 1]
            if u == 0x40 {
                let start = i - 1
                guard start == 0 || opensToken(units[start - 1]) else { return nil }
                let prefix = String(decoding: units[i..<caret], as: UTF16.self)
                return MentionToken(range: start..<caret, prefix: prefix)
            }
            if u == 0x2F {
                slashes += 1
                if slashes > 1 { return nil }
            } else if !isNameUnit(u) {
                return nil
            }
            i -= 1
        }
        return nil
    }

    /// Replaces the token, and the rest of its name after the caret ("@da|na"), with "@<insert> " and
    /// returns the new text and caret. A space already after the name is reused rather than doubled.
    public func inserting(_ insert: String, into text: String) -> (text: String, caret: Int) {
        let edit = edit(inserting: insert, into: text)
        var units = Array(text.utf16)
        units.replaceSubrange(edit.range, with: Array(edit.replacement.utf16))
        return (String(decoding: units, as: UTF16.self), edit.caret)
    }

    /// `inserting` as one replacement, for a text view to apply with its undo: the UTF-16 range it
    /// replaces, the text put there, and the caret after it.
    public func edit(inserting insert: String, into text: String) -> (range: Range<Int>, replacement: String, caret: Int) {
        let units = Array(text.utf16)
        let lower = min(range.lowerBound, units.count)
        var upper = min(range.upperBound, units.count)
        var slashes = units[lower..<upper].filter { $0 == 0x2F }.count
        while upper < units.count {
            let u = units[upper]
            if u == 0x2F, slashes == 0 {
                slashes = 1
            } else if !Self.isNameUnit(u) {
                break
            }
            upper += 1
        }
        let replacement = "@\(insert)"
        let length = replacement.utf16.count
        if upper < units.count, units[upper] == 0x20 {
            return (lower..<upper, replacement, lower + length + 1)
        }
        return (lower..<upper, replacement + " ", lower + length + 1)
    }

    private static func isNameUnit(_ u: UInt16) -> Bool {
        switch u {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D: return true
        default: return false
        }
    }

    private static func opensToken(_ u: UInt16) -> Bool {
        switch u {
        case 0x20, 0x09, 0x0A, 0x0D, 0x28, 0x5B, 0x7B, 0x22, 0x27: return true
        default: return false
        }
    }
}
