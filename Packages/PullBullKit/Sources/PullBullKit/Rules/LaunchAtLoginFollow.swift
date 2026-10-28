import Foundation

/// What launch does to the login item so it follows the installed copy.
public enum LaunchAtLoginFollow {
    /// Mirrors `SMAppService.Status`, so the rule can be tested without ServiceManagement.
    public enum Status: Equatable, Sendable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Unregister, then register from this copy, and remember its path.
        case reregister
    }

    /// Re-registers only an installed copy whose enabled login item was last registered from another
    /// path. A missing path counts as moved, so an item registered before paths were remembered is
    /// repointed once. Never turns the item on, and leaves one awaiting approval as it is.
    public static func action(installed: Bool, status: Status, registeredPath: String?,
                              currentPath: String) -> Action {
        guard installed, status == .enabled, registeredPath != currentPath else { return .none }
        return .reregister
    }
}
