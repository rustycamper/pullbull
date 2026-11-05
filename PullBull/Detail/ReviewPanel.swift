import PullBullKit
import SwiftUI

/// Review mode's panel, directly above the bottom row: the two-way verdict, then what's being reviewed.
/// The verdict's buttons take no focus: a click that took it from the comment field would end review mode.
struct ReviewPanel: View {
    let model: AppModel
    let mode: ReviewMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            verdict
            if let detail = model.detail(for: mode.key) {
                summaryLine(ReviewSummary(head: mode.head, detail: detail))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var verdict: some View {
        HStack(spacing: 2) {
            ForEach(ReviewVerdict.allCases, id: \.self) { choice in
                VerdictButton(title: choice.title, isSelected: choice == mode.verdict) {
                    if choice != mode.verdict { model.changeReviewVerdict() }
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.fill))
        .disabled(!mode.canChangeVerdict)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Review verdict")
        .accessibilityValue(mode.verdict.title)
        .accessibilityAdjustableAction { _ in model.changeReviewVerdict() }
    }

    /// The checks part alone takes the warning colour.
    private func summaryLine(_ summary: ReviewSummary) -> some View {
        var line = AttributedString(summary.text)
        if summary.warns, let checks = summary.checks, let range = line.range(of: checks, options: .backwards) {
            line[range].swiftUI.foregroundColor = Palette.amberGlyph
        }
        return Text(line)
            .font(.system(size: 11))
            .foregroundStyle(Palette.secondaryText)
            .monospacedDigit()
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// One side of the verdict: filled when chosen.
private struct VerdictButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(isSelected ? Palette.strongFill : .clear))
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(PressableStyle())
        .focusable(false)
    }
}
