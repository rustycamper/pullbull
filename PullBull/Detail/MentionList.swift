import PullBullKit
import SwiftUI

/// The comment field's @ list, drawn over the detail just above the field: people and teams for the token
/// at the caret, styled as search completion's rows. Focus stays in the field; its keys are routed in
/// `PopoverView.handleDetailKey`.
struct MentionList: View {
    let model: AppModel
    let mention: MentionState

    var body: some View {
        VStack(spacing: 0) {
            if mention.rows.isEmpty {
                Text("Loading people…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(mention.rows.enumerated()), id: \.element.id) { index, row in
                    MentionRow(candidate: row, selected: index == mention.selection) {
                        model.selectMention(index)
                        model.acceptMention()
                    }
                }
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator, lineWidth: 0.5))
    }
}

private struct MentionRow: View {
    let candidate: MentionCandidate
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if candidate.isTeam {
                    Image(systemName: "person.2")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                } else {
                    AvatarView(login: candidate.title, url: candidate.avatarURL, size: 18)
                }
                Text(candidate.title)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                if candidate.isTeam {
                    Text(candidate.insertText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected ? Palette.selection : hovering ? Palette.rowHover : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CompletionSpeech.label(candidate))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}
