import SwiftUI
import PullBullKit

/// The Ask screen: the question, the model's answer, and the items it picked in its order. Plain inputs
/// only; the popover owns the keys (↑/↓, ↩, ⌘↩, copy, Esc) and passes the selection in.
struct AskView: View {
    let question: String
    /// Nil while `asking`, or before the first reply.
    let outcome: AskOutcome?
    let asking: Bool
    let selection: PRKey?
    let now: Date
    let onOpen: (PRKey) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.bottom, 6)
            }
            Hairline()
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to search")
            Text(verbatim: question)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Esc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.separator, lineWidth: 0.5))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch outcome {
        case .answered(_, let answer, let rows, let stillSyncing):
            answerBox(answer)
            if rows.isEmpty {
                note("Nothing matched. Try other words.")
            } else {
                ForEach(rows, id: \.key) { item in
                    AskRow(
                        item: item, why: answer.results.first { $0.key == item.key }?.why ?? "",
                        now: now, selected: selection == item.key, onOpen: onOpen)
                }
            }
            if let stillSyncing {
                note("Index still syncing (\(stillSyncing) items)")
            }
        case .failed(_, let error):
            note(error.message)
        case nil:
            if asking { note("Asking…") }
        }
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    /// The answer as plain text: no Markdown and no link detection, so nothing in it can be clicked.
    private func answerBox(_ answer: AskAnswer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !answer.answer.isEmpty {
                Text(verbatim: answer.answer)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Answer: \(answer.answer)")
            }
            Text(verbatim: Self.sourceLine(answer))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.fill))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// "Sonnet 5.5 · 3.2 s · 20 candidates sent".
    static func sourceLine(_ answer: AskAnswer) -> String {
        let parts = answer.elapsed.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return "\(answer.model.name) · \(seconds.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))) s · \(answer.cardsSent) candidates sent"
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("↩ open · ⌘↩ GitHub · ⌘C copy")
            Spacer()
            Text("⌥⌘↩ ask again")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// One picked item: kind glyph, title, `repo #n · @author · age`, the state pill and the model's reason.
private struct AskRow: View {
    let item: AskItem
    let why: String
    let now: Date
    let selected: Bool
    let onOpen: (PRKey) -> Void
    @State private var hovering = false

    var body: some View {
        Button { onOpen(item.key) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(symbol: glyph.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(glyph.color)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: item.title)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    meta.padding(.top, 3)
                    if !why.isEmpty {
                        Text(verbatim: why)
                            .font(.system(size: 11.5).italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.top, 7)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .modifier(RowFill(cornerRadius: 7, selected: selected, hovering: hovering))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var meta: some View {
        HStack(spacing: 5) {
            RepoNumber(key: item.key)
                .layoutPriority(-1)
            if let author = item.author {
                Text("·").foregroundStyle(.tertiary)
                Text(verbatim: "@\(author)")
            }
            Text("·").foregroundStyle(.tertiary)
            Text(RelativeAge.short(from: item.updated, to: now)).fixedSize()
            statePill
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 16)
    }

    @ViewBuilder private var statePill: some View {
        switch item.state {
        case "merged": EndedPill(merged: true)
        case "closed": EndedPill(merged: false)
        case "draft": DraftPill()
        default: Pill(symbol: nil, text: "Open", foreground: Palette.secondaryText, fill: Palette.fill)
        }
    }

    private var glyph: (symbol: String, color: Color) {
        switch item.kind {
        case .pr:
            let g = PRGlyph(state: PRState(rawValue: item.state) ?? .open, isDraft: item.state == "draft")
            return (Palette.prGlyph(g), Palette.prGlyphColor(g))
        case .issue:
            let g = Palette.issueGlyph(item.state == "closed" ? .completed : .open)
            return (g.symbol, g.color)
        }
    }

    private var accessibilityText: String {
        let kind = item.kind == .pr ? "Pull request" : "Issue"
        var parts = [kind, item.title, item.key.askKey, item.state]
        if !why.isEmpty { parts.append(why) }
        return parts.joined(separator: ", ")
    }
}
