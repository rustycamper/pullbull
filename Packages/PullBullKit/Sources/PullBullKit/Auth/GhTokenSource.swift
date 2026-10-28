import Foundation

/// Memoizes `gh auth token --user <login>` per account, in memory only.
/// Concurrent first requests share one `gh` call.
actor GhTokenCache {
    private let gh: GhCLI
    private var tokens: [String: String] = [:]
    private var pending: [String: Task<String, any Error>] = [:]
    /// Bumped by `invalidate`, so a `gh auth token` started before it can't store its old token.
    private var generations: [String: Int] = [:]
    /// The last token the API rejected per login: a second 401 on it is final.
    private var lastRejected: [String: String] = [:]

    init(gh: GhCLI) {
        self.gh = gh
    }

    func token(for login: String) async throws -> String {
        if let token = tokens[login] { return token }
        if let task = pending[login] { return try await task.value }
        let gh = gh
        let generation = generations[login, default: 0]
        let task = Task { try await gh.token(for: login) }
        pending[login] = task
        defer { if generations[login, default: 0] == generation { pending[login] = nil } }
        let token = try await task.value
        if generations[login, default: 0] == generation { tokens[login] = token }
        return token
    }

    /// Drops the cached token, and any request still running, so the next request runs
    /// `gh auth token` again.
    func invalidate(_ login: String) {
        drop(login)
        lastRejected[login] = nil
    }

    /// True the first time `token` is rejected: rerun `gh` and retry. The same token rejected
    /// again is final. Either way the next `token(for:)` asks `gh` again.
    func rejected(_ token: String, for login: String) -> Bool {
        let retry = lastRejected[login] != token
        lastRejected[login] = token
        if tokens[login] == nil || tokens[login] == token { drop(login) }
        return retry
    }

    private func drop(_ login: String) {
        tokens[login] = nil
        pending[login] = nil
        generations[login, default: 0] += 1
    }
}

struct GhTokenSource: TokenSource {
    let cache: GhTokenCache
    let login: String

    func token() async throws -> String {
        try await cache.token(for: login)
    }

    func rejected(_ token: String) async throws -> Bool {
        await cache.rejected(token, for: login)
    }
}
