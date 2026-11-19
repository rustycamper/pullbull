import Testing
@testable import PullBullKit

private func reactions(mine: Bool) -> Reactions {
    Reactions(
        subjectId: "S1",
        groups: [ReactionGroup(content: .thumbsUp, count: mine ? 1 : 0, viewerHasReacted: mine, reactors: [])],
        viewerCanReact: true)
}

@Suite struct ReactionFlowTests {
    @Test func anAppliedAnswerMatchingTheLastClickIsDone() {
        let r = reactions(mine: true)
        #expect(ReactionFlow.next(sent: true, answer: .applied(r), wanted: true) == .done(r))
    }

    @Test func aSecondClickWhileSendingSendsTheOppositeAfterTheAnswer() {
        #expect(ReactionFlow.next(sent: true, answer: .applied(reactions(mine: true)), wanted: false) == .send(add: false))
    }

    @Test func aRefusalOfTheLastClickIsRefused() {
        #expect(ReactionFlow.next(sent: true, answer: .refused("locked"), wanted: true) == .refused("locked"))
    }

    @Test func aRefusalAfterTheUserChangedTheirMindIsQuiet() {
        #expect(ReactionFlow.next(sent: true, answer: .refused("locked"), wanted: false) == .dropQuietly)
    }

    @Test func anUnknownAnswerConfirms() {
        #expect(ReactionFlow.next(sent: true, answer: .unknown, wanted: true) == .confirm)
        #expect(ReactionFlow.next(sent: true, answer: .unknown, wanted: false) == .confirm)
    }

    @Test func aFailedConfirmFetchIsUnconfirmed() {
        #expect(ReactionFlow.afterConfirm(nil, content: .thumbsUp, sent: true, wanted: true) == .unconfirmed)
        #expect(ReactionFlow.afterConfirm(nil, content: .thumbsUp, sent: true, wanted: false) == .unconfirmed)
    }

    @Test func aConfirmShowingTheWantedStateIsQuiet() {
        #expect(ReactionFlow.afterConfirm(reactions(mine: true), content: .thumbsUp, sent: true, wanted: true) == .dropQuietly)
        #expect(ReactionFlow.afterConfirm(reactions(mine: false), content: .thumbsUp, sent: false, wanted: false) == .dropQuietly)
    }

    @Test func aClickDuringTheConfirmSendsIt() {
        #expect(ReactionFlow.afterConfirm(reactions(mine: false), content: .thumbsUp, sent: true, wanted: false) == .dropQuietly)
        #expect(ReactionFlow.afterConfirm(reactions(mine: true), content: .thumbsUp, sent: true, wanted: false) == .send(add: false))
    }

    @Test func aConfirmNotShowingItIsUnconfirmed() {
        #expect(ReactionFlow.afterConfirm(reactions(mine: false), content: .thumbsUp, sent: true, wanted: true) == .unconfirmed)
    }
}
