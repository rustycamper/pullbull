import Foundation

/// What the PR detail offers for the draft flip.
public enum DraftOffer: Equatable, Sendable {
    /// Merge section: the draft line and **Ready for review**.
    case markReady(autoMergeSet: Bool)
    /// Reviewers header: **Convert to draft**.
    case convert
    /// A draft whose install lacks Pull requests write: the note in the Merge section.
    case permission(EditPermission)
    case hidden
}

public enum DraftGate {
    /// The author may flip their own PR even without write access; anyone else needs write. An unknown
    /// `canWrite` counts as allowed: GitHub refuses a flip the viewer can't make.
    public static func offer(
        state: PRState?, info: MergeInfo?, author: String?, viewer: String?, permission: EditPermission
    ) -> DraftOffer {
        guard state == .open, let info, let author, let viewer else { return .hidden }
        let isAuthor = author.caseInsensitiveCompare(viewer) == .orderedSame
        guard isAuthor || info.canWrite != false else { return .hidden }
        guard permission == .ready else { return info.isDraft ? .permission(permission) : .hidden }
        return info.isDraft ? .markReady(autoMergeSet: info.autoMerge != nil) : .convert
    }
}
