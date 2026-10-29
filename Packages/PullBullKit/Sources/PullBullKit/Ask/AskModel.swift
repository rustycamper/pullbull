import Foundation

/// A Claude model Ask can use. `all` is the fallback list; the key check on save replaces it with the
/// newest Sonnet and Haiku the key can use, so a retired model needs no release.
public struct AskModel: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let all: [AskModel] = [
        AskModel(id: "claude-sonnet-5-5", name: "Sonnet 5.5"),
        AskModel(id: "claude-haiku-5-5", name: "Haiku 5.5"),
    ]

    public static let `default` = all[0]

    /// The families Ask offers, best first.
    static let families = ["sonnet", "haiku"]

    /// The model with this ID; an unknown or retired ID falls back to `default`.
    public static func named(_ id: String) -> AskModel {
        named(id, in: all)
    }

    /// The model with this ID among `choices`; an unknown or retired ID falls back to the first choice.
    public static func named(_ id: String, in choices: [AskModel]) -> AskModel {
        choices.first { $0.id == id } ?? choices.first ?? .default
    }

    /// The models to offer: the ones the last key check found, or `all` before any check.
    public static func choices(_ checked: [AskModel]) -> [AskModel] {
        checked.isEmpty ? all : checked
    }

    /// The choices and chosen model after the Messages API reported `id` unknown: `id` leaves the choices,
    /// and only when it was the chosen one does the next take over. Nil when it was the last choice, since
    /// an empty list would bring back `all`; saving the key again refreshes it.
    public static func retiring(_ id: String, from choices: [AskModel], chosen: String) -> (choices: [AskModel], chosen: String)? {
        let remaining = choices.filter { $0.id != id }
        guard !remaining.isEmpty else { return nil }
        return (remaining, chosen == id ? remaining[0].id : chosen)
    }

    /// The newest model of each family in `listed` (the Models API lists newest first), in family order.
    /// Empty when none of the families is listed.
    public static func offered(from listed: [AskModel]) -> [AskModel] {
        families.compactMap { family in listed.first { $0.id.contains(family) } }
    }
}
