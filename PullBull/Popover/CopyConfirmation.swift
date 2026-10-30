import SwiftUI

/// The quiet "Copied" after Copy as Markdown Link and Copy Checkout Command: the footer's age slot (the
/// search footer's leading hint) and the detail header's link button read it for 1.5 s, in place, so
/// nothing moves. VoiceOver hears it at once.
@MainActor @Observable
final class CopyConfirmation {
    static let shared = CopyConfirmation()

    /// "Copied Markdown link" or "Copied checkout command" while it shows; nil otherwise.
    private(set) var message: String?
    private var generation = 0

    func show(_ message: String) {
        self.message = message
        generation += 1
        let shown = generation
        AccessibilityNotification.Announcement(message).post()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            // A newer copy keeps its own full 1.5 s.
            if generation == shown { self.message = nil }
        }
    }
}

/// "✓ Copied Markdown link" in a footer, in its 11 pt secondary text. VoiceOver already heard it.
struct CopiedNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark")
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .accessibilityHidden(true)
    }
}
