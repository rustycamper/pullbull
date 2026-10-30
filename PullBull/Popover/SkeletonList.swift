import SwiftUI
import PullBullKit

/// A list before its first data: shimmering placeholder rows laid out with the real rows' fonts, frames and
/// paddings, inside the same scroll view and insets as `PRListView` and `IssueListView`, so the data
/// replaces them in place. VoiceOver reads "Loading…".
struct SkeletonList: View {
    /// Whether the first rows sit under a group header (`ListSkeleton`).
    let header: Bool
    let compact: Bool
    /// The trailing glyph's diameter: the CI glyph on PR rows, the assignee avatar on issue rows.
    let trailing: CGFloat
    /// The meta line's fixed height on PR rows (`PRRow.meta`); issue rows size it to the 11pt text.
    var metaHeight: CGFloat? = nil

    private static let titleWidths: [CGFloat] = [0.72, 0.6, 0.68, 0.54, 0.64]
    private static let metaWidths: [CGFloat] = [0.38, 0.32, 0.42, 0.3, 0.36]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if header {
                    headerRow
                } else {
                    Color.clear.frame(height: 6)
                }
                ForEach(0..<ListSkeleton.rowCount, id: \.self) { index in
                    if compact { compactRow(index) } else { fullRow(index) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
            .skeletonShimmer()
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading…")
    }

    /// `ListSectionHeader`: an 11pt semibold line.
    private var headerRow: some View {
        bar(.system(size: 11, weight: .semibold), width: .fixed(72), height: 9)
            .padding(.horizontal, 8)
            .frame(height: ListSectionHeader.height)
    }

    /// `PRRow.fullBody` / `IssueRow.fullBody` with a one-line title.
    private func fullRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(.foreground)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                bar(.system(size: 13), width: .fraction(Self.titleWidths[index]), height: 12)
                bar(.system(size: 11), width: .fraction(Self.metaWidths[index]), height: 9)
                    .frame(height: metaHeight)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle()
                .fill(.foreground)
                .frame(width: trailing, height: trailing)
                .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 8)
    }

    /// `CompactRowLayout`, as the tab rows use it.
    private func compactRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.foreground)
                .frame(width: 16, height: 16)
            bar(.system(size: 12.5), width: .fraction(Self.titleWidths[index]), height: 10)
            bar(.system(size: 11), width: .fixed(56), height: 9)
                .frame(width: 56)
            Circle()
                .fill(.foreground)
                .frame(width: min(trailing, 16), height: min(trailing, 16))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }

    private func bar(_ font: Font, width: SkeletonBar.Width, height: CGFloat) -> SkeletonBar {
        SkeletonBar(font: font, width: width, height: height)
    }
}

extension SkeletonList {
    /// The current PR tab before its first snapshot.
    static func pullRequests(_ model: AppModel) -> SkeletonList {
        SkeletonList(
            header: ListSkeleton.prLeadsWithHeader(
                grouping: model.prGrouping(for: model.selectedTab), focused: model.repoFocus != nil),
            compact: model.settings.compact, trailing: 14, metaHeight: 16)
    }

    /// An Issues tab before its first successful load.
    static func issues(_ model: AppModel, tab: IssueTab) -> SkeletonList {
        SkeletonList(
            header: ListSkeleton.issueLeadsWithHeader(
                tab: tab, grouping: model.settings.grouping, focused: model.repoFocus != nil,
                statusKnown: model.issueTabs?.statusKnown),
            compact: model.settings.compact, trailing: 18)
    }
}
