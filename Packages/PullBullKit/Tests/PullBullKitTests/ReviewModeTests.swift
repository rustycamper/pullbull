import Foundation
import Testing
@testable import PullBullKit

private let key = PRKey(repo: "acme/app", number: 88)

private func detail(
    head: String? = "abcdef123456", author: String? = "sam", state: PRState? = .open, ci: CIState? = .success,
    checks: [Check] = [], files: Int? = 5, additions: Int? = 120, deletions: Int? = 3
) -> PRDetail {
    PRDetail(
        key: key, body: "", checks: checks, reviews: [], comments: [], files: [], ci: ci,
        changedFiles: files, additions: additions, deletions: deletions,
        headOid: head, author: author, state: state)
}

@Suite struct ReviewModeTests {
    @Test func opensOnApprove() {
        let mode = ReviewMode(key: key, head: "abc", lastReview: nil)
        #expect(mode.verdict == .approve)
        #expect(mode.phase == .composing)
        #expect(!mode.missingText)
        #expect(ReviewMode(key: key, head: "abc", lastReview: .approved).verdict == .approve)
    }

    @Test func opensOnRequestChangesAfterRequestingChanges() {
        #expect(ReviewMode(key: key, head: "abc", lastReview: .changesRequested).verdict == .requestChanges)
    }

    @Test func toggleClearsMissingText() {
        var mode = ReviewMode(key: key, head: "abc", lastReview: nil)
        mode.missingText = true
        mode.toggleVerdict()
        #expect(mode.verdict == .requestChanges)
        #expect(!mode.missingText)
        mode.toggleVerdict()
        #expect(mode.verdict == .approve)
    }

    @Test func verdictLocksOnceSubmitted() {
        for phase in [ReviewPhase.checking, .sending] {
            var mode = ReviewMode(key: key, head: "abc", lastReview: nil)
            mode.phase = phase
            mode.missingText = true
            mode.toggleVerdict()
            #expect(mode.verdict == .approve)
            #expect(mode.missingText)
        }
    }

    @Test func pinIgnoresNewerDetail() {
        let mode = ReviewMode(key: key, head: "abcdef123456", lastReview: nil)
        let newer = detail(head: "999999999999")
        #expect(ReviewSummary(head: mode.head, detail: newer).text.hasPrefix("abcdef1"))
    }

    @Test func cancelAndVerdictFollowPhase() {
        var mode = ReviewMode(key: key, head: "abc", lastReview: nil)
        #expect(mode.canCancel && mode.canChangeVerdict)
        mode.phase = .checking
        #expect(mode.canCancel && !mode.canChangeVerdict)
        mode.phase = .sending
        #expect(!mode.canCancel && !mode.canChangeVerdict)
    }

    @Test func gate() {
        let ok = detail()
        #expect(ReviewGate.canReview(detail: ok, viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: detail(state: .merged), viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: detail(state: .closed), viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: detail(author: "pb"), viewer: "PB", permission: .ready))
        #expect(!ReviewGate.canReview(detail: detail(head: nil), viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: detail(author: nil), viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: detail(state: nil), viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: nil, viewer: "me", permission: .ready))
        #expect(!ReviewGate.canReview(detail: ok, viewer: nil, permission: .ready))
        #expect(!ReviewGate.canReview(detail: ok, viewer: "me", permission: .unavailable))
        #expect(!ReviewGate.canReview(detail: ok, viewer: "me", permission: .needsGhScope(command: "x")))
    }

    @Test func whitespaceIsNoTextForRequestChanges() {
        #expect(!ReviewGate.canSubmit(.requestChanges, text: " \n"))
        #expect(ReviewGate.canSubmit(.requestChanges, text: "fix it"))
        #expect(ReviewGate.canSubmit(.approve, text: ""))
    }

    @Test func summaryLine() {
        let head = "abcdef123456"
        let passed = ReviewSummary(head: head, detail: detail())
        #expect(passed.text == "abcdef1 · 5 files +120 −3 · checks passed")
        #expect(passed.checks == "checks passed")
        #expect(!passed.warns)

        let failing = [Check(name: "a", state: .failure, url: nil), Check(name: "b", state: .cancelled, url: nil),
                       Check(name: "c", state: .success, url: nil)]
        let failed = ReviewSummary(head: head, detail: detail(ci: .failure, checks: failing))
        #expect(failed.text == "abcdef1 · 5 files +120 −3 · 2 checks failing")
        #expect(failed.warns)

        let one = ReviewSummary(head: head, detail: detail(ci: .failure, checks: [failing[0]]))
        #expect(one.checks == "1 check failing")

        let unheld = ReviewSummary(head: head, detail: detail(ci: .failure))
        #expect(unheld.checks == "checks failing")

        let pending = ReviewSummary(head: head, detail: detail(ci: .pending))
        #expect(pending.text == "abcdef1 · 5 files +120 −3 · checks running")
        #expect(pending.warns)

        let none = ReviewSummary(head: head, detail: detail(ci: CIState.none, files: 1))
        #expect(none.text == "abcdef1 · 1 file +120 −3")
        #expect(none.checks == nil)
        #expect(!none.warns)
    }
}
