import SwiftUI

/// A detail before its first fetch: shimmering placeholders for what the loaded detail draws under the
/// summary, with its fonts, cards and paddings, so the detail replaces them in place. The summary itself
/// already shows from the list data. VoiceOver reads "Loading details…".
struct DetailSkeleton: View {
    enum Layout {
        /// An open PR: the Checks section. Reviewers follows from the list data.
        case checks
        /// A merged or closed PR: the Description section, prose straight on the material.
        case prose
        /// An issue: the linked pull requests line, then the Description card.
        case issue
    }

    let layout: Layout

    private static let lineWidths: [CGFloat] = [0.94, 0.86, 0.97, 0.58]

    var body: some View {
        placeholders
            .skeletonShimmer()
            // The cards' chrome, laid out the same way and without the shapes, stays still under the shimmer.
            .background {
                placeholders
                    .foregroundStyle(.clear)
                    .environment(\.skeletonCardChrome, true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading details…")
    }

    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch layout {
            case .checks:
                section(titleWidth: 44) {
                    SkeletonCard { checkRow }
                }
            case .prose:
                section(titleWidth: 64) {
                    lines(size: 12.5, spacing: 3)
                }
            case .issue:
                // "No linked pull requests", the line most issues show here.
                SkeletonBar(font: .system(size: 12), width: .fixed(132), height: 9)
                    .padding(.horizontal, Metrics.detailGutter)
                    .padding(.top, 14)
                section(titleWidth: 64) {
                    SkeletonCard {
                        lines(size: 12, spacing: 2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    /// `DetailSection`: an 11pt semibold title over its content.
    private func section(titleWidth: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBar(font: .system(size: 11, weight: .semibold), width: .fixed(titleWidth), height: 8)
            content()
        }
        .padding(.horizontal, Metrics.detailGutter)
        .padding(.top, 14)
    }

    /// `CheckLine`: the state glyph and the check's name.
    private var checkRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.foreground)
                .frame(width: 12, height: 12)
                .frame(width: 14)
            SkeletonBar(font: .system(size: 12), width: .fraction(0.5), height: 9)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 28)
    }

    /// A paragraph of `size` text with `spacing` between its lines.
    private func lines(size: CGFloat, spacing: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(Self.lineWidths.enumerated()), id: \.offset) { _, width in
                SkeletonBar(font: .system(size: size), width: .fraction(width), height: 9)
            }
        }
    }
}

/// `DetailCard`'s shape, drawing its background and border only in the chrome layer.
private struct SkeletonCard<Content: View>: View {
    @Environment(\.skeletonCardChrome) private var chrome
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if chrome { RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)) }
        }
        .overlay {
            if chrome { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.separator, lineWidth: 0.5) }
        }
    }
}

private extension EnvironmentValues {
    @Entry var skeletonCardChrome = false
}
