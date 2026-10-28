import AppKit
import SwiftUI

/// A command for Terminal in a monospaced, selectable box, with a button that copies it. Commands
/// only: nothing secret goes on the pasteboard.
struct CopyableCommand: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(copied ? "Copied" : "Copy", action: copy)
                .controlSize(.small)
                .accessibilityLabel("Copy command: \(command)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.separator, lineWidth: 0.5))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
