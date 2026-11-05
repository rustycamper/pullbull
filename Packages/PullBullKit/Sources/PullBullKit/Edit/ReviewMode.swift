import Foundation

public enum ReviewPhase: Sendable {
    case composing, checking, sending
}

/// A detail's comment field while it writes a review: the commit the reader looked at, the verdict, and
/// where the submit is.
public struct ReviewMode: Equatable, Sendable {
    public let key: PRKey
    /// The head commit pinned when review mode opened; the review is sent on it and nothing newer.
    public let head: String
    public var verdict: ReviewVerdict
    public var phase: ReviewPhase = .composing
    /// Request changes was submitted with no text; the placeholder takes the warning colour.
    public var missingText = false

    /// `lastReview` is the viewer's latest review state; having requested changes opens on Request changes.
    public init(key: PRKey, head: String, lastReview: ReviewState?) {
        self.key = key
        self.head = head
        verdict = lastReview == .changesRequested ? .requestChanges : .approve
    }

    public var canCancel: Bool { phase != .sending }
    public var canChangeVerdict: Bool { phase == .composing }

    public mutating func toggleVerdict() {
        guard canChangeVerdict else { return }
        verdict = verdict == .approve ? .requestChanges : .approve
        missingText = false
    }
}

public enum ReviewGate {
    /// Whether the viewer may start a review on this detail: an open PR by someone else, edits allowed.
    /// A detail cached before the head, author and state were stored never qualifies. Drafts qualify;
    /// GitHub's refusal is the answer there.
    public static func canReview(detail: PRDetail?, viewer: String?, permission: EditPermission) -> Bool {
        guard permission == .ready, let detail, let viewer, detail.headOid != nil,
              let author = detail.author, detail.state == .open
        else { return false }
        return author.caseInsensitiveCompare(viewer) != .orderedSame
    }

    /// GitHub requires text on Request changes; whitespace is none.
    public static func canSubmit(_ verdict: ReviewVerdict, text: String) -> Bool {
        verdict == .approve || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The line under the verdict: the pinned commit, the size of the change and the checks.
public struct ReviewSummary: Equatable, Sendable {
    public let text: String
    public let warns: Bool
    /// The checks part of `text` alone; nil when there are no checks to speak of.
    public let checks: String?

    public init(head: String, detail: PRDetail) {
        let files = detail.fileTotal
        var parts = [
            String(head.prefix(7)),
            "\(files) \(files == 1 ? "file" : "files") +\(detail.additionsTotal) −\(detail.deletionsTotal)",
        ]
        let failing = detail.checks.filter { $0.state == .failure || $0.state == .cancelled }.count
        switch detail.ci ?? .none {
        case .success:
            checks = "checks passed"
            warns = false
        case .failure:
            checks = failing == 0 ? "checks failing" : "\(failing) \(failing == 1 ? "check" : "checks") failing"
            warns = true
        case .pending:
            checks = "checks running"
            warns = true
        case .skipped, .cancelled, .none:
            checks = nil
            warns = false
        }
        if let checks { parts.append(checks) }
        text = parts.joined(separator: " · ")
    }
}
