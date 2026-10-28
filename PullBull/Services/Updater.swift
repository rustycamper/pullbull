import Foundation
import Observation
import Sparkle

/// Sparkle's standard updater: a daily check once the user agrees to automatic checks (Sparkle asks on
/// the second launch), and Check for Updates… in Settings and the menu bar item's menu. It starts only
/// in a Developer ID-signed Release build with a Sparkle public key; otherwise `isAvailable` stays false
/// and both items are hidden.
@Observable @MainActor
final class Updater {
    static let shared = Updater()

    /// False while Sparkle is busy with a check or an update, so the items disable themselves.
    private(set) var canCheckForUpdates = false
    private(set) var isAvailable = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    func start() {
        guard controller == nil, Self.isConfigured else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        isAvailable = true
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheckForUpdates = canCheck }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// A local build (Debug, or not signed with Developer ID) would offer to replace itself with the
    /// release, so only release copies update.
    private static var isConfigured: Bool {
        #if DEBUG
        return false
        #else
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.trimmingCharacters(in: .whitespaces).isEmpty && !BuildInfo.isLocalBuild
        #endif
    }
}
