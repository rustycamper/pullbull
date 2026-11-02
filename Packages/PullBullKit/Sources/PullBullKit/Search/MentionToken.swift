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

    /// Replaces the token with "@<insert> " and returns the new text and caret.
    /// A space already after the token is reused rather than doubled.
    public func inserting(_ insert: String, into text: String) -> (text: String, caret: Int) {
        let units = Array(text.utf16)
        let lower = min(range.lowerBound, units.count)
        let upper = min(range.upperBound, units.count)
        let replacement = Array("@\(insert)".utf16)
        let hasSpace = upper < units.count && units[upper] == 0x20
        var out = Array(units[..<lower]) + replacement
        let caret: Int
        if hasSpace {
            caret = out.count + 1
        } else {
            out.append(0x20)
            caret = out.count
        }
        out += units[upper...]
        return (String(decoding: out, as: UTF16.self), caret)
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
