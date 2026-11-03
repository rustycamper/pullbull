import Foundation

/// The folded sections of the pull request list, one map for every account. Recently closed and Team
/// start folded; the others start open. Issues sections share the map under their own keys.
public struct SectionFolds: Codable, Equatable, Sendable {
    /// Folds set by a toggle, by `PRSection.rawValue`; a missing key takes the default.
    private var folded: [String: Bool] = [:]

    public init() {}

    private static func startsFolded(_ section: PRSection) -> Bool {
        section == .recentlyClosed || section == .team
    }

    public func isFolded(_ section: PRSection) -> Bool {
        folded[section.rawValue] ?? Self.startsFolded(section)
    }

    public mutating func toggle(_ section: PRSection) {
        folded[section.rawValue] = !isFolded(section)
    }

    /// The sections shown folded: none while a search is active (results never hide inside a fold; the
    /// stored state is kept for when the search ends) or in a scope without section headers.
    public func shownFolded(in scope: PRScope, searching: Bool) -> Set<PRSection> {
        guard !searching, scope.showsSectionHeaders else { return [] }
        return Set(scope.sections.filter(isFolded))
    }

    /// Only Rest of the board starts folded; the other Issues sections start open.
    public func isFolded(_ section: IssueSection) -> Bool {
        folded[section.rawValue] ?? (section == .restOfBoard)
    }

    public mutating func toggle(_ section: IssueSection) {
        folded[section.rawValue] = !isFolded(section)
    }

    /// The Issues sections shown folded among those `issues` holds: none while a search is active.
    public func shownFolded(issues: IssueList, searching: Bool) -> Set<IssueSection> {
        guard !searching else { return [] }
        return Set(issues.sections.map(\.section).filter { isFolded($0) })
    }

    public init(from decoder: Decoder) throws {
        // A value that can't be read is dropped; the other sections keep theirs.
        folded = try decoder.singleValueContainer().decode([String: Readable<Bool>].self)
            .compactMapValues(\.value)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(folded)
    }
}
