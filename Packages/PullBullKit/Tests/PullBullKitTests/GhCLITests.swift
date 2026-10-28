import Foundation
import Testing
@testable import PullBullKit

private struct FakeRunner: ProcessRunning {
    let handler: @Sendable (URL, [String]) -> (status: Int32, stdout: Data, stderr: Data)

    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        handler(executable, args)
    }
}

private let statusJSON = #"{"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"rustycamper","tokenSource":"GH_TOKEN","scopes":"admin:public_key, gist, read:org, repo","gitProtocol":"ssh"},{"state":"success","active":false,"host":"github.com","login":"rustycamper","tokenSource":"keyring","scopes":"admin:public_key, gist, read:org, repo","gitProtocol":"ssh"},{"state":"success","active":false,"host":"github.com","login":"devon","tokenSource":"keyring","scopes":"admin:public_key, gist, project, read:org, repo","gitProtocol":"ssh"}]}}"#

@Suite struct GhCLITests {
    @Test func parsesAccounts() async throws {
        let runner = FakeRunner { _, args in
            #expect(args == ["auth", "status", "--json", "hosts"])
            return (1, Data(statusJSON.utf8), Data())
        }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        let accounts = try await gh.accounts()
        #expect(accounts.map(\.login) == ["rustycamper", "devon"])
        #expect(accounts[1].canReadProjects)
        #expect(!accounts[0].canReadProjects)
        #expect(accounts[0].scopes == ["admin:public_key", "gist", "read:org", "repo"])
    }

    @Test func skipsNonSuccessAndOtherHosts() async throws {
        let json = #"{"hosts":{"github.com":[{"state":"error","login":"bad","scopes":""},{"state":"success","login":"ok","scopes":"repo"}],"ghe.example.com":[{"state":"success","login":"other","scopes":"repo"}]}}"#
        let runner = FakeRunner { _, _ in (0, Data(json.utf8), Data()) }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        #expect(try await gh.accounts().map(\.login) == ["ok"])
    }

    @Test func locateFallsBackToLoginShell() async throws {
        let runner = FakeRunner { exe, args in
            #expect(exe.path == "/bin/zsh")
            #expect(args == ["-lc", "command -v gh"])
            return (0, Data("/x/gh\n".utf8), Data())
        }
        let gh = GhCLI(runner: runner, searchPaths: ["/a/gh"], fileExists: { _ in false })
        #expect(try await gh.locate() == URL(fileURLWithPath: "/x/gh"))
    }

    @Test func locateNotInstalled() async {
        let runner = FakeRunner { _, _ in (1, Data(), Data()) }
        let gh = GhCLI(runner: runner, searchPaths: ["/a/gh"], fileExists: { _ in false })
        await #expect(throws: GhError.notInstalled) { try await gh.locate() }
    }

    @Test func tokenIsTrimmed() async throws {
        let runner = FakeRunner { _, args in
            #expect(args == ["auth", "token", "--user", "devon"])
            return (0, Data("abc123\n".utf8), Data())
        }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        #expect(try await gh.token(for: "devon") == "abc123")
    }

    @Test func tokenNotLoggedIn() async {
        let runner = FakeRunner { _, _ in (1, Data(), Data("no oauth token found for devon".utf8)) }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        await #expect(throws: GhError.notLoggedIn("devon")) { try await gh.token(for: "devon") }
    }

    @Test func canReadProjectsForLogin() {
        let accounts = [
            GhAccount(login: "devon", scopes: ["repo", "project"]),
            GhAccount(login: "rustycamper", scopes: ["repo"]),
        ]
        #expect(accounts.canReadProjects(for: "devon"))
        #expect(!accounts.canReadProjects(for: "rustycamper"))
        // Unknown until gh auth status answers: assume access.
        #expect(accounts.canReadProjects(for: "someone-else"))
        #expect(!accounts.canReadProjects(for: nil))
    }

    @Test func accountsKnowTheActiveLogin() async throws {
        let runner = FakeRunner { _, _ in (0, Data(statusJSON.utf8), Data()) }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        let accounts = try await gh.accounts()
        #expect(accounts.map(\.active) == [true, false])
    }

    @Test func statusListsEveryLoginWithItsHealth() async {
        let json = #"{"hosts":{"github.com":[{"state":"success","active":true,"login":"rustycamper","scopes":"repo"},{"state":"error","active":false,"login":"devon","error":"The token in keyring is invalid.","scopes":""},{"state":"timeout","active":false,"login":"slow","scopes":""},{"state":"error","active":false,"login":"offline","error":"Get \"https://api.github.com/\": dial tcp: lookup api.github.com: no such host"}]}}"#
        let runner = FakeRunner { _, _ in (1, Data(json.utf8), Data()) }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        #expect(await gh.status() == .logins(gh: "/fake/gh", [
            GhLogin(login: "rustycamper", active: true, health: .ok, scopes: ["repo"]),
            GhLogin(login: "devon", active: false, health: .invalid, scopes: []),
            GhLogin(login: "slow", active: false, health: .unreachable, scopes: []),
            GhLogin(login: "offline", active: false, health: .unreachable, scopes: []),
        ]))
    }

    @Test func statusMergesALoginListedTwice() async {
        let runner = FakeRunner { _, _ in (0, Data(statusJSON.utf8), Data()) }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        guard case .logins(_, let logins) = await gh.status() else {
            Issue.record("expected logins")
            return
        }
        #expect(logins.map(\.login) == ["rustycamper", "devon"])
        #expect(logins[0].active)
    }

    @Test func statusWithoutGh() async {
        let runner = FakeRunner { _, _ in (1, Data(), Data()) }
        let gh = GhCLI(runner: runner, searchPaths: ["/a/gh"], fileExists: { _ in false })
        #expect(await gh.status() == .notInstalled)
    }

    @Test func statusFailureKeepsTheFirstLineOfStderr() async {
        let runner = FakeRunner { _, _ in (1, Data("not json".utf8), Data("error connecting to keyring\nmore detail".utf8)) }
        let gh = GhCLI(runner: runner, searchPaths: ["/fake/gh"], fileExists: { _ in true })
        #expect(await gh.status() == .failed(gh: "/fake/gh", message: "error connecting to keyring"))
    }

    @Test func homebrewIsFoundInEitherPrefix() {
        let intel = GhCLI(runner: FakeRunner { _, _ in (0, Data(), Data()) }, fileExists: { $0 == "/usr/local/bin/brew" })
        #expect(intel.homebrewInstalled)
        let none = GhCLI(runner: FakeRunner { _, _ in (0, Data(), Data()) }, fileExists: { _ in false })
        #expect(!none.homebrewInstalled)
    }

    @Test func processRunnerTimesOut() async throws {
        let runner = SystemProcessRunner(timeout: .milliseconds(300))
        let started = Date()
        await #expect(throws: GhError.failed("sleep did not finish within 0.3s and was stopped")) {
            _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"])
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }

    @Test func processRunnerReturnsOutputBeforeTimeout() async throws {
        let runner = SystemProcessRunner(timeout: .seconds(10))
        let result = try await runner.run(URL(fileURLWithPath: "/bin/echo"), ["hi"])
        #expect(result.status == 0)
        #expect(String(decoding: result.stdout, as: UTF8.self) == "hi\n")
    }

    @Test func authStatusGetsALongerTimeoutThanToken() async throws {
        let runner = TimeoutRecorder()
        let gh = GhCLI(runner: runner, searchPaths: ["/x/gh"], fileExists: { _ in true })
        _ = try? await gh.accounts()
        _ = try? await gh.token(for: "me")
        #expect(runner.timeouts == [GhCLI.authStatusTimeout, nil])
    }

    @Test func processRunnerHonorsPerCallTimeout() async throws {
        let runner = SystemProcessRunner(timeout: .seconds(30))
        let started = Date()
        await #expect(throws: GhError.self) {
            _ = try await runner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: .milliseconds(300))
        }
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

private final class TimeoutRecorder: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Duration?] = []
    var timeouts: [Duration?] { lock.withLock { recorded } }

    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await run(executable, args, timeout: nil)
    }

    func run(
        _ executable: URL, _ args: [String], timeout: Duration?
    ) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        lock.withLock { recorded.append(timeout) }
        return (0, Data(#"{"hosts":{}}"#.utf8), Data())
    }
}
