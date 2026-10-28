import Foundation
import Testing
@testable import PullBullKit

private let closedAt = Date(timeIntervalSince1970: 1_800_000_000)

@Test func returnRouteAsk() {
    // A detail opened from Ask closes onto Ask.
    #expect(AskReturn.closing(openedFrom: .ask) == .ask)
    // A PR linked from an issue that was opened from Ask: back to the issue first, then Ask.
    #expect(AskReturn.closing(openedFrom: .issueDetail) == .issueDetail)
    #expect(AskReturn.closing(openedFrom: .ask) == .ask)
    // Details opened elsewhere are not Ask's business.
    #expect(AskReturn.closing(openedFrom: .list) == .list)
    #expect(AskReturn.closing(openedFrom: .search) == .search)
}

@Test func escOnAskGoesBackToSearchWithTheQuestion() {
    let landing = AskReturn.leavingAsk(question: "who fixed the acme paging bug")
    #expect(landing.place == .search)
    #expect(landing.searchText == "who fixed the acme paging bug")
}

@Test func backTitleNamesAskResults() {
    #expect(AskReturn.backTitle(openedFrom: .ask) == "Ask results")
    #expect(AskReturn.backTitle(openedFrom: .list) == nil)
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
