import Foundation

public enum AskOutcome: Equatable, Sendable {
    /// `rows` follow the model's result order, built from the index items that were sent to it.
    case answered(question: String, answer: AskAnswer, rows: [AskItem], stillSyncing: Int?)
    case failed(question: String, AskError)
}

/// One Ask end to end: first candidates from the local index, `search_local` follow-ups from the same
/// index, then the answer's rows.
public struct AskSession: Sendable {
    public static let firstCards = 20
    public static let moreCards = 10
    /// Extra rows fetched so dropping out-of-scope or excluded ones rarely shrinks a batch.
    private static let overfetch = 10

    private let index: AskIndex
    private let client: AskClient
    private let context: AskContext
    /// Lowercased `owner/name`.
    private let excluded: Set<String>
    private let scope: FetchScope

    public init(index: AskIndex, client: AskClient, context: AskContext, excluded: Set<String>, scope: FetchScope) {
        self.index = index
        self.client = client
        self.context = context
        self.excluded = excluded
        self.scope = scope
    }

    /// Runs one Ask. Only cancellation is thrown (`CancellationError`, or `URLError.cancelled` as a
    /// cancelled request reports it); the caller ignores it. Every other failure is `.failed`: an
    /// `AskError` as the client reports it, anything unexpected as `.server(0)`.
    public func run(_ question: String, focusedRepo: String?, stillSyncing: Int?) async throws -> AskOutcome {
        let sent = SentItems()
        do {
            let first = try await candidates(question, limit: Self.firstCards, shown: [], repo: focusedRepo)
            sent.add(first)
            let answer = try await client.ask(question, candidates: first, context: context) { query, shown in
                try Task.checkCancellation()
                let batch = try await candidates(query, limit: Self.moreCards, shown: shown, repo: focusedRepo)
                sent.add(batch)
                return batch
            }
            try Task.checkCancellation()
            let rows = answer.results.compactMap { sent.item($0.key) }
            return .answered(question: question, answer: answer, rows: rows, stillSyncing: stillSyncing)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch where Task.isCancelled {
            throw CancellationError()
        } catch let error as AskError {
            return .failed(question: question, error)
        } catch {
            return .failed(question: question, .server(0))
        }
    }

    /// Index hits for `query` that are in scope and not excluded, at most `limit`.
    private func candidates(_ query: String, limit: Int, shown: Set<PRKey>, repo: String?) async throws -> [AskItem] {
        let found = try await index.search(query, limit: limit + Self.overfetch, excluding: shown, repo: repo)
        let allowed = found.filter { scope.covers($0.key.repo) && !excluded.contains($0.key.repo.lowercased()) }
        return Array(allowed.prefix(limit))
    }
}

/// The items sent to the model so far, by key.
private final class SentItems: @unchecked Sendable {
    private let lock = NSLock()
    private var byKey: [PRKey: AskItem] = [:]

    func add(_ items: [AskItem]) {
        lock.withLock { for item in items { byKey[item.key] = item } }
    }

    func item(_ key: PRKey) -> AskItem? { lock.withLock { byKey[key] } }
}
