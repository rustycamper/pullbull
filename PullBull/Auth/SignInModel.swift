import AppKit
import Foundation
import Observation
import PullBullKit

enum SignInOutcome: Equatable {
    case ready(GitHubIdentity)
    case needsApproval(GitHubIdentity, org: String, installURL: URL)
    /// No org, and PullBull isn't installed on the user's own account: the window stays open on
    /// "Choose the repositories PullBull can see".
    case needsPersonalInstall(GitHubIdentity)
    case differentLogin(GitHubIdentity, stillSignedOut: String)
    /// GitHub couldn't be reached to read who signed in; nothing was saved.
    case unreachable
    /// The Keychain refused the sign-in. `needsSignedBuild` when the build isn't team-signed.
    case saveFailed(needsSignedBuild: Bool)
}

@MainActor @Observable
final class SignInModel {
    enum Phase: Equatable {
        case requesting(unreachable: Bool)
        case code(userCode: String, url: URL, expiresAt: Date, unreachable: Bool)
        case finishing
        case signedIn(SignInOutcome)
        case expired, denied, tooManyCodes, misconfigured
    }

    private(set) var phase: Phase = .requesting(unreachable: false)
    /// Check Again is reading the org's installations.
    private(set) var checking = false

    private let config: GitHubAppConfig?
    private let complete: @MainActor (TokenGrant) async -> SignInOutcome
    private let checkApproval: @MainActor () async -> Bool
    private var task: Task<Void, Never>?

    /// `checkApproval` reads the org's installations again and returns true once it has approved PullBull.
    init(
        config: GitHubAppConfig?, complete: @escaping @MainActor (TokenGrant) async -> SignInOutcome,
        checkApproval: @escaping @MainActor () async -> Bool
    ) {
        self.config = config
        self.complete = complete
        self.checkApproval = checkApproval
    }

    #if DEBUG
    init(previewing phase: Phase) {
        config = nil
        complete = { _ in .unreachable }
        checkApproval = { false }
        self.phase = phase
    }
    #endif

    /// Check Again from the needs-approval state: an org that approved PullBull meanwhile turns it into
    /// the signed-in state.
    func checkAgain() async {
        guard !checking, case .signedIn(.needsApproval(let identity, _, _)) = phase else { return }
        checking = true
        defer { checking = false }
        let approved = await checkApproval()
        guard approved, case .signedIn(.needsApproval) = phase else { return }
        phase = .signedIn(.ready(identity))
    }

    func start() {
        task?.cancel()
        guard let config else {
            phase = .misconfigured
            task = nil
            return
        }
        phase = .requesting(unreachable: false)
        let session = DeviceFlowSession(
            client: DeviceFlowClient(clientID: config.clientID, transport: URLSessionHTTPTransport()))
        task = Task { [weak self] in
            for await event in session.run() {
                if Task.isCancelled { return }
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func copyCodeAndOpenGitHub() {
        guard case .code(let userCode, let url, _, _) = phase else { return }
        PasteboardCopy.copyCode(userCode)
        NSWorkspace.shared.open(url)
    }

    func copyCode() {
        guard case .code(let userCode, _, _, _) = phase else { return }
        PasteboardCopy.copyCode(userCode)
    }

    private func handle(_ event: DeviceFlowEvent) async {
        switch event {
        case .code(let userCode, let url, let expiresAt):
            phase = .code(userCode: userCode, url: url, expiresAt: expiresAt, unreachable: false)
        case .unreachable:
            setUnreachable(true)
        case .waiting:
            setUnreachable(false)
        case .granted(let grant):
            phase = .finishing
            let outcome = await complete(grant)
            if Task.isCancelled { return }
            phase = .signedIn(outcome)
        case .expired: phase = .expired
        case .denied: phase = .denied
        case .tooManyCodes: phase = .tooManyCodes
        case .misconfigured: phase = .misconfigured
        }
    }

    private func setUnreachable(_ value: Bool) {
        switch phase {
        case .requesting:
            phase = .requesting(unreachable: value)
        case .code(let userCode, let url, let expiresAt, _):
            phase = .code(userCode: userCode, url: url, expiresAt: expiresAt, unreachable: value)
        default:
            break
        }
    }
}
