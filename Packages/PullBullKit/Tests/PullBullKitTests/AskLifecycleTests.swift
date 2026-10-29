import Foundation
import Testing
@testable import PullBullKit

@MainActor
@Suite struct AskLifecycleTests {
    final class Runtime {
        let target: AskTarget
        init(target: AskTarget) { self.target = target }
    }

    /// Records opens, closes and file deletes; closes wait for `release()` while `holdsCloses` is on.
    @MainActor
    final class Harness {
        var opened: [Runtime] = []
        var closed: [Runtime] = []
        var fileExists = false
        var removals = 0
        /// A delete ran while a runtime was open.
        var removedUnderOpenIndex = false
        var failingTargets: Set<String> = []
        var holdsCloses = false
        var closing = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private(set) var lifecycle: AskLifecycle<Runtime>!

        init() {
            lifecycle = AskLifecycle(
                open: { [unowned self] target in
                    if self.failingTargets.contains(target.account.login) {
                        throw AskIndex.IndexError(message: "disk full")
                    }
                    let runtime = Runtime(target: target)
                    self.opened.append(runtime)
                    self.fileExists = true
                    return runtime
                },
                close: { [unowned self] runtime in
                    self.closing = true
                    if self.holdsCloses {
                        await withCheckedContinuation { self.waiting.append($0) }
                    }
                    self.closing = false
                    self.closed.append(runtime)
                },
                removeFiles: { [unowned self] in
                    if self.openCount > 0 { self.removedUnderOpenIndex = true }
                    self.removals += 1
                    self.fileExists = false
                })
        }

        var openCount: Int { opened.count - closed.count }

        func release() {
            holdsCloses = false
            waiting.forEach { $0.resume() }
            waiting = []
        }

        func waitUntilClosing() async {
            while !closing { await Task.yield() }
        }
    }

    let x = AskTarget(account: AccountRef(login: "me", source: .gh), scope: .org("acme"))
    let y = AskTarget(account: AccountRef(login: "me", source: .gh), scope: .personal(login: "me"))

    @Test func offOnOffOnLeavesOneRuntimeAndTheFile() async {
        let h = Harness()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        #expect(h.openCount == 1)

        h.holdsCloses = true
        h.lifecycle.update(wanted: x, enabled: false)
        await h.waitUntilClosing()
        h.lifecycle.update(wanted: x, enabled: true)
        h.lifecycle.update(wanted: x, enabled: false)
        h.lifecycle.update(wanted: x, enabled: true)
        h.release()
        await h.lifecycle.idle()

        #expect(h.openCount == 1)
        #expect(h.opened.count == 2)
        #expect(h.lifecycle.runtime === h.opened.last)
        #expect(h.lifecycle.openTarget == x)
        #expect(h.fileExists)
        #expect(h.removals == 0)
        #expect(!h.removedUnderOpenIndex)
    }

    /// Off and on again before the worker runs: the open index stays, and its file isn't deleted.
    @Test func offAndOnAtOnceKeepsTheOpenIndex() async {
        let h = Harness()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        let first = h.lifecycle.runtime
        h.lifecycle.update(wanted: x, enabled: false)
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        #expect(h.lifecycle.runtime === first)
        #expect(h.opened.count == 1)
        #expect(h.removals == 0)
        #expect(!h.removedUnderOpenIndex)
    }

    @Test func sameTargetAgainKeepsTheRuntime() async {
        let h = Harness()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        #expect(h.opened.count == 1)
        #expect(h.closed.isEmpty)
    }

    @Test func endingOffClosesFirstThenDeletes() async {
        let h = Harness()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        h.holdsCloses = true
        h.lifecycle.update(wanted: x, enabled: false)
        await h.waitUntilClosing()
        h.lifecycle.update(wanted: x, enabled: true)
        h.lifecycle.update(wanted: x, enabled: false)
        h.release()
        await h.lifecycle.idle()

        #expect(h.openCount == 0)
        #expect(h.lifecycle.runtime == nil)
        #expect(!h.fileExists)
        #expect(h.removals == 1)
        #expect(!h.removedUnderOpenIndex)
    }

    @Test func targetGoneAndBackBeforeTheOpenOpensOnce() async {
        let h = Harness()
        h.lifecycle.update(wanted: x, enabled: true)
        h.lifecycle.update(wanted: nil, enabled: true)
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        #expect(h.opened.count == 1)
        #expect(h.openCount == 1)

        // The same with a runtime open and its close still running.
        h.holdsCloses = true
        h.lifecycle.update(wanted: nil, enabled: true)
        await h.waitUntilClosing()
        h.lifecycle.update(wanted: x, enabled: true)
        h.release()
        await h.lifecycle.idle()
        #expect(h.openCount == 1)
        #expect(h.lifecycle.runtime === h.opened.last)
        #expect(h.fileExists)
    }

    @Test func signOutAfterRapidChangesClosesTheRuntime() async {
        let h = Harness()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        h.holdsCloses = true
        h.lifecycle.update(wanted: y, enabled: true)
        await h.waitUntilClosing()
        h.lifecycle.update(wanted: x, enabled: true)
        h.lifecycle.update(wanted: y, enabled: true)
        h.release()
        await h.lifecycle.idle()
        #expect(h.openCount == 1)
        #expect(h.lifecycle.openTarget == y)

        h.lifecycle.update(wanted: nil, enabled: true)
        await h.lifecycle.idle()
        #expect(h.openCount == 0)
        #expect(h.lifecycle.runtime == nil)
        // Signing out isn't turning Ask off: the delete is the caller's (`removeAll`).
        #expect(h.fileExists)
    }

    @Test func failedOpenIsNotRetriedUntilTheTargetChanges() async {
        let h = Harness()
        h.failingTargets = ["me"]
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        #expect(h.lifecycle.runtime == nil)
        #expect(h.opened.isEmpty)

        h.failingTargets = []
        h.lifecycle.update(wanted: x, enabled: true)
        await h.lifecycle.idle()
        #expect(h.lifecycle.runtime == nil)
        h.lifecycle.update(wanted: y, enabled: true)
        await h.lifecycle.idle()
        #expect(h.lifecycle.openTarget == y)
    }

    @Test func offAtLaunchDeletesNothing() async {
        let h = Harness()
        h.fileExists = true
        h.lifecycle.update(wanted: x, enabled: false)
        await h.lifecycle.idle()
        #expect(h.fileExists)
        #expect(h.opened.isEmpty)
    }
}
