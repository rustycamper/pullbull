import Testing
@testable import PullBullKit

private let first = PRKey(repo: "acme/api", number: 1)
private let second = PRKey(repo: "acme/api", number: 2)

/// What the app compares: the screen, the mode and tab, the account, the query and the popover.
private struct Screen: Equatable, Sendable {
    var route = "list"
    var mode = "pullRequests"
    var tab = "review"
    var account = "octocat"
    var query = ""
    var popoverOpens = 1
}

@Test func theDetailOpensWhenNothingChanged() {
    var flash = RowFlash<Screen>()
    let began = flash.begin(first, context: Screen())
    #expect(began)
    #expect(flash.key == first)
    let opens = flash.end(context: Screen())
    #expect(opens)
    #expect(flash.key == nil)
}

@Test(arguments: [
    Screen(route: "search"),
    Screen(mode: "issues"),
    Screen(tab: "mine"),
    Screen(account: "hubot"),
    Screen(query: "fix"),
    Screen(popoverOpens: 2),
])
private func aChangeDuringTheFlashDropsTheDetail(changed: Screen) {
    var flash = RowFlash<Screen>()
    _ = flash.begin(first, context: Screen())
    let opens = flash.end(context: changed)
    #expect(!opens)
    #expect(flash.key == nil)
}

@Test func aSecondChoiceDuringTheFlashIsIgnored() {
    var flash = RowFlash<Screen>()
    _ = flash.begin(first, context: Screen())
    let again = flash.begin(first, context: Screen())
    let other = flash.begin(second, context: Screen(tab: "mine"))
    #expect(!again)
    #expect(!other)
    #expect(flash.key == first)
    // The ignored choice's context doesn't replace the first one's.
    let opens = flash.end(context: Screen())
    #expect(opens)
}

@Test func endingWithoutAFlashOpensNothing() {
    var flash = RowFlash<Screen>()
    let opens = flash.end(context: Screen())
    #expect(!opens)
}

@Test func theNextChoiceFlashesOnceTheFlashEnds() {
    var flash = RowFlash<Screen>()
    _ = flash.begin(first, context: Screen())
    _ = flash.end(context: Screen(query: "x"))
    let began = flash.begin(second, context: Screen())
    #expect(began)
    #expect(flash.key == second)
}
