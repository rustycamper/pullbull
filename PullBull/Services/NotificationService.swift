import AppKit
import Observation
import PullBullKit
import UserNotifications

/// What a notification click opens.
enum NotificationTarget: Equatable {
    case pr(PRKey)
    case issue(PRKey)
}

/// Whether macOS lets PullBull post notifications. Read-only: it never asks, so reading it shows no prompt.
@Observable @MainActor
final class NotificationPermission {
    enum State: Equatable {
        case unknown
        case granted
        case denied
    }

    private(set) var state: State

    init(state: State = .unknown) {
        self.state = state
    }

    /// Reads the current authorization (a denied one, or a disabled app in System Settings).
    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        state = switch settings.authorizationStatus {
        case .denied: .denied
        case .notDetermined: .unknown
        default: .granted
        }
    }

    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
}

/// Posts change notifications and routes their clicks back to the app.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var gate = NotificationGate(launchedAt: Date())
    private weak var model: AppModel?
    /// A click that arrived before the model was attached.
    private var pending: NotificationTarget?
    private var installed = false

    /// Called at launch: becomes the delegate so clicks reach the app, and asks for permission
    /// (the system prompts only the first time).
    func install() {
        guard !installed else { return }
        installed = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // The async API: a completion closure formed here would be MainActor-isolated and is called
        // back on a background queue.
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    func attach(_ model: AppModel) {
        guard self.model !== model else { return }
        self.model = model
        if let target = pending {
            pending = nil
            open(target)
        }
    }

    /// Account or org changed: the next live fetch is a fresh baseline.
    func resetBaseline() {
        gate.reset()
    }

    /// Feeds one coordinator update; posts what changed since the previous live fetch.
    func process(
        _ snapshot: Snapshot?, _ status: RefreshStatus, toggles: NotificationToggles, filters: ReviewFilters
    ) {
        post(gate.changes(snapshot: snapshot, status: status, toggles: toggles, filters: filters, now: Date()))
    }

    func post(_ changes: NotificationChanges) {
        guard !changes.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let model = model
        Task {
            for event in changes.prs {
                var subtitle = event.notificationSubtitle
                if event.kind == .ciFailed, let checks = await model?.checksForNotification(event.pr.key) {
                    subtitle = PREvent.ciSubtitle(checks)
                }
                let request = await request(
                    event.notificationTitle, subtitle, event.notificationBody, key: event.pr.key, kind: "pr",
                    avatarOf: event.actor)
                try? await center.add(request)
            }
            for event in changes.issues {
                let request = await request(
                    event.notificationTitle, event.notificationSubtitle, event.notificationBody,
                    key: event.issue.key, kind: "issue", avatarOf: event.actor)
                try? await center.add(request)
            }
        }
    }

    private func request(
        _ title: String, _ subtitle: String?, _ body: String, key: PRKey, kind: String, avatarOf login: String?
    ) async -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.sound = .default
        content.threadIdentifier = "\(key.repo)#\(key.number)"
        content.userInfo = ["kind": kind, "repo": key.repo, "number": key.number]
        if let login, let attachment = await Self.avatarAttachment(login) { content.attachments = [attachment] }
        return UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    }

    /// The actor's avatar, round, as the banner's image. Nil when it can't be fetched: the banner goes
    /// out without one rather than waiting.
    private static func avatarAttachment(_ login: String) async -> UNNotificationAttachment? {
        guard let url = URL(string: "https://avatars.githubusercontent.com/\(login)"),
              let image = await AvatarCache.shared.image(for: url),
              let png = round(image, side: 128)
        else { return nil }
        // The system moves the file into its own store when the attachment is made.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        guard (try? png.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "avatar", url: file)
    }

    private static func round(_ image: NSImage, side: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        NSBezierPath(ovalIn: rect).addClip()
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Banners also show while the popover is open (the app counts as frontmost then).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        guard let repo = info["repo"] as? String, let number = info["number"] as? Int else { return }
        let key = PRKey(repo: repo, number: number)
        // Notifications posted before issue events carry no kind: they are PRs.
        await open(info["kind"] as? String == "issue" ? .issue(key) : .pr(key))
    }

    private func open(_ target: NotificationTarget) {
        guard let model else {
            pending = target
            return
        }
        switch target {
        case .pr(let key): model.openFromNotification(key)
        case .issue(let key): model.openIssueFromNotification(key)
        }
    }
}
