import Foundation
import PullBullKit
import ServiceManagement

/// Registers the app as a login item through `SMAppService.mainApp`. Only a copy in Applications
/// changes it, so test builds and stray downloads leave the installed copy's login item alone.
@MainActor
enum LaunchAtLogin {
    /// The last register/unregister failure, cleared on the next successful change.
    private(set) static var lastError: String?

    /// Fixed for the life of the process: a running app can't move.
    static let isInstalled = InstallLocation.isInstalled(
        bundleURL: Bundle.main.bundleURL, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)

    /// The bundle path that last registered successfully, so launch can tell when the copy has moved.
    private static let registeredPathKey = "launchAtLogin.registeredPath"
    private static let currentPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path

    /// Registered counts as on even while it still needs the user's approval. Setting it does nothing
    /// outside Applications.
    static var isEnabled: Bool {
        get { [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) }
        set {
            guard isInstalled else { return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    UserDefaults.standard.set(currentPath, forKey: registeredPathKey)
                } else {
                    try SMAppService.mainApp.unregister()
                    UserDefaults.standard.removeObject(forKey: registeredPathKey)
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Registered, but the user still has to allow it in System Settings › General › Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// At launch, points an enabled login item at this installed copy when it was registered from
    /// another path (or before paths were remembered). `register()` alone fails on a registered item,
    /// so it unregisters first.
    static func followInstalledCopy() {
        let action = LaunchAtLoginFollow.action(
            installed: isInstalled, status: followStatus(SMAppService.mainApp.status),
            registeredPath: UserDefaults.standard.string(forKey: registeredPathKey), currentPath: currentPath)
        guard action == .reregister else { return }
        try? SMAppService.mainApp.unregister()
        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(currentPath, forKey: registeredPathKey)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func followStatus(_ status: SMAppService.Status) -> LaunchAtLoginFollow.Status {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }
}
