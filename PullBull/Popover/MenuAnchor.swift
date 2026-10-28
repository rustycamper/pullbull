import AppKit
import SwiftUI

/// The AppKit view behind a SwiftUI control, for popping a menu up at it.
@MainActor
final class MenuAnchor {
    weak var view: NSView?
}

struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }

    /// Top-left origin, so a point given to the menu reads as in SwiftUI.
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        /// Clicks go to the control on top.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
