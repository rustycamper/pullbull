import Foundation
import PullBullKit

/// The Anthropic key's state in Settings → Ask.
enum AskKeyState: Equatable {
    /// No key saved.
    case none
    /// The key typed is being checked (`GET /v1/models`).
    case checking
    /// A key is saved; it passed the check when it was saved.
    case valid
    /// The key typed failed the check or couldn't be saved; the Keychain is unchanged.
    case invalid(String)
}

/// The open Ask index of one account and scope, its sync, and the work started on them. Work runs off
/// the main actor; `close()` returns once none of it can write to the index again.
@MainActor
final class AskRuntime {
    let target: AskTarget
    let index: AskIndex
    let sync: AskSync
    /// When the snapshot the last sync followed was fetched, so a snapshot shown again doesn't sync again.
    var syncedAfter: Date?
    private var work: [UUID: Task<Void, Never>] = [:]
    /// The running `sync()` this runtime started; nil when none runs.
    private var syncing: UUID?
    private var progressTask: Task<Void, Never>?

    init(target: AskTarget, index: AskIndex, sync: AskSync) {
        self.target = target
        self.index = index
        self.sync = sync
    }

    /// Hands each progress report of the sync to `show`, until `close()`.
    func listen(_ show: @escaping @MainActor (AskSyncProgress) -> Void) {
        let stream = sync.progress
        progressTask = Task {
            for await progress in stream { show(progress) }
        }
    }

    /// Runs `body` in a detached task.
    func run(_ body: @escaping @Sendable (AskSync, AskIndex) async -> Void) {
        start(body)
    }

    /// Starts a sync unless the last one started here still runs.
    func syncNow() {
        guard syncing == nil else { return }
        syncing = start { sync, _ in await sync.sync() }
    }

    /// Stops the sync and waits for the work started here. A rebuild or repo backfill that was queued
    /// behind the pass can start one after `cancel()` returns, so cancelling repeats until all of it ended.
    func close() async {
        progressTask?.cancel()
        repeat {
            await sync.cancel()
            if !work.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        } while !work.isEmpty
    }

    @discardableResult
    private func start(_ body: @escaping @Sendable (AskSync, AskIndex) async -> Void) -> UUID {
        let id = UUID()
        let sync = sync
        let index = index
        work[id] = Task.detached(priority: .utility) { [weak self] in
            await body(sync, index)
            await self?.finish(id)
        }
        return id
    }

    private func finish(_ id: UUID) {
        work[id] = nil
        if syncing == id { syncing = nil }
    }
}

// MARK: - Lifecycle

extension AppModel {
    /// What Ask should index now: the running account and scope, while Ask is on and that account is
    /// signed in.
    private var wantedAskTarget: AskTarget? {
        guard settings.askEnabled, !isSignedOut else { return nil }
        return runningAskTarget
    }

    /// The open Ask index and its sync; nil while Ask is off, no account runs, or the open failed.
    var askRuntime: AskRuntime? { askLifecycle?.runtime }

    /// Opens, switches or closes the Ask index to match the setting and the running account and scope.
    /// `AskLifecycle` keeps at most one index open and stops the old sync before another opens.
    func reconcileAsk() {
        let lifecycle = askLifecycle ?? makeAskLifecycle()
        askLifecycle = lifecycle
        if !settings.askEnabled { askOpenError = nil }
        lifecycle.update(wanted: wantedAskTarget, enabled: settings.askEnabled)
    }

    /// Turns Ask on (the index opens and its backfill starts) or off (the sync stops, then every Ask
    /// index file is deleted unless Ask is on again by then).
    func setAskEnabled(_ on: Bool) {
        guard settings.askEnabled != on else { return }
        settings.askEnabled = on
        reconcileAsk()
    }

    /// Returns once the Ask index matches the running account and scope, so the files of an account
    /// that stopped running or is signed out can be deleted (sign-out, a renamed login).
    func settleAsk() async {
        reconcileAsk()
        await askLifecycle?.idle()
    }

    /// A refresh brought a fresh snapshot: the index fetches what changed since its last sync.
    func syncAskAfterRefresh(_ status: RefreshStatus) {
        guard let runtime = askRuntime, !status.isRefreshing, status.error == nil,
              let fetchedAt = snapshot?.fetchedAt, runtime.syncedAfter != fetchedAt
        else { return }
        runtime.syncedAfter = fetchedAt
        runtime.syncNow()
    }

    /// A detail fetch found `key` gone: its row leaves the index.
    func askItemNotFound(_ key: PRKey) {
        guard let runtime = askRuntime else { return }
        runtime.run { [weak self] _, index in
            try? await index.delete(keys: [key])
            await self?.showAskCount(of: index, for: runtime)
        }
    }

    /// Saves the exclude list. Added repos lose their rows; removed ones are fetched over the window.
    func setAskExcluded(_ repos: [String]) {
        var kept = Set<String>()
        let unique = repos.filter { kept.insert($0.lowercased()).inserted }
        let before = askExcludedRepos()
        settings.askExcludedRepos = unique
        let added = kept.subtracting(before)
        let removed = before.subtracting(kept)
        guard let runtime = askRuntime, !added.isEmpty || !removed.isEmpty else { return }
        runtime.run { [weak self] sync, index in
            if !added.isEmpty {
                try? await index.delete(repos: added)
                await self?.showAskCount(of: index, for: runtime)
            }
            for repo in removed.sorted() {
                await sync.backfill(repo: repo)
            }
        }
    }

    /// Deletes every row and syncs from scratch.
    func rebuildAskIndex() {
        askRuntime?.run { sync, _ in await sync.rebuild() }
    }

    /// Repos (`owner/name`) of the running scope that aren't excluded yet, for the exclude list's menu.
    var askExcludeCandidates: [String] {
        guard let context = snapshot?.org else { return [] }
        let excluded = askExcludedRepos()
        return context.repos
            .map { "\(context.org)/\($0)" }
            .filter { !excluded.contains($0.lowercased()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The exclude list, lowercased, as `AskSync` and `AskIndex` compare it.
    func askExcludedRepos() -> Set<String> {
        Set(settings.askExcludedRepos.map { $0.lowercased() })
    }

    private func makeAskLifecycle() -> AskLifecycle<AskRuntime> {
        let store = snapshotStore
        return AskLifecycle(
            open: { [unowned self] target in try self.openAsk(target) },
            close: { [unowned self] runtime in
                self.askProgress = nil
                await runtime.close()
            },
            removeFiles: { try? await store.removeAskIndexes() })
    }

    private func openAsk(_ target: AskTarget) throws -> AskRuntime {
        let url = snapshotStore.askIndexURL(account: target.account.login, scope: target.scope)
        let index: AskIndex
        do {
            index = try AskIndex(fileURL: url)
        } catch {
            let reason = (error as? AskIndex.IndexError)?.message ?? error.localizedDescription
            askOpenError = "Couldn't open the Ask index (\(reason))."
            throw error
        }
        askOpenError = nil
        let sync = AskSync(
            index: index, fetcher: api(for: target.account), scope: target.scope,
            excluded: { [weak self] in await self?.askExcludedRepos() ?? [] },
            refreshing: { [weak self] in await self?.isRefreshingForAsk() ?? false })
        let runtime = AskRuntime(target: target, index: index, sync: sync)
        runtime.listen { [weak self] progress in
            guard let self, self.askRuntime === runtime else { return }
            self.askProgress = progress
        }
        runtime.run { [weak self] _, index in await self?.showAskCount(of: index, for: runtime) }
        // A backfill when the index is new or unfinished, else what changed since its last sync.
        runtime.syncNow()
        return runtime
    }

    private func isRefreshingForAsk() -> Bool { status.isRefreshing }

    /// Shows the index's row count and last sync, as when it opens or rows were deleted.
    private func showAskCount(of index: AskIndex, for runtime: AskRuntime) async {
        let indexed = (try? await index.count()) ?? 0
        let lastSync = (try? await index.meta(.lastSync)) ?? nil
        guard askRuntime === runtime else { return }
        askProgress = AskSyncProgress(
            indexed: indexed, estimatedTotal: askProgress?.estimatedTotal,
            backfilling: askProgress?.backfilling ?? false, lastSync: lastSync)
    }
}

// MARK: - Anthropic key

extension AppModel {
    /// Reads whether a key is saved. No network.
    func loadAskKeyState() {
        guard askKeyState != .checking else { return }
        let saved = (try? AnthropicKeyStore().load()) ?? nil
        askKeyState = saved == nil ? .none : .valid
    }

    /// Checks `key` with Anthropic (`GET /v1/models`) and saves it only when the check passes. The
    /// only call to Anthropic outside an Ask.
    func saveAskKey(_ key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.askEnabled, !key.isEmpty, askKeyState != .checking else { return }
        askKeyState = .checking
        do {
            try await AskClient.checkKey(key)
        } catch {
            askKeyState = .invalid(Self.askKeyCheckMessage(error))
            return
        }
        do {
            try AnthropicKeyStore().save(key)
            askKeyState = .valid
        } catch {
            askKeyState = .invalid("Not saved: the Keychain refused the key.")
        }
    }

    func removeAskKey() {
        do {
            try AnthropicKeyStore().delete()
            askKeyState = .none
        } catch {
            askKeyState = .invalid("The Keychain refused to remove the key.")
        }
    }

    private static func askKeyCheckMessage(_ error: any Error) -> String {
        switch error as? AskError {
        case .unauthorized: "Not saved: Anthropic rejected this key."
        case .offline: "Not saved: no network to check the key."
        case .rateLimited: "Not saved: Anthropic is rate limiting. Try again shortly."
        case .timeout: "Not saved: the check timed out."
        case .server(let code): "Not saved: Anthropic answered \(code)."
        default: "Not saved: the key couldn't be checked."
        }
    }
}
