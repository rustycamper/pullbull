import Foundation

public enum DraftOutcome: Equatable, Sendable { case done, refused(String), unknown }

/// Turns GitHub's answer to a draft flip into an outcome. A flip is never sent twice.
public enum DraftFlow {
    /// `send` returns GitHub's `isDraft`. `read` is the newest detail it read, for the caller to store; nil
    /// when it read nothing or every read failed.
    @MainActor public static func run(
        toDraft: Bool, send: @MainActor () async throws -> Bool, read: @MainActor () async throws -> PRDetail,
        sleep: @MainActor (Duration) async throws -> Void
    ) async -> (outcome: DraftOutcome, read: PRDetail?) {
        let sent = EditChange.draft(isDraft: toDraft, viewer: "")
        do {
            if try await send() == toDraft { return (.done, nil) }
        } catch {
            if case .refused(let reason) = CommentFailure.classify(error) {
                return await refusal(reason, sent: sent, read: read)
            }
        }
        let confirmed = await MergeFlow.confirmLanded(sent, read: read, sleep: sleep)
        return (confirmed.landed ? .done : .unknown, confirmed.last)
    }

    /// A refusal leaves nothing in flight, so one read settles it: the PR may already be as asked.
    @MainActor private static func refusal(
        _ reason: String, sent: EditChange, read: @MainActor () async throws -> PRDetail
    ) async -> (outcome: DraftOutcome, read: PRDetail?) {
        let fresh = try? await read()
        if let fresh, MergeFlow.landed(sent, in: fresh) { return (.done, fresh) }
        let shown = reason.contains("Resource not accessible by integration") ? MergeFlow.notReachable : reason
        return (.refused(shown), fresh)
    }
}
