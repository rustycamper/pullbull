import Foundation

public protocol ProcessRunning: Sendable {
    func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data)
    /// `timeout` overrides the runner's own; nil keeps it.
    func run(
        _ executable: URL, _ args: [String], timeout: Duration?
    ) async throws -> (status: Int32, stdout: Data, stderr: Data)
}

public extension ProcessRunning {
    func run(
        _ executable: URL, _ args: [String], timeout: Duration?
    ) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await run(executable, args)
    }
}

public struct SystemProcessRunner: ProcessRunning {
    private let timeout: Duration

    /// Runs the blocking work (pipe reads, the exit wait) and the timeout. A queue of its own targets the
    /// overcommit root queue, which adds a thread when its threads block; the global queue doesn't overcommit
    /// and holds about one thread per core, so blocked reads could keep the timeout from firing on time.
    private static let queue = DispatchQueue(label: "PullBull.process", attributes: .concurrent)

    /// A process still running after `timeout` (e.g. `gh` waiting on an unanswered Keychain prompt)
    /// is stopped and reported as `GhError.failed`, so a refresh can't hang forever.
    public init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
    }

    public func run(_ executable: URL, _ args: [String]) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        try await run(executable, args, timeout: nil)
    }

    public func run(
        _ executable: URL, _ args: [String], timeout: Duration?
    ) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        var env = ProcessInfo.processInfo.environment
        env["GH_TOKEN"] = nil
        env["GITHUB_TOKEN"] = nil
        let parts = (timeout ?? self.timeout).components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        let timeoutMessage = "\(executable.lastPathComponent) did not finish within \(String(format: "%g", seconds))s "
            + "and was stopped"

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let process = Process()
            process.executableURL = executable
            process.arguments = args
            process.environment = env
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice

            Self.queue.async {
                do {
                    try process.run()
                } catch {
                    once.resume(with: .failure(error))
                    return
                }
                Self.queue.asyncAfter(deadline: .now() + seconds) {
                    guard process.isRunning else { return }
                    // Answer before stopping it: once it ends, the exit wait below could resume first with
                    // the signal's status. Answering now also covers a child that inherited the pipes and
                    // keeps the reads below blocked.
                    once.resume(with: .failure(GhError.failed(timeoutMessage)))
                    process.terminate()
                    Self.queue.asyncAfter(deadline: .now() + 2) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                // Drain both pipes before waiting so a full pipe buffer cannot stall the child.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                Self.queue.async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let stdout = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                once.resume(with: .success((process.terminationStatus, stdout, errBox.data)))
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Resumes a continuation at most once (the process ending and the timeout race).
private final class ResumeOnce: @unchecked Sendable {
    typealias Output = (status: Int32, stdout: Data, stderr: Data)
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, any Error>?

    init(_ continuation: CheckedContinuation<Output, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Output, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<Output, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}

public struct GhAccount: Hashable, Codable, Sendable {
    public let login: String
    public let scopes: Set<String>
    /// gh's active login, the one `gh auth refresh` acts on.
    public let active: Bool

    public init(login: String, scopes: Set<String>, active: Bool = false) {
        self.login = login
        self.scopes = scopes
        self.active = active
    }
}

public extension GhAccount {
    var canReadProjects: Bool { scopes.contains("project") || scopes.contains("read:project") }
}

public extension Array where Element == GhAccount {
    /// Whether `login`'s token can read Projects boards. A login not listed (yet) is assumed to,
    /// until `gh auth status` says otherwise; no login can't.
    func canReadProjects(for login: String?) -> Bool {
        guard let login else { return false }
        return first { $0.login == login }?.canReadProjects ?? true
    }
}

/// One github.com login as `gh auth status` reports it, healthy or not.
public struct GhLogin: Equatable, Sendable {
    public enum Health: Equatable, Sendable {
        case ok
        /// Expired, revoked or otherwise rejected.
        case invalid
        /// gh couldn't reach GitHub to check it.
        case unreachable
    }

    public let login: String
    public let active: Bool
    public let health: Health
    public let scopes: Set<String>

    public init(login: String, active: Bool, health: Health, scopes: Set<String>) {
        self.login = login
        self.active = active
        self.health = health
        self.scopes = scopes
    }

    public var canReadProjects: Bool { scopes.contains("project") || scopes.contains("read:project") }
}

/// What the GitHub CLI setup checklist knows about `gh`; `GhCLI.status()`.
public enum GhStatus: Equatable, Sendable {
    case notInstalled
    /// `gh` is at `gh`; every github.com login, in gh's order (none when nobody is logged in).
    case logins(gh: String, [GhLogin])
    /// `gh auth status` failed or timed out; `message` is the first line of its stderr.
    case failed(gh: String, message: String)
}

public enum GhError: Error, Equatable {
    case notInstalled
    case notLoggedIn(String)
    case failed(String)
}

public struct GhCLI: Sendable {
    /// `gh auth status` checks every login over the network, so it gets longer than other calls.
    public static let authStatusTimeout: Duration = .seconds(45)

    private let runner: ProcessRunning
    private let searchPaths: [String]
    private let fileExists: @Sendable (String) -> Bool

    public init(
        runner: ProcessRunning = SystemProcessRunner(),
        searchPaths: [String] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"],
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.runner = runner
        self.searchPaths = searchPaths
        self.fileExists = fileExists
    }

    public func locate() async throws -> URL {
        if let path = searchPaths.first(where: fileExists) {
            return URL(fileURLWithPath: path)
        }
        let result = try await runner.run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v gh"])
        let path = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.status == 0, !path.isEmpty else { throw GhError.notInstalled }
        return URL(fileURLWithPath: path)
    }

    public func accounts() async throws -> [GhAccount] {
        let gh = try await locate()
        let result = try await runner.run(gh, ["auth", "status", "--json", "hosts"], timeout: Self.authStatusTimeout)
        guard let logins = Self.logins(from: result.stdout) else {
            throw GhError.failed(Self.message(result.stderr, fallback: "gh auth status failed"))
        }
        return logins.filter { $0.health == .ok }
            .map { GhAccount(login: $0.login, scopes: $0.scopes, active: $0.active) }
    }

    /// Where `gh` is and who is logged in, healthy or not; never throws. The same two steps as
    /// `accounts()`: the path lookup, then one `gh auth status`.
    public func status() async -> GhStatus {
        guard let gh = try? await locate() else { return .notInstalled }
        do {
            let result = try await runner.run(
                gh, ["auth", "status", "--json", "hosts"], timeout: Self.authStatusTimeout)
            guard let logins = Self.logins(from: result.stdout) else {
                return .failed(gh: gh.path, message: Self.firstLine(result.stderr, fallback: "gh auth status failed"))
            }
            return .logins(gh: gh.path, logins)
        } catch GhError.failed(let message) {
            return .failed(gh: gh.path, message: message)
        } catch {
            return .failed(gh: gh.path, message: error.localizedDescription)
        }
    }

    /// Homebrew in either of its standard prefixes; the checklist offers `brew install gh` only then.
    public var homebrewInstalled: Bool {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].contains(where: fileExists)
    }

    /// The github.com logins in `gh auth status --json hosts`, one per login: a login listed twice
    /// (e.g. keyring and an environment token) is healthy, active or scoped if any entry is. Nil when
    /// the output isn't that JSON. gh exits non-zero when any account is unhealthy but still prints it.
    static func logins(from data: Data) -> [GhLogin]? {
        guard let status = try? JSONDecoder().decode(AuthStatus.self, from: data) else { return nil }
        var order: [String] = []
        var merged: [String: GhLogin] = [:]
        for entry in status.hosts["github.com"] ?? [] {
            let scopes = entry.state == "success" ? Set((entry.scopes ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }) : []
            let health = Self.health(of: entry)
            guard let previous = merged[entry.login] else {
                order.append(entry.login)
                merged[entry.login] = GhLogin(
                    login: entry.login, active: entry.active ?? false, health: health, scopes: scopes)
                continue
            }
            let best: GhLogin.Health = previous.health == .ok || health == .ok ? .ok
                : previous.health == .unreachable || health == .unreachable ? .unreachable : .invalid
            merged[entry.login] = GhLogin(
                login: entry.login, active: previous.active || (entry.active ?? false), health: best,
                scopes: previous.scopes.union(scopes))
        }
        return order.compactMap { merged[$0] }
    }

    /// gh reports a check it couldn't make as `timeout`, or as an `error` naming the network failure.
    private static func health(of entry: AuthStatus.Entry) -> GhLogin.Health {
        switch entry.state {
        case "success": return .ok
        case "timeout": return .unreachable
        default:
            let error = (entry.error ?? "").lowercased()
            let network = ["dial tcp", "no such host", "network is unreachable", "i/o timeout", "connection refused"]
            return network.contains(where: error.contains) ? .unreachable : .invalid
        }
    }

    private static func firstLine(_ stderr: Data, fallback: String) -> String {
        let text = message(stderr, fallback: fallback)
        return text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? fallback
    }

    public func token(for login: String) async throws -> String {
        let gh = try await locate()
        let result = try await runner.run(gh, ["auth", "token", "--user", login], timeout: nil)
        let stderr = String(decoding: result.stderr, as: UTF8.self)
        guard result.status == 0 else {
            if stderr.lowercased().contains("no oauth token") { throw GhError.notLoggedIn(login) }
            throw GhError.failed(Self.message(result.stderr, fallback: "gh auth token failed"))
        }
        let token = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GhError.notLoggedIn(login) }
        return token
    }

    private static func message(_ stderr: Data, fallback: String) -> String {
        let text = String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    private struct AuthStatus: Decodable {
        struct Entry: Decodable {
            let state: String
            let login: String
            let scopes: String?
            let active: Bool?
            let error: String?
        }
        let hosts: [String: [Entry]]
    }
}
