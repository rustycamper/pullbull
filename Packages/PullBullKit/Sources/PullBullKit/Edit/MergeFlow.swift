import Foundation

public enum MergeRequestState: Equatable, Sendable {
    case pending(uuid: String), merged, autoMergeSet, enqueued, failed(String)
}

public enum MergeOutcome: Equatable, Sendable {
    case merged, autoMergeSet, cancelled, headMoved
    case notOpen(merged: Bool)
    /// Nothing went through. With an action the panel shows the read and disarms; with none it closes.
    case changed(MergeRead)
    case checkFailed(String)
    case refused(String)
    case unknown
}

public enum AutoMergeCancelOutcome: Equatable, Sendable { case cancelled, refused(String), unknown }

/// Reads the pull request again, then sends only when it still looks as it did in the panel.
public enum MergeFlow {
    public static let pollInterval: Duration = .seconds(1)
    public static let pollLimit = 30

    /// GitHub's reads trail its writes by about 1.5 s, so one read can miss a write that landed.
    public static let unknownReads = 3
    public static let unknownReadGap: Duration = .seconds(2)

    static let notReachable = "PullBull can't reach this repository. Add it to the install on GitHub."

    @MainActor public static func run(
        shown: MergeFacts, isCancelled: () -> Bool,
        read: @MainActor () async throws -> MergeRead,
        willSend: () -> Void,
        send: @MainActor () async throws -> MergeRequestState,
        poll: @MainActor (String) async throws -> MergeRequestState,
        sleep: @MainActor (Duration) async throws -> Void
    ) async -> MergeOutcome {
        let fresh: MergeRead
        do {
            fresh = try await read()
        } catch {
            if isCancelled() { return .cancelled }
            return .checkFailed(reason(for: error))
        }
        if isCancelled() { return .cancelled }
        guard let state = fresh.facts.state else { return .changed(fresh) }
        guard state == .open else { return .notOpen(merged: state == .merged) }
        guard fresh.facts.head == shown.head else { return .headMoved }
        guard fresh.facts == shown, fresh.facts.action != nil else { return .changed(fresh) }

        willSend()
        let sent: MergeRequestState
        do {
            sent = try await send()
        } catch {
            switch CommentFailure.classify(error) {
            case .refused(let reason): return await refusal(reason, shown: shown, read: read)
            case .unknown: return .unknown
            }
        }
        switch sent {
        case .merged: return .merged
        case .autoMergeSet: return .autoMergeSet
        case .enqueued: return .unknown
        case .failed(let reason): return await refusal(reason, shown: shown, read: read)
        case .pending(let uuid): return await polling(uuid, shown: shown, poll: poll, sleep: sleep, read: read)
        }
    }

    /// What a read before sending failed on: GitHub's words, or the refresh wording for anything else.
    public static func reason(for error: any Error) -> String {
        switch CommentFailure.classify(error) {
        case .refused(let reason): reason
        case .unknown: RefreshError(error).message
        }
    }

    /// Whether `detail` shows what was sent, when GitHub's answer didn't say. An auto-merge can land at once,
    /// so a merged PR counts for it too. Only the viewer's own request counts as theirs. A draft flip landed
    /// when the detail's merge state shows it.
    public static func landed(_ sent: EditChange, in detail: PRDetail) -> Bool {
        switch sent {
        case .merged:
            return detail.state == .merged
        case .autoMerge(enabled: true, let viewer):
            if detail.state == .merged { return true }
            guard detail.state == .open, let name = detail.merge?.autoMerge?.enabledBy else { return false }
            return name.caseInsensitiveCompare(viewer) == .orderedSame
        case .draft(let isDraft, _):
            return detail.merge?.isDraft == isDraft
        case .status, .labels, .assignees, .reviewers, .review, .autoMerge:
            return false
        }
    }

    /// Reads up to `unknownReads` times, `unknownReadGap` apart, until `sent` shows. A failed read counts as
    /// one; `last` is the newest read that succeeded. A throwing sleep ends the reads with what it has.
    @MainActor public static func confirmLanded(
        _ sent: EditChange, read: @MainActor () async throws -> PRDetail,
        sleep: @MainActor (Duration) async throws -> Void
    ) async -> (landed: Bool, last: PRDetail?) {
        var last: PRDetail?
        for attempt in 0..<unknownReads {
            if attempt > 0 {
                do { try await sleep(unknownReadGap) } catch { break }
            }
            guard let fresh = try? await read() else { continue }
            last = fresh
            if landed(sent, in: fresh) { return (true, last) }
        }
        return (false, last)
    }

    /// Anything the poll or the sleep throws is unknown: GitHub accepted the merge, so calling it refused
    /// would report the reverse.
    @MainActor private static func polling(
        _ uuid: String, shown: MergeFacts, poll: @MainActor (String) async throws -> MergeRequestState,
        sleep: @MainActor (Duration) async throws -> Void, read: @MainActor () async throws -> MergeRead
    ) async -> MergeOutcome {
        for _ in 0..<pollLimit {
            do {
                try await sleep(pollInterval)
                switch try await poll(uuid) {
                case .merged: return .merged
                case .failed(let reason): return await refusal(reason, shown: shown, read: read)
                case .pending: continue
                case .autoMergeSet, .enqueued: return .unknown
                }
            } catch {
                return .unknown
            }
        }
        return .unknown
    }

    /// Reads once more to say why: a moved head whatever GitHub's words were, a PR that merged or closed meanwhile, a PR that turned clean as
    /// a fresh read, a repository left out of the install clearly; otherwise GitHub's reason.
    @MainActor private static func refusal(
        _ reason: String, shown: MergeFacts, read: @MainActor () async throws -> MergeRead
    ) async -> MergeOutcome {
        let fresh = try? await read()
        if let state = fresh?.facts.state, state != .open { return .notOpen(merged: state == .merged) }
        if let fresh, let head = fresh.facts.head, head != shown.head { return .headMoved }
        if let fresh, reason.contains("clean status") { return .changed(fresh) }
        if reason.contains("Resource not accessible by integration") { return .refused(notReachable) }
        return .refused(reason)
    }

    @MainActor public static func cancelAutoMerge(
        send: @MainActor () async throws -> Void,
        stillSet: @MainActor () async throws -> Bool
    ) async -> AutoMergeCancelOutcome {
        do {
            try await send()
            return .cancelled
        } catch {
            switch CommentFailure.classify(error) {
            case .refused(let reason): return .refused(reason)
            case .unknown:
                guard let set = try? await stillSet() else { return .unknown }
                return set ? .unknown : .cancelled
            }
        }
    }
}
