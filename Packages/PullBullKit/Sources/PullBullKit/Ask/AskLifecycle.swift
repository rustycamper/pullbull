import Foundation

/// The account and scope an Ask index belongs to.
public struct AskTarget: Equatable, Sendable {
    public let account: AccountRef
    public let scope: FetchScope

    public init(account: AccountRef, scope: FetchScope) {
        self.account = account
        self.scope = scope
    }
}

/// Keeps at most one Ask index open, for the account and scope Ask should index now. One worker
/// settles every change in order. It closes the open runtime before another opens, and deletes the
/// index files only while Ask is off and nothing is open, so no file goes from under an open index.
@MainActor
public final class AskLifecycle<Runtime: AnyObject> {
    /// The open runtime; nil while Ask is off, no account runs, or the open failed.
    public private(set) var runtime: Runtime?
    /// The target `runtime` was opened for.
    public private(set) var openTarget: AskTarget?

    private let open: @MainActor (AskTarget) throws -> Runtime
    private let close: @MainActor (Runtime) async -> Void
    private let removeFiles: @MainActor () async -> Void

    private var wanted: AskTarget?
    private var enabled = false
    /// Ask went off: the files go once the open runtime has closed, unless Ask is on again by then.
    private var removalPending = false
    /// The open of this target failed; it isn't tried again until the wanted target changes.
    private var failedTarget: AskTarget?
    private var worker: Task<Void, Never>?

    public init(
        open: @escaping @MainActor (AskTarget) throws -> Runtime,
        close: @escaping @MainActor (Runtime) async -> Void,
        removeFiles: @escaping @MainActor () async -> Void
    ) {
        self.open = open
        self.close = close
        self.removeFiles = removeFiles
    }

    /// Ask should index `wanted` (nil: nothing) and is `enabled` or not. Turning it off deletes the
    /// index files once nothing is open.
    public func update(wanted: AskTarget?, enabled: Bool) {
        if self.enabled, !enabled { removalPending = true }
        if enabled { removalPending = false }
        self.enabled = enabled
        let wanted = enabled ? wanted : nil
        if wanted != self.wanted { failedTarget = nil }
        self.wanted = wanted
        guard worker == nil else { return }
        worker = Task { await self.settle() }
    }

    /// Returns once every change so far has been settled.
    public func idle() async {
        while let worker {
            await worker.value
        }
    }

    /// Closes, deletes and opens until the state matches the latest `update`. State is read afresh
    /// after each wait, so changes made meanwhile are settled too; the last check and the end of the
    /// worker happen without a wait between them.
    private func settle() async {
        while true {
            if let current = runtime, openTarget != wanted {
                runtime = nil
                openTarget = nil
                await close(current)
                continue
            }
            if removalPending, !enabled, runtime == nil {
                removalPending = false
                await removeFiles()
                continue
            }
            if runtime == nil, let wanted, wanted != failedTarget {
                do {
                    runtime = try open(wanted)
                    openTarget = wanted
                } catch {
                    failedTarget = wanted
                }
            }
            break
        }
        worker = nil
    }
}
