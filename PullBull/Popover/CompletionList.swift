import SwiftUI
import PullBullKit

/// The "@user", "~label" or "is:" completion: people, labels or states matching the token at the caret,
/// drawn over the top of the hints or results. Focus stays in the search field; the keys are handled in
/// `PopoverView.handleKey`.
struct CompletionList: View {
    let model: AppModel
    /// Completes with the selected row (`PopoverView.acceptCompletion`).
    let accept: () -> Void

    var body: some View {
        if let completion = model.completion {
            VStack(spacing: 0) {
                switch completion {
                case .people(let people):
                    if model.snapshot == nil {
                        message("People appear once PullBull has loaded")
                    } else if people.candidates.isEmpty {
                        message("No one called “\(people.token.prefix)” in PullBull's lists · ↩ to search anyway")
                    } else {
                        ForEach(Array(people.candidates.enumerated()), id: \.element.id) { index, candidate in
                            CompletionRow(candidate: candidate, selected: index == people.selection) {
                                pick(index, in: completion)
                            }
                        }
                    }
                case .labels(let labels):
                    if model.snapshot == nil {
                        message("Labels appear once PullBull has loaded")
                    } else if labels.candidates.isEmpty {
                        message("No label called “\(labels.token.prefix)” in PullBull's lists · ↩ to search anyway")
                    } else {
                        ForEach(Array(labels.candidates.enumerated()), id: \.element.id) { index, candidate in
                            LabelCompletionRow(candidate: candidate, selected: index == labels.selection) {
                                pick(index, in: completion)
                            }
                        }
                    }
                case .states(let states):
                    if states.candidates.isEmpty {
                        message("No state called “\(states.token.prefix)” · ↩ to search anyway")
                    } else {
                        ForEach(Array(states.candidates.enumerated()), id: \.element.id) { index, candidate in
                            StateCompletionRow(candidate: candidate, selected: index == states.selection) {
                                pick(index, in: completion)
                            }
                        }
                    }
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.separator, lineWidth: 0.5))
            .padding(.horizontal, 10)
            .padding(.top, 4)
        }
    }

    private func pick(_ index: Int, in completion: SearchCompletion) {
        model.moveCompletion(by: index - completion.selection)
        accept()
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }
}

private struct CompletionRow: View {
    let candidate: PersonCandidate
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AvatarView(login: candidate.login, url: candidate.avatarURL, size: 18)
                if candidate.isViewer {
                    Text("me")
                        .font(.system(size: 13))
                    Text("· \(candidate.login)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Text(candidate.login)
                        .font(.system(size: 13))
                }
                Spacer(minLength: 8)
                if candidate.isMember {
                    Text("member")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if candidate.openCount > 0 {
                    Text("· \(candidate.openCount)")
                        .font(.system(size: 11))
                        .monospacedDigit()
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

private struct LabelCompletionRow: View {
    let candidate: LabelCandidate
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                Text(candidate.name)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                if candidate.openCount > 0 {
                    Text("· \(candidate.openCount)")
                        .font(.system(size: 11))
                        .monospacedDigit()
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

private struct StateCompletionRow: View {
    let candidate: StateCandidate
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                Text(candidate.state.rawValue)
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                Text(candidate.state.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
