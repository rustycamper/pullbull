import Foundation

/// A Claude model Ask can use. The one list of IDs; updating it is a release step.
public struct AskModel: Hashable, Sendable, Identifiable {
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

    /// The model with this ID; an unknown or retired ID falls back to `default`.
    public static func named(_ id: String) -> AskModel {
        all.first { $0.id == id } ?? .default
    }
}
