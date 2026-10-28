import Foundation
import Testing
@testable import PullBullKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let codeJSON = """
    {"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device",\
    "expires_in":900,"interval":5}
    """
private let grantJSON = """
    {"access_token":"ghu_A","expires_in":28800,"refresh_token":"ghr_B",\
    "refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}
    """

private func client(_ fake: FakeGitHubOAuth, now: Date = now) -> DeviceFlowClient {
    DeviceFlowClient(clientID: "Iv23test", transport: fake, now: { now })
}

private let sampleCode = DeviceCode(
    deviceCode: "dc", userCode: "WDJB-MJHT",
    verificationURL: URL(string: "https://github.com/login/device")!,
    expiresIn: .seconds(900), interval: 5)

private func errorJSON(_ code: String, interval: Int? = nil) -> String {
    let extra = interval.map { #","interval":\#($0)"# } ?? ""
    return #"{"error":"\#(code)"\#(extra)}"#
}

@Suite struct DeviceFlowClientTests {
    @Test func requestCodeSendsFormAndAcceptJSON() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/device/code", [(200, codeJSON)])
        let code = try await client(fake).requestCode()

        let request = try #require(await fake.requests.first)
        #expect(request.url.absoluteString == "https://github.com/login/device/code")
        #expect(request.method == "POST")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(request.form == ["client_id": "Iv23test"])
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.expiresIn == .seconds(900))
        #expect(code.interval == 5)
    }

    @Test func pollSendsDeviceGrantType() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/oauth/access_token", [(200, errorJSON("authorization_pending"))])
        _ = try await client(fake).poll(sampleCode)

        let request = try #require(await fake.requests.first)
        #expect(request.url.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(
            request.form == [
                "client_id": "Iv23test", "device_code": "dc",
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
    }

    @Test func pollMapsEachErrorCode() async throws {
        func poll(_ json: String) async throws -> PollResult {
            let fake = FakeGitHubOAuth()
            await fake.script("/login/oauth/access_token", [(200, json)])
            return try await client(fake).poll(sampleCode)
        }
        #expect(try await poll(errorJSON("authorization_pending")) == .pending)
        #expect(try await poll(errorJSON("slow_down", interval: 10)) == .slowDown(interval: 10))
        #expect(try await poll(errorJSON("slow_down")) == .slowDown(interval: sampleCode.interval + 5))

        let expectations: [(String, DeviceFlowError)] = [
            ("expired_token", .expired),
            ("access_denied", .denied),
            ("device_flow_disabled", .misconfigured),
            ("incorrect_client_credentials", .misconfigured),
            ("unsupported_grant_type", .misconfigured),
            ("incorrect_device_code", .misconfigured),
            ("weird_code", .unexpected("weird_code")),
        ]
        for (code, expected) in expectations {
            await #expect(throws: expected) { try await poll(errorJSON(code)) }
        }
    }

    @Test func grantDatesComeFromExpiresIn() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/oauth/access_token", [(200, grantJSON)])
        let result = try await client(fake).poll(sampleCode)

        guard case .granted(let grant) = result else {
            Issue.record("expected a grant, got \(result)")
            return
        }
        #expect(grant.accessToken == "ghu_A")
        #expect(grant.refreshToken == "ghr_B")
        #expect(grant.accessExpiresAt == now.addingTimeInterval(28800))
        #expect(grant.refreshExpiresAt == now.addingTimeInterval(15_897_600))
    }

    @Test func grantWithoutExpiryDecodes() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script(
            "/login/oauth/access_token", [(200, #"{"access_token":"ghu_A","token_type":"bearer"}"#)])
        let result = try await client(fake).poll(sampleCode)

        guard case .granted(let grant) = result else {
            Issue.record("expected a grant, got \(result)")
            return
        }
        #expect(grant.accessExpiresAt == nil)
        #expect(grant.refreshToken == nil)
        #expect(grant.refreshExpiresAt == nil)
    }

    @Test func refreshSendsRefreshGrant() async throws {
        let fake = FakeGitHubOAuth(validRefreshTokens: ["ghr_B"])
        let grant = try await client(fake).refresh("ghr_B")

        let request = try #require(await fake.requests.first)
        #expect(
            request.form == ["client_id": "Iv23test", "grant_type": "refresh_token", "refresh_token": "ghr_B"])
        #expect(grant.refreshToken != "ghr_B")
        await #expect(throws: DeviceFlowError.badRefreshToken) {
            try await client(fake).refresh("ghr_B")
        }
    }

    /// GitHub answers a refresh with a revoked authorization as `incorrect_client_credentials` (seen live, 2026-10-27):
    /// that is a sign-out, not a misconfigured app. The device flow keeps reading it as misconfigured.
    @Test func refreshWithRevokedAuthorizationIsSignedOut() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/oauth/access_token", [(200, errorJSON("incorrect_client_credentials"))])
        await #expect(throws: DeviceFlowError.badRefreshToken) {
            try await client(fake).refresh("ghr_revoked")
        }
        await fake.script("/login/oauth/access_token", [(200, errorJSON("incorrect_client_credentials"))])
        await #expect(throws: DeviceFlowError.misconfigured) {
            try await client(fake).poll(sampleCode)
        }
    }

    /// A build without the app's client ID never sends a refresh: GitHub would read it as revoked.
    @Test func refreshWithoutClientIDIsMisconfiguredAndSendsNothing() async throws {
        let fake = FakeGitHubOAuth(validRefreshTokens: ["ghr_B"])
        let flow = DeviceFlowClient(clientID: "", transport: fake, now: { now })
        await #expect(throws: DeviceFlowError.misconfigured) { try await flow.refresh("ghr_B") }
        #expect(await fake.requests.isEmpty)
    }

    @Test func noRequestCarriesClientSecret() async throws {
        let fake = FakeGitHubOAuth(validRefreshTokens: ["ghr_B"])
        await fake.script("/login/device/code", [(200, codeJSON)])
        await fake.script(
            "/login/oauth/access_token",
            [(200, errorJSON("authorization_pending")), (200, errorJSON("slow_down")), (200, grantJSON)])
        let flow = client(fake)
        let code = try await flow.requestCode()
        for _ in 0..<3 { _ = try await flow.poll(code) }
        _ = try await flow.refresh("ghr_B")

        let requests = await fake.requests
        #expect(requests.count == 5)
        let key = "client" + "_secret"
        #expect(requests.allSatisfy { $0.form[key] == nil && !($0.url.query ?? "").contains(key) })
    }

    @Test func requestCodeRateLimitIsTooManyCodes() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/device/code", [(429, "{}")])
        await #expect(throws: DeviceFlowError.tooManyCodes) { try await client(fake).requestCode() }
    }

    @Test func networkFailureIsNetwork() async throws {
        let fake = FakeGitHubOAuth()
        await fake.failNext(URLError(.notConnectedToInternet))
        await #expect(throws: DeviceFlowError.network) { try await client(fake).requestCode() }
    }

    /// A transport failure that isn't a lack of connectivity is retried like a 5xx, never offline.
    @Test func secureConnectionFailureIsUnexpected() async throws {
        let fake = FakeGitHubOAuth()
        await fake.failNext(URLError(.serverCertificateUntrusted))
        await #expect(throws: DeviceFlowError.unexpected("secure connection failed")) {
            try await client(fake).requestCode()
        }
    }

    @Test func cancelledRequestIsCancellation() async throws {
        let fake = FakeGitHubOAuth()
        await fake.failNext(URLError(.cancelled))
        await #expect(throws: CancellationError.self) { try await client(fake).requestCode() }
    }

    @Test(arguments: [
        (400, "{}"), (401, "{}"), (404, "{}"), (422, "{}"),
        (200, #"{"error":"weird_code"}"#), (200, #"{"error":"authorization_pending"}"#),
        (200, "not json"), (200, #"{"user_code":"WDJB-MJHT"}"#),
    ])
    func permanentRequestCodeFailureIsMisconfigured(status: Int, json: String) async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/device/code", [(status, json)])
        await #expect(throws: DeviceFlowError.misconfigured) { try await client(fake).requestCode() }
    }

    @Test func requestCodeServerErrorStaysUnexpected() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/device/code", [(503, "{}")])
        await #expect(throws: DeviceFlowError.unexpected("HTTP 503")) { try await client(fake).requestCode() }
    }

    @Test func unknownErrorMessageHasNoBody() async throws {
        let fake = FakeGitHubOAuth()
        await fake.script("/login/device/code", [(500, #"{"secret":"ghu_LEAK"}"#)])
        let error = await #expect(throws: DeviceFlowError.self) { try await client(fake).requestCode() }
        #expect(error == .unexpected("HTTP 500"))
        #expect(!String(describing: try #require(error)).contains("ghu_LEAK"))
    }

    @Test func grantAndCodeAreRedacted() {
        let grant = TokenGrant(
            accessToken: "ghu_SECRET", accessExpiresAt: now,
            refreshToken: "ghr_SECRET", refreshExpiresAt: now)
        let code = DeviceCode(
            deviceCode: "dc_SECRET", userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            expiresIn: .seconds(900), interval: 5)

        func renderings(_ value: some Any) -> [String] {
            var dumped = ""
            dump(value, to: &dumped)
            return [String(describing: value), String(reflecting: value), "\(value)", dumped]
        }
        for text in renderings(grant) + renderings(code) {
            #expect(!text.contains("_SECRET"))
        }
        #expect(String(describing: code) == "<device code user=WDJB-MJHT>")
    }
}
