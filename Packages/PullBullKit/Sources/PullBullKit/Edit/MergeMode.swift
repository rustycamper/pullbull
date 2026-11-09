import Foundation

public enum MergePhase: Sendable { case reading, ready, confirming }

/// What the panel shows, frozen, and what confirming compares against.
public struct MergeFacts: Equatable, Sendable {
    public let head: String?, base: String
    public let state: PRState?
    /// Nil when the read offers nothing any more. A detail with no `merge` gives nil and zero counts.
    public let action: MergeAction?
    public let tally: CheckTally
    public let approvals: Int
    public let changesRequested: Bool

    public init(detail: PRDetail, offer: MergeOffer) {
        head = detail.headOid
        state = detail.state
        if case .action(let action) = offer { self.action = action } else { action = nil }
        base = detail.merge?.base ?? ""
        tally = detail.merge?.tally ?? CheckTally(failing: 0, running: 0, total: 0)
        approvals = detail.merge?.approvals ?? 0
        changesRequested = detail.merge?.changesRequested ?? false
    }
}

/// One read: what's compared, and what the panel freezes.
public struct MergeRead: Equatable, Sendable {
    public let facts: MergeFacts
    public let info: MergeInfo?

    public init(detail: PRDetail, offer: MergeOffer) {
        facts = MergeFacts(detail: detail, offer: offer)
        info = detail.merge
    }
}

public enum MergeWarning: Equatable, Sendable {
    case checksFailing(Int), checksRunning(Int), noChecks, changesRequested

    public var text: String {
        switch self {
        case .checksFailing(let n): n == 1 ? "1 check is failing." : "\(n) checks are failing."
        case .checksRunning(let n): n == 1 ? "1 check is still running." : "\(n) checks are still running."
        case .noChecks: "No checks have reported on this commit."
        case .changesRequested: "A review is requesting changes."
        }
    }
}

public struct MergeMode: Equatable, Sendable {
    public static let armDelay: TimeInterval = 0.5
    public static let secondStepDelay: TimeInterval = 0.3

    public let key: PRKey
    public let pinnedHead: String
    /// The comment field had focus when the panel opened, so closing it with Esc or Cancel gives it back.
    public let fieldHadFocus: Bool
    /// Frozen at each `show`, and all the panel reads, so nothing changes under the viewer.
    public private(set) var read: MergeRead?
    public var method: MergeMethod?
    public var phase: MergePhase = .reading
    public var isSecondStep = false
    private var armedAt = Date.distantFuture
    private var secondStepAt = Date.distantFuture

    public init(key: PRKey, pinnedHead: String, fieldHadFocus: Bool = false) {
        self.key = key
        self.pinnedHead = pinnedHead
        self.fieldHadFocus = fieldHadFocus
    }

    public var warnings: [MergeWarning] {
        guard let read, read.facts.action == .merge else { return [] }
        var found: [MergeWarning] = []
        let tally = read.facts.tally
        if tally.failing > 0 { found.append(.checksFailing(tally.failing)) }
        if tally.running > 0 { found.append(.checksRunning(tally.running)) }
        if tally.total == 0 { found.append(.noChecks) }
        if read.facts.changesRequested { found.append(.changesRequested) }
        return found
    }

    public var sentence: String? {
        guard let read, let action = read.facts.action else { return nil }
        let target = "#\(key.number) into \(read.facts.base)"
        switch action {
        case .mergeWhenReady:
            return "Merge \(target) when its requirements pass"
        case .merge:
            switch method {
            case .squash: return "Squash and merge \(target)"
            case .rebase: return "Rebase and merge \(target)"
            case .merge, nil: return "Merge \(target)"
            }
        }
    }

    public var summary: String? {
        guard let info = read?.info else { return nil }
        let tally = info.tally
        var parts = [info.commitCount == 1 ? "1 commit" : "\(info.commitCount) commits"]
        if info.approvals > 0 { parts.append(info.approvals == 1 ? "1 approval" : "\(info.approvals) approvals") }
        let noun = tally.total == 1 ? "check" : "checks"
        if tally.failing > 0 {
            parts.append("\(tally.failing) of \(tally.total) \(noun) failing")
        } else if tally.running > 0 {
            parts.append("\(tally.running) of \(tally.total) \(noun) running")
        } else if tally.total > 0 {
            parts.append("\(tally.total) \(noun) passing")
        } else {
            parts.append("no checks")
        }
        return parts.joined(separator: " · ")
    }

    public var methods: [MergeMethod] { read?.info?.allowedMethods ?? [] }

    public var confirmTitle: String { isSecondStep ? "Merge anyway" : "Merge" }

    public func canConfirm(at now: Date) -> Bool {
        guard phase == .ready, read?.facts.action != nil else { return false }
        if now < armedAt.addingTimeInterval(Self.armDelay) { return false }
        if isSecondStep, now < secondStepAt.addingTimeInterval(Self.secondStepDelay) { return false }
        return true
    }

    /// True when this press should send, and the phase is then `.confirming`; false when it only moved
    /// to the second step or did nothing. Does nothing unless the phase is `.ready`.
    public mutating func confirm(at now: Date) -> Bool {
        guard canConfirm(at: now) else { return false }
        if !warnings.isEmpty, !isSecondStep {
            isSecondStep = true
            secondStepAt = now
            return false
        }
        phase = .confirming
        return true
    }

    /// Moves to `.ready`, re-arms and clears the second step, every time. Keeps a chosen method that's
    /// still allowed; otherwise `defaultMethod` if allowed, else the first.
    public mutating func show(_ read: MergeRead, at now: Date) {
        self.read = read
        let allowed = methods
        if method.map(allowed.contains) != true {
            if let preferred = read.info?.defaultMethod, allowed.contains(preferred) {
                method = preferred
            } else {
                method = allowed.first
            }
        }
        phase = .ready
        isSecondStep = false
        armedAt = now
    }

    public mutating func changeMethod(by offset: Int, at now: Date) {
        let allowed = methods
        guard phase == .ready, allowed.count > 1, let method, let index = allowed.firstIndex(of: method) else { return }
        let count = allowed.count
        self.method = allowed[((index + offset) % count + count) % count]
        isSecondStep = false
        armedAt = now
    }
}
