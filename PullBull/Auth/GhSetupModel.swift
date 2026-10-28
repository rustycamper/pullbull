import AppKit
import Foundation
import Observation
import PullBullKit

/// The "Set Up GitHub CLI" window's state: one `gh` pass when it opens, when PullBull becomes active
/// again (back from Terminal), on Check Now, and every 10 s while it is open until 10 minutes pass
/// without a change.
@MainActor @Observable
final class GhSetupModel {
    let purpose: GhSetupChecklist.Purpose
    private(set) var status: GhStatus?
    private(set) var checking = false
    private(set) var checkedAt: Date?
    /// Passes so far; a `gh` still missing after the first one says where PullBull looks.
    private var passes = 0

    @ObservationIgnored private let app: AppModel?
    @ObservationIgnored private let homebrew: Bool
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(app: AppModel, purpose: GhSetupChecklist.Purpose, gh: GhCLI = GhCLI()) {
        self.app = app
        self.purpose = purpose
        homebrew = gh.homebrewInstalled
    }

    #if DEBUG
    init(previewing status: GhStatus?, purpose: GhSetupChecklist.Purpose = .firstRun, homebrew: Bool = true) {
        app = nil
        self.purpose = purpose
        self.status = status
        self.homebrew = homebrew
        checkedAt = status == nil ? nil : .now
    }
    #endif

    var checklist: GhSetupChecklist {
        GhSetupChecklist.make(
            purpose: purpose, status: status, homebrew: homebrew,
            missedAfterRecheck: passes > 1 && status == .notInstalled)
    }

    func start() {
        guard app != nil, activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
        checkNow()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    /// A pass now; the timed passes start over from it.
    func checkNow() {
        guard app != nil else { return }
        loop?.cancel()
        loop = Task { [weak self] in
            _ = await self?.pass()
            guard let self, !Task.isCancelled else { return }
            _ = await RecheckSchedule.ghSetup.run(clock: ContinuousClock()) {
                await self.pass()
            }
        }
    }

    /// "Use X from GitHub CLI". For a personal board it stays in no-org mode.
    func use(_ login: String) {
        guard let app else { return }
        let personal = if case .board = purpose { true } else { false }
        Task { await app.useGhLogin(login, personal: personal) }
    }

    private func pass() async -> RecheckResult {
        guard let app, !checking else { return .unchanged }
        checking = true
        defer { checking = false }
        let before = checklist
        let previous = status
        // Kept even when Check Now cancelled the loop meanwhile: its own pass was skipped for this one.
        let fresh = await app.ghSetupPass()
        status = fresh
        passes += 1
        checkedAt = Date()
        for line in GhSetupChecklist.announcements(from: before, to: checklist) {
            AccessibilityNotification.Announcement(line).post()
        }
        return GhSetupChecklist.recheckResult(from: previous, to: fresh)
    }
}
