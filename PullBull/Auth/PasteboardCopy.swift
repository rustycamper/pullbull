import AppKit

enum PasteboardCopy {
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// Copies the device user code, marked so clipboard managers skip it. Pass nothing else here.
    @MainActor
    static func copyCode(_ code: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        pasteboard.setData(Data(), forType: transient)
        pasteboard.setData(Data(), forType: concealed)
    }
}

extension PasteboardCopy {
    /// Copies a command or a URL as plain text. Nothing secret goes through here.
    @MainActor
    static func copyPlain(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
