import Foundation
import Testing
@testable import PullBullKit

private typealias Comment = PullBullKit.Comment
private let start = Date(timeIntervalSince1970: 1_800_000_100)

private func comment(
    _ body: String, by author: String = "pb", at offset: TimeInterval = 5, id: String = "C1"
) -> Comment {
    Comment(id: id, author: author, body: body, createdAt: start.addingTimeInterval(offset))
}

@Suite struct CommentCheckTests {
    @Test func findsTheMatchingComment() {
        let landed = comment("Looks good", id: "C_landed")
        let comments = [comment("earlier", by: "alice", at: -300, id: "C0"), landed]
        #expect(CommentCheck.landed("Looks good", by: "pb", since: start, in: comments) == landed)
    }

    @Test func authorIsCaseInsensitive() {
        let landed = comment("Looks good", by: "PB")
        #expect(CommentCheck.landed("Looks good", by: "pb", since: start, in: [landed]) == landed)
    }

    @Test func ignoresAnotherAuthor() {
        let other = comment("Looks good", by: "alice")
        #expect(CommentCheck.landed("Looks good", by: "pb", since: start, in: [other]) == nil)
    }

    @Test func ignoresADifferentBody() {
        #expect(CommentCheck.landed("Looks good", by: "pb", since: start, in: [comment("Looks bad")]) == nil)
    }

    @Test func ignoresOneCreatedBeforeTheSkewAllowance() {
        #expect(CommentCheck.landed("Looks good", by: "pb", since: start, in: [comment("Looks good", at: -61)]) == nil)
        let skewed = comment("Looks good", at: -60)
        #expect(CommentCheck.landed("Looks good", by: "pb", since: start, in: [skewed]) == skewed)
    }

    @Test func trimsTheSentText() {
        let landed = comment("Looks good")
        #expect(CommentCheck.landed("  Looks good\n\n", by: "pb", since: start, in: [landed]) == landed)
    }

    @Test func lineEndingsAreNormalised() {
        let crlf = comment("one\r\ntwo")
        #expect(CommentCheck.landed("one\ntwo", by: "pb", since: start, in: [crlf]) == crlf)
        let lf = comment("one\ntwo")
        #expect(CommentCheck.landed("one\r\ntwo", by: "pb", since: start, in: [lf]) == lf)
    }
}
