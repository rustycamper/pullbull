import Foundation
import Testing
@testable import PullBullKit

@Suite struct MergeModeTests {
    private let key = PRKey(repo: "o/r", number: 88)
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func info(
        methods: [MergeMethod] = [.squash], defaultMethod: MergeMethod? = nil, base: String = "main",
        commits: Int = 3, approvals: Int = 2, failing: Int = 0, running: Int = 0, total: Int = 12,
        changes: Bool = false
    ) -> MergeInfo {
        MergeInfo(
            nodeID: "PR_1", status: .clean, hasConflicts: false, usesMergeQueue: false, isStacked: false,
            isDraft: false, autoMerge: nil, canEnableAutoMerge: false, canDisableAutoMerge: false,
            canWrite: true, allowedMethods: methods, defaultMethod: defaultMethod ?? methods.first, base: base,
            commitCount: commits, approvals: approvals,
            tally: CheckTally(failing: failing, running: running, total: total), changesRequested: changes)
    }

    private func detail(_ info: MergeInfo?, head: String? = "abc", state: PRState? = .open) -> PRDetail {
        PRDetail(key: key, body: "", checks: [], reviews: [], comments: [], files: [], headOid: head, state: state, merge: info)
    }

    private func read(
        _ info: MergeInfo, offer: MergeOffer = .action(.merge), head: String? = "abc"
    ) -> MergeRead {
        MergeRead(detail: detail(info, head: head), offer: offer)
    }

    private func shown(_ info: MergeInfo, offer: MergeOffer = .action(.merge)) -> MergeMode {
        var mode = MergeMode(key: key, pinnedHead: "abc")
        mode.show(read(info, offer: offer), at: t0)
        return mode
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func press(_ mode: inout MergeMode, _ now: Date) -> Bool { mode.confirm(at: now) }

    @Test func confirmIsDisarmedForHalfASecond() {
        let mode = shown(info())
        #expect(!mode.canConfirm(at: at(0.4)))
        #expect(mode.canConfirm(at: at(0.5)))
    }

    @Test func confirmDoesNothingWhileReading() {
        var mode = MergeMode(key: key, pinnedHead: "abc")
        #expect(!mode.canConfirm(at: at(10)))
        #expect(!press(&mode, at(10)))
        #expect(mode.phase == .reading)
    }

    @Test func confirmDoesNothingWhileConfirming() {
        var mode = shown(info())
        mode.phase = .confirming
        #expect(!press(&mode, at(5)))
        #expect(mode.phase == .confirming)
    }

    @Test func confirmMovesToConfirming() {
        var mode = shown(info())
        #expect(press(&mode, at(0.5)))
        #expect(mode.phase == .confirming)
    }

    @Test func aChangedSentenceDisarmsAgain() {
        var mode = shown(info(methods: [.merge, .squash]))
        mode.changeMethod(by: 1, at: at(2))
        #expect(!mode.canConfirm(at: at(2.4)))
        #expect(mode.canConfirm(at: at(2.5)))

        mode.show(read(info(methods: [.merge, .squash], base: "dev")), at: at(5))
        #expect(!mode.canConfirm(at: at(5.4)))
        #expect(mode.canConfirm(at: at(5.5)))
    }

    @Test func aTallyOnlyChangeDisarmsAgain() {
        var mode = shown(info())
        mode.show(read(info(failing: 1)), at: at(3))
        #expect(!mode.canConfirm(at: at(3.4)))
        #expect(mode.canConfirm(at: at(3.5)))
    }

    @Test func showClearsTheSecondStep() {
        var mode = shown(info(running: 1))
        #expect(!press(&mode, at(1)))
        #expect(mode.isSecondStep)
        mode.show(read(info(failing: 1)), at: at(5))
        #expect(!mode.isSecondStep)
        #expect(mode.confirmTitle == "Merge")
        #expect(!press(&mode, at(6)))
        #expect(mode.isSecondStep)
        #expect(press(&mode, at(7)))
    }

    @Test func showKeepsAChosenMethod() {
        var mode = shown(info(methods: [.merge, .squash, .rebase], defaultMethod: .merge))
        #expect(mode.method == .merge)
        mode.changeMethod(by: 1, at: at(1))
        mode.show(read(info(methods: [.merge, .squash, .rebase], defaultMethod: .merge)), at: at(2))
        #expect(mode.method == .squash)
    }

    @Test func showFallsBackWhenTheMethodIsGone() {
        var mode = shown(info(methods: [.merge, .squash, .rebase], defaultMethod: .rebase))
        mode.changeMethod(by: -1, at: at(1))
        #expect(mode.method == .squash)
        mode.show(read(info(methods: [.merge, .rebase], defaultMethod: .rebase)), at: at(2))
        #expect(mode.method == .rebase)
        mode.show(read(info(methods: [.merge, .squash], defaultMethod: .rebase)), at: at(3))
        #expect(mode.method == .merge)
    }

    @Test func thePanelReadsOnlyWhatWasShown() {
        var mode = shown(info())
        let newer = read(info(base: "dev", failing: 5, changes: true))
        #expect(mode.warnings.isEmpty)
        #expect(mode.sentence == "Squash and merge #88 into main")
        #expect(mode.summary == "3 commits · 2 approvals · 12 checks passing")
        #expect(mode.read != newer)

        mode.show(newer, at: at(1))
        #expect(mode.warnings == [.checksFailing(5), .changesRequested])
        #expect(mode.sentence == "Squash and merge #88 into dev")
        #expect(mode.summary == "3 commits · 2 approvals · 5 of 12 checks failing")
    }

    @Test func failingAndRunningShowOnlyFailingInTheSummary() {
        let mode = shown(info(failing: 2, running: 3))
        #expect(mode.summary == "3 commits · 2 approvals · 2 of 12 checks failing")
        #expect(mode.warnings == [.checksFailing(2), .checksRunning(3)])
    }

    @Test func warningsNeedASecondStep() {
        var mode = shown(info(failing: 1))
        #expect(mode.confirmTitle == "Merge")
        #expect(!press(&mode, at(1)))
        #expect(mode.phase == .ready)
        #expect(mode.confirmTitle == "Merge anyway")
        #expect(press(&mode, at(2)))
        #expect(mode.phase == .confirming)
    }

    @Test func secondStepWaitsASecond() {
        var mode = shown(info(failing: 1))
        #expect(!press(&mode, at(1)))
        #expect(!press(&mode, at(1.9)))
        #expect(mode.isSecondStep)
        #expect(mode.phase == .ready)
        #expect(press(&mode, at(2)))
    }

    @Test func noWarningsSendOnTheFirstConfirm() {
        var mode = shown(info())
        #expect(mode.warnings.isEmpty)
        #expect(press(&mode, at(0.5)))
    }

    @Test func eachWarningIsRaised() {
        #expect(shown(info(failing: 2)).warnings == [.checksFailing(2)])
        #expect(shown(info(running: 3)).warnings == [.checksRunning(3)])
        #expect(shown(info(total: 0)).warnings == [.noChecks])
        #expect(shown(info(changes: true)).warnings == [.changesRequested])
        #expect(shown(info(failing: 1, running: 1, changes: true)).warnings
            == [.checksFailing(1), .checksRunning(1), .changesRequested])
    }

    @Test func whenReadyNeverNeedsASecondStep() {
        var mode = shown(info(failing: 1, running: 1, total: 0, changes: true), offer: .action(.mergeWhenReady))
        #expect(mode.warnings.isEmpty)
        #expect(press(&mode, at(0.5)))
    }

    @Test func changingMethodResetsTheSecondStep() {
        var mode = shown(info(methods: [.merge, .squash], failing: 1))
        #expect(!press(&mode, at(1)))
        mode.changeMethod(by: 1, at: at(2))
        #expect(!mode.isSecondStep)
        #expect(mode.method == .squash)
        mode.changeMethod(by: 1, at: at(3))
        #expect(mode.method == .merge)
    }

    @Test func oneMethodDoesNothingOnChange() {
        var mode = shown(info(methods: [.squash], failing: 1))
        #expect(!press(&mode, at(1)))
        mode.changeMethod(by: 1, at: at(1.2))
        #expect(mode.method == .squash)
        #expect(mode.isSecondStep)
        #expect(mode.canConfirm(at: at(2.2)))
    }

    @Test func sentenceNamesMethodAndBase() {
        var mode = shown(info(methods: [.merge, .squash, .rebase], defaultMethod: .merge))
        #expect(mode.sentence == "Merge #88 into main")
        mode.changeMethod(by: 1, at: at(1))
        #expect(mode.sentence == "Squash and merge #88 into main")
        mode.changeMethod(by: 1, at: at(1))
        #expect(mode.sentence == "Rebase and merge #88 into main")
        #expect(shown(info(), offer: .action(.mergeWhenReady)).sentence == "Merge #88 into main when its requirements pass")
        #expect(shown(info(), offer: .hidden).sentence == nil)
    }

    @Test func summaryMatchesTheCopy() {
        #expect(shown(info(failing: 1)).summary == "3 commits · 2 approvals · 1 of 12 checks failing")
        #expect(shown(info(approvals: 0, running: 2)).summary == "3 commits · 2 of 12 checks running")
        #expect(shown(info()).summary == "3 commits · 2 approvals · 12 checks passing")
        #expect(shown(info(total: 0)).summary == "3 commits · 2 approvals · no checks")
        #expect(shown(info(commits: 1, approvals: 1, failing: 1, total: 1)).summary == "1 commit · 1 approval · 1 of 1 check failing")
        #expect(shown(info(commits: 1, approvals: 0, total: 1)).summary == "1 commit · 1 check passing")
        #expect(MergeMode(key: key, pinnedHead: "abc").summary == nil)
    }

    @Test func warningsReadAsWritten() {
        #expect(MergeWarning.checksFailing(1).text == "1 check is failing.")
        #expect(MergeWarning.checksFailing(2).text == "2 checks are failing.")
        #expect(MergeWarning.checksRunning(1).text == "1 check is still running.")
        #expect(MergeWarning.checksRunning(2).text == "2 checks are still running.")
        #expect(MergeWarning.noChecks.text == "No checks have reported on this commit.")
        #expect(MergeWarning.changesRequested.text == "A review is requesting changes.")
    }

    @Test func factsDifferOnEachField() {
        let base = MergeFacts(detail: detail(info()), offer: .action(.merge))
        #expect(base == MergeFacts(detail: detail(info()), offer: .action(.merge)))
        #expect(base != MergeFacts(detail: detail(info(), head: "def"), offer: .action(.merge)))
        #expect(base != MergeFacts(detail: detail(info(base: "dev")), offer: .action(.merge)))
        #expect(base != MergeFacts(detail: detail(info(), state: .merged), offer: .action(.merge)))
        #expect(base != MergeFacts(detail: detail(info()), offer: .action(.mergeWhenReady)))
        #expect(base != MergeFacts(detail: detail(info()), offer: .waiting))
        #expect(base != MergeFacts(detail: detail(info(failing: 1)), offer: .action(.merge)))
        #expect(base != MergeFacts(detail: detail(info(approvals: 1)), offer: .action(.merge)))
        #expect(base != MergeFacts(detail: detail(info(changes: true)), offer: .action(.merge)))
        let none = MergeFacts(detail: detail(nil), offer: .hidden)
        #expect(none.action == nil && none.approvals == 0 && none.tally.total == 0 && none.base == "")
    }
}
