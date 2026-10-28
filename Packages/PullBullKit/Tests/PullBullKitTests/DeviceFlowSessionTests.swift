import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let verificationURL = URL(string: "https://github.com/login/device")!
private let grantJSON = """
    {"access_token":"ghu_A","expires_in":28800,"refresh_token":"ghr_B",\
    "refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}
    """
private let grant = TokenGrant(
    accessToken: "ghu_A", accessExpiresAt: now.addingTimeInterval(28800),
    refreshToken: "ghr_B", refreshExpiresAt: now.addingTimeInterval(15_897_600))
private let pending = (200, #"{"error":"authorization_pending"}"#)

private func codeJSON(expiresIn: Int = 900, interval: Int = 5) -> String {
    """
    {"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device",\
    "expires_in":\(expiresIn),"interval":\(interval)}
    """
}

private func codeEvent(expiresIn: Int = 900) -> DeviceFlowEvent {
    .code(userCode: "WDJB-MJHT", verificationURL: verificationURL, expiresAt: now.addingTimeInterval(TimeInterval(expiresIn)))
}

private struct Harness {
    let fake = FakeGitHubOAuth()
    let clock = TestClock()

    func run(transport: (any HTTPTransport)? = nil) -> Task<[DeviceFlowEvent], Never> {
        let session = DeviceFlowSession(
            client: DeviceFlowClient(clientID: "Iv23test", transport: transport ?? fake, now: { now }),
            clock: clock, now: { now })
        let stream = session.run()
        return Task {
            var events: [DeviceFlowEvent] = []
            for await event in stream { events.append(event) }
            return events
        }
    }

    /// Lets the session request its next sleep, then advances the clock by that sleep.
    func tick(_ n: Int, by duration: Duration) async {
        _ = await clock.waitForSleeps(n)
        clock.advance(by: duration)
    }
}

private func seconds(_ values: Int...) -> [Duration] { values.map { .seconds($0) } }

/// Answers the code request from `inner` but fails every poll with an error that isn't a `DeviceFlowError`.
private struct PollThrows: HTTPTransport {
    struct Boom: Error {}
    let inner: FakeGitHubOAuth

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path == "/login/oauth/access_token" { throw Boom() }
        return try await inner.send(request)
    }
}

@Suite struct DeviceFlowSessionTests {
    @Test func pendingThreeTimesThenGranted() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.script("/login/oauth/access_token", [pending, pending, pending, (200, grantJSON)])
        let events = h.run()
        for n in 1...4 { await h.tick(n, by: .seconds(5)) }
        #expect(await events.value == [codeEvent(), .granted(grant)])
        #expect(await h.clock.waitForSleeps(4) == seconds(5, 5, 5, 5))
    }

    @Test func slowDownAddsFiveSecondsAndKeepsIt() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.script(
            "/login/oauth/access_token",
            [pending, (200, #"{"error":"slow_down"}"#), pending, (200, grantJSON)])
        let events = h.run()
        await h.tick(1, by: .seconds(5))
        await h.tick(2, by: .seconds(5))
        await h.tick(3, by: .seconds(10))
        await h.tick(4, by: .seconds(10))
        #expect(await events.value == [codeEvent(), .granted(grant)])
        #expect(await h.clock.waitForSleeps(4) == seconds(5, 5, 10, 10))
    }

    @Test func expiresWithoutServerAnswer() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON(expiresIn: 15))])
        await h.fake.script("/login/oauth/access_token", [pending, pending])
        let events = h.run()
        for n in 1...3 { await h.tick(n, by: .seconds(5)) }
        #expect(await events.value == [codeEvent(expiresIn: 15), .expired])
        #expect(await h.fake.requests.count == 3)
    }

    @Test func deniedEndsTheStream() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.script("/login/oauth/access_token", [pending, (200, #"{"error":"access_denied"}"#)])
        let events = h.run()
        for n in 1...2 { await h.tick(n, by: .seconds(5)) }
        #expect(await events.value.last == .denied)
    }

    @Test func networkErrorThenRecovery() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.script("/login/oauth/access_token", [pending, pending, (200, grantJSON)])
        let events = h.run()
        await h.tick(1, by: .seconds(5))
        _ = await h.clock.waitForSleeps(2)
        await h.fake.failNext(URLError(.notConnectedToInternet))
        h.clock.advance(by: .seconds(5))
        await h.tick(3, by: .seconds(10))
        await h.tick(4, by: .seconds(5))
        #expect(await events.value == [codeEvent(), .unreachable, .waiting, .granted(grant)])
        #expect(await h.clock.waitForSleeps(4) == seconds(5, 5, 10, 5))
    }

    @Test func requestCodeOfflineRetries() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.script("/login/oauth/access_token", [(200, grantJSON)])
        await h.fake.failNext(URLError(.notConnectedToInternet))
        let events = h.run()
        await h.tick(1, by: .seconds(5))
        await h.tick(2, by: .seconds(5))
        #expect(await events.value == [.unreachable, codeEvent(), .granted(grant)])
    }

    @Test func requestCodeRetryBacksOffToThirtySeconds() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.failNext(URLError(.timedOut))
        let events = h.run()
        let waits = [5, 10, 20, 30, 30]
        for (i, wait) in waits.enumerated() {
            _ = await h.clock.waitForSleeps(i + 1)
            if i < waits.count - 1 { await h.fake.failNext(URLError(.timedOut)) }
            h.clock.advance(by: .seconds(wait))
        }
        _ = await h.clock.waitForSleeps(6)
        events.cancel()
        #expect(await events.value == [.unreachable, codeEvent()])
        #expect(h.clock.requestedSleeps.prefix(5) == waits.map { Duration.seconds($0) }[...])
    }

    @Test(arguments: [
        (429, "{}", DeviceFlowEvent.tooManyCodes),
        (200, #"{"error":"device_flow_disabled"}"#, DeviceFlowEvent.misconfigured),
    ])
    func tooManyCodesAndMisconfigured(status: Int, json: String, event: DeviceFlowEvent) async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(status, json)])
        #expect(await h.run().value == [event])
    }

    @Test(arguments: [
        (400, "{}"), (404, "{}"),
        (200, #"{"error":"weird_code"}"#), (200, "not json"),
    ])
    func permanentRequestCodeFailureIsMisconfigured(status: Int, json: String) async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(status, json)])
        #expect(await h.run().value == [.misconfigured])
        #expect(await h.fake.requests.count == 1)
        #expect(h.clock.requestedSleeps.isEmpty)
    }

    @Test func requestCodeServerErrorRetriesAsUnreachable() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(502, "{}"), (503, "{}"), (200, codeJSON())])
        await h.fake.script("/login/oauth/access_token", [(200, grantJSON)])
        let events = h.run()
        await h.tick(1, by: .seconds(5))
        await h.tick(2, by: .seconds(10))
        await h.tick(3, by: .seconds(5))
        #expect(await events.value == [.unreachable, codeEvent(), .granted(grant)])
        #expect(await h.clock.waitForSleeps(3) == seconds(5, 10, 5))
        #expect(await h.fake.requests.filter { $0.url.path == "/login/device/code" }.count == 3)
    }

    @Test func nonDeviceFlowPollErrorIsMisconfigured() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        let events = h.run(transport: PollThrows(inner: h.fake))
        await h.tick(1, by: .seconds(5))
        #expect(await events.value == [codeEvent(), .misconfigured])
    }

    @Test func cancellationStopsRequests() async {
        let h = Harness()
        await h.fake.script("/login/device/code", [(200, codeJSON())])
        await h.fake.script("/login/oauth/access_token", [pending, pending, pending])
        let session = DeviceFlowSession(
            client: DeviceFlowClient(clientID: "Iv23test", transport: h.fake, now: { now }),
            clock: h.clock, now: { now })
        let stream = session.run()
        let consumer = Task {
            for await _ in stream {}
        }
        _ = await h.clock.waitForSleeps(1)
        let before = await h.fake.requests.count
        consumer.cancel()
        await consumer.value
        // Ending the stream cancels the session's sleep at once, so nothing is left to wake.
        #expect(h.clock.pendingSleepers == 0)
        h.clock.advance(by: .seconds(3600))
        #expect(await h.fake.requests.count == before)
        #expect(h.clock.requestedSleeps.count == 1)
    }
}
