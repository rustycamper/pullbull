import Foundation

public enum MergeAction: Equatable, Sendable { case merge, mergeWhenReady }

public enum MergeOffer: Equatable, Sendable {
    case action(MergeAction)
    case cancelAutoMerge
    /// A line for the detail, with Open on GitHub.
    case reason(String)
    /// The install or login can't do this yet: `EditPermission.note(for: .merge)` and its link.
    case permission(EditPermission)
    /// GitHub hasn't worked it out; read again.
    case waiting
    /// Nothing at all: no button, no line.
    case hidden
}

public enum MergeGate {
    /// `state` and `info` are what's on screen, with the overlay laid over them, so a merge on its way offers nothing.
    public static func offer(state: PRState?, info: MergeInfo?, viewer: String?, permission: EditPermission) -> MergeOffer {
        guard state == .open, let info, !info.isDraft, info.canWrite != false else { return .hidden }

        func button(_ offer: MergeOffer) -> MergeOffer {
            permission == .ready ? offer : .permission(permission)
        }

        if info.isStacked { return .reason("Part of a stack. Merge it on GitHub.") }
        if info.usesMergeQueue { return .reason("Uses a merge queue. Add it on GitHub.") }

        if let auto = info.autoMerge {
            if let name = auto.enabledBy, let viewer, name.caseInsensitiveCompare(viewer) == .orderedSame, info.canDisableAutoMerge {
                return button(.cancelAutoMerge)
            }
            return .reason(auto.enabledBy.map { "Auto-merge set by @\($0). Change it on GitHub." }
                ?? "Auto-merge is set. Change it on GitHub.")
        }

        let rules = MergeOffer.reason("This branch's rules aren't met yet.")
        switch info.status {
        case .clean, .unstable, .hasHooks:
            return info.allowedMethods.isEmpty ? rules : button(.action(.merge))
        case .blocked where info.canEnableAutoMerge:
            return info.allowedMethods.isEmpty ? rules : button(.action(.mergeWhenReady))
        default:
            break
        }

        if info.hasConflicts || info.status == .dirty { return .reason("Merge conflicts. Resolve them on GitHub.") }
        switch info.status {
        case .behind: return .reason("Behind the base branch. Update it on GitHub.")
        case .blocked: return rules
        default: return .waiting
        }
    }
}

/// GitHub is still working it out, or a read just after a review can show a stale `BLOCKED`.
public enum MergeRetry {
    public static let limit = 3
    public static let interval: Duration = .seconds(2)

    public static func shouldRetry(_ info: MergeInfo?, afterReview: Bool) -> Bool {
        switch info?.status {
        case .unknown: true
        case .blocked: afterReview
        default: false
        }
    }
}
