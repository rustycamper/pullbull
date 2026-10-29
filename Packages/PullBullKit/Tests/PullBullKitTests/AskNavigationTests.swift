import Foundation
import Testing
@testable import PullBullKit

private let closedAt = Date(timeIntervalSince1970: 1_800_000_000)

@Test func returnRouteAsk() {
    var route = AskReturn()
    // Ask opens an issue; the issue opens a linked PR.
    route.open(from: .ask)
    #expect(route.backTitle == "Ask AI results")
    route.open(from: .issueDetail)
    #expect(route.backTitle == nil)
    // Closing the PR comes back through the issue, then to Ask.
    #expect(route.close() == .issueDetail)
    #expect(route.backTitle == "Ask AI results")
    #expect(route.close() == .ask)
    // Nothing open: the list.
    #expect(route.close() == .list)
}

@Test func detailOpenedFromAskClosesOntoAsk() {
    var route = AskReturn()
    route.open(from: .ask)
    #expect(route.close() == .ask)
    // A detail opened from the list does not return to Ask.
    route.open(from: .list)
    #expect(route.backTitle == nil)
    #expect(route.close() == .list)
}

@Test func escOnAskGoesBackToSearchWithTheQuestion() {
    let landing = AskReturn.leavingAsk(question: "who fixed the acme paging bug")
    #expect(landing.place == .search)
    #expect(landing.searchText == "who fixed the acme paging bug")
}

@Test func reopenAfterLongWhileKeepsQuestion() {
    let question = "paging bug in acme/web"
    let long = closedAt.addingTimeInterval(PopoverReopen.keepDetailFor)
    for place in [AskReturn.Place.ask, .issueDetail, .pullRequestDetail] {
        let landing = AskReturn.reopening(at: place, question: question, closedAt: closedAt, now: long)
        #expect(landing.place == .search)
        #expect(landing.searchText == question)
    }
}

@Test func reopenWithinAMinuteStaysPut() {
    let soon = closedAt.addingTimeInterval(59)
    let landing = AskReturn.reopening(at: .ask, question: "q", closedAt: closedAt, now: soon)
    #expect(landing.place == .ask)
    #expect(landing.searchText == "q")
}

@Test func editCancelsAsk() {
    var generation = AskGeneration()
    let first = generation.begin()
    #expect(generation.accepts(first))
    // Typing in the field cancels: an earlier reply no longer lands.
    generation.cancel()
    #expect(!generation.accepts(first))
    // A newer Ask supersedes an older one still in flight.
    let second = generation.begin()
    let third = generation.begin()
    #expect(!generation.accepts(second))
    #expect(generation.accepts(third))
}

@Test func cancellationIsIgnored() {
    #expect(AskGeneration.isCancellation(CancellationError()))
    #expect(AskGeneration.isCancellation(URLError(.cancelled)))
    #expect(!AskGeneration.isCancellation(URLError(.notConnectedToInternet)))
    #expect(!AskGeneration.isCancellation(AskError.timeout))
}

private func answered(_ question: String) -> AskOutcome {
    let answer = AskAnswer(results: [], answer: "Nothing.", model: .default, elapsed: .seconds(1), cardsSent: 0)
    return .answered(question: question, answer: answer, rows: [], stillSyncing: nil)
}

@Test func askReturnIsEmptyOnlyWithNoOpener() {
    var route = AskReturn()
    #expect(route.isEmpty)
    route.open(from: .ask)
    #expect(!route.isEmpty)
    _ = route.close()
    #expect(route.isEmpty)
    route.open(from: .ask)
    route.reset()
    #expect(route.isEmpty)
}

@Test func askStateShowsTheScreenForAnAnswer() {
    var state = AskState()
    let token = state.begin("paging bug in acme/web")
    #expect(state.asking == "paging bug in acme/web")
    #expect(state.outcome == nil)
    #expect(state.land(answered("paging bug in acme/web"), token: token) == .screen)
    #expect(state.asking == nil)
    #expect(state.outcome == answered("paging bug in acme/web"))
}

@Test func askStateKeepsAFailureOnTheSearch() {
    var state = AskState()
    let token = state.begin("q")
    #expect(state.land(.failed(question: "q", .timeout), token: token) == .errorLine)
    #expect(state.errorLine(for: "q") == "No answer in 20 s.")
    // Another question in the field: the line is not about it.
    #expect(state.errorLine(for: "other") == nil)
}

@Test func lateReplyNeverReplacesTheScreen() {
    var state = AskState()
    let first = state.begin("first")
    // Typing in the field: the reply in flight is dropped and nothing shows.
    state.clear()
    #expect(state.asking == nil)
    #expect(state.land(answered("first"), token: first) == .ignored)
    #expect(state.outcome == nil)
    // A newer Ask supersedes one still in flight, whichever replies first.
    let second = state.begin("second")
    let third = state.begin("third")
    #expect(state.land(answered("second"), token: second) == .ignored)
    #expect(state.asking == "third")
    #expect(state.land(answered("third"), token: third) == .screen)
    #expect(state.outcome == answered("third"))
    // An earlier failure arriving after the answer changes nothing either.
    #expect(state.land(.failed(question: "second", .offline), token: second) == .ignored)
    #expect(state.outcome == answered("third"))
}

@Test func cancelledAskEndsQuietly() {
    var state = AskState()
    let old = state.begin("old")
    let current = state.begin("current")
    // The superseded Ask's cancellation leaves the running one alone.
    state.cancelled(token: old)
    #expect(state.asking == "current")
    state.cancelled(token: current)
    #expect(state.asking == nil)
    #expect(state.outcome == nil)
    #expect(state.notice == nil)
}

@Test func askWithoutKeyShowsTheNoticeAndDropsTheAskInFlight() {
    var state = AskState()
    let token = state.begin("q")
    state.needsKey()
    #expect(state.notice == "Add an Anthropic API key in Settings → Ask AI")
    #expect(state.asking == nil)
    #expect(state.outcome == nil)
    #expect(state.land(answered("q"), token: token) == .ignored)
    // The next Ask or edit clears the notice.
    _ = state.begin("q")
    #expect(state.notice == nil)
    state.needsKey()
    state.clear()
    #expect(state.notice == nil)
}

@Test func editClearsAnErrorLine() {
    var state = AskState()
    let token = state.begin("q")
    _ = state.land(.failed(question: "q", .offline), token: token)
    state.clear()
    #expect(state.outcome == nil)
    #expect(state.errorLine(for: "q") == nil)
}

@Test func longReopenOnADetailOpenedFromAskLandsOnSearchWithTheQuestion() {
    let question = "paging bug in acme/web"
    let long = closedAt.addingTimeInterval(PopoverReopen.keepDetailFor)
    // Ask opened an issue, and the issue a linked PR.
    var route = AskReturn()
    route.open(from: .ask)
    route.open(from: .issueDetail)
    let landing = route.reopen(at: .pullRequestDetail, question: question, closedAt: closedAt, now: long)
    #expect(landing == AskReturn.Landing(place: .search, searchText: question))
    // Nothing is left to go back through.
    #expect(route.isEmpty)
}

@Test func reopenWithinAMinuteKeepsTheAskChain() {
    var route = AskReturn()
    route.open(from: .ask)
    let soon = closedAt.addingTimeInterval(59)
    let landing = route.reopen(at: .issueDetail, question: "q", closedAt: closedAt, now: soon)
    #expect(landing.place == .issueDetail)
    #expect(!route.isEmpty)
    #expect(route.close() == .ask)
}

@Test func askWithoutAnOpenIndexSaysSo() {
    var state = AskState()
    let token = state.begin("q")
    state.refuse(AskState.indexNotReadyNotice)
    #expect(state.notice == "Ask AI index isn't ready yet.")
    #expect(state.asking == nil)
    #expect(state.land(answered("q"), token: token) == .ignored)
}

@Test func askAgainWhileTheSameQuestionRunsSendsNothing() {
    var state = AskState()
    #expect(!state.isAsking("q"))
    let token = state.begin("q")
    #expect(state.isAsking("q"))
    // An edited question still replaces the one in flight.
    #expect(!state.isAsking("q2"))
    _ = state.land(.failed(question: "q", .timeout), token: token)
    #expect(!state.isAsking("q"))
}
