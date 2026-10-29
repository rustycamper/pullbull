import Testing
@testable import PullBullKit

@Suite struct AskErrorMessageTests {
    @Test func messagePerCase() {
        #expect(AskError.offline.message == "No network.")
        #expect(AskError.unauthorized.message == "Anthropic rejected the key. Check it in Settings → Ask AI.")
        #expect(AskError.rateLimited.message == "Rate limited by Anthropic. Try again shortly.")
        #expect(AskError.timeout.message == "No answer in 20 s.")
        #expect(AskError.refusal.message == "The model declined to answer.")
        #expect(AskError.modelRetired.message
            == "Anthropic retired this model. Pick another in Settings → Ask AI, or save the key again to refresh the list.")
        #expect(AskError.truncated.message == "Ask AI failed (answer cut off).")
        #expect(AskError.noAnswer.message == "Ask AI failed (no answer).")
    }

    @Test func serverMessageCarriesStatus() {
        #expect(AskError.server(500).message == "Ask AI failed (HTTP 500).")
    }

    @Test func serverWithoutStatusIsUnexpectedError() {
        #expect(AskError.server(0).message == "Ask AI failed (unexpected error).")
    }
}
