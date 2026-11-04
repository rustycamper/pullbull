import SwiftUI
import PullBullKit

/// The Stats screen's four sections, each under a list-style section header: Your reviews (with the bar
/// chart), Your pull requests (with the top reviewers), Right now (two list rows) and Issues. Before the
/// first report the values shimmer; Right now, built from the lists, shows at once.
struct StatsCards: View {
    let model: AppModel
    let now: Date

    private var report: StatsReport? { model.statsReport }
    /// The first load of this period: nothing to show yet, and a fetch running.
    private var loading: Bool { report == nil && model.statsLoading }
    private var period: StatsPeriod { model.settings.statsPeriod }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reviews
            pullRequests
            rightNow
            issues
        }
    }

    // MARK: Your reviews

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListSectionHeader(glyph: PRSection.needsReview.glyph, title: StatsCard.reviews.title, trailing: period.span)
            StatsCardBox {
                VStack(alignment: .leading, spacing: 5) {
                    StatColumns(loading: loading, columns: [
                        .init(label: "Reviews", value: report?.reviews, skeletonWidth: 34),
                        .init(label: "Turnaround", value: report?.turnaround, skeletonWidth: 66),
                    ])
                    .cardSpeech(report?.cardSpeech(.reviews) ?? StatsCard.reviews.placeholderSpeech(loading: loading))
                    chart
                }
            }
        }
    }

    @ViewBuilder private var chart: some View {
        if let bars = report?.bars {
            StatsBarChart(bars: bars, period: period)
        } else if loading {
            RoundedRectangle(cornerRadius: 3)
                .fill(.foreground)
                .frame(height: StatsBarChart.height)
                .skeletonShimmer()
                .accessibilityHidden(true)
        } else {
            // The reviews didn't load: no bars rather than a row of empty days.
            Color.clear
                .frame(height: StatsBarChart.height)
                .accessibilityHidden(true)
        }
    }

    // MARK: Your pull requests

    private var pullRequests: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListSectionHeader(glyph: PRSection.yourPRs.glyph, title: StatsCard.pullRequests.title)
            StatsCardBox {
                VStack(alignment: .leading, spacing: 5) {
                    StatColumns(loading: loading, columns: [
                        .init(label: "Merged", value: report?.merged, skeletonWidth: 26),
                        .init(label: "Time to merge", value: report?.timeToMerge, skeletonWidth: 56),
                        .init(label: "First review", value: report?.firstReview, skeletonWidth: 62),
                    ])
                    TopReviewersRow(reviewers: report?.topReviewers, loading: loading)
                }
                .cardSpeech(
                    report?.cardSpeech(.pullRequests) ?? StatsCard.pullRequests.placeholderSpeech(loading: loading))
            }
        }
    }

    // MARK: Right now

    private var rightNow: some View {
        let picked = model.rightNow
        return VStack(alignment: .leading, spacing: 0) {
            ListSectionHeader(glyph: PRSection.waiting.glyph, title: "Right now")
            RightNowSlot(
                model: model, item: picked.waitingOnMe, tab: .review, now: now,
                caption: "Waiting on you longest", empty: "Nothing waits on your review")
            RightNowSlot(
                model: model, item: picked.myLongest, tab: .mine, now: now,
                caption: "Your PR waiting longest", empty: "None of your PRs waits for a first review")
        }
    }

    // MARK: Issues

    private var issues: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListSectionHeader(glyph: "pullbull.issue", title: StatsCard.issues.title)
            StatsCardBox {
                StatColumns(loading: loading, columns: [
                    .init(label: "Closed", value: report?.issuesClosed, skeletonWidth: 20),
                    .init(label: "Opened", value: report?.issuesOpened, skeletonWidth: 30),
                    .init(label: "Comments", value: report?.comments, skeletonWidth: 26),
                ])
                .cardSpeech(report?.cardSpeech(.issues) ?? StatsCard.issues.placeholderSpeech(loading: loading))
            }
        }
    }
}

private extension View {
    /// A card's figures read as one VoiceOver element: the card's sentence.
    func cardSpeech(_ text: String) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityLabel(text)
    }
}

/// The detail's card (8 pt corners, faint fill, hairline edge), inset to the section headers' glyph line.
private struct StatsCardBox<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        DetailCard {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }
}

/// Equal columns split by hairlines, each a label, a figure and its comparison.
private struct StatColumns: View {
    struct Column {
        let label: String
        /// Nil with no report behind it: "–", or a shimmer while `loading`.
        let value: StatValue?
        /// The shimmer's width, about the figure's usual width.
        let skeletonWidth: CGFloat
    }

    let loading: Bool
    let columns: [Column]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                StatColumn(column: column, loading: loading)
                    .padding(.leading, index == 0 ? 0 : 10)
                    // Every column as tall as the tallest, so the hairlines run the full height.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .leading) {
                        if index > 0 { Hairline(axis: .vertical) }
                    }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StatColumn: View {
    let column: StatColumns.Column
    let loading: Bool

    private static let figureFont = Font.system(size: 20, weight: .semibold)
    private static let smallFont = Font.system(size: 11)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(column.label)
                .font(Self.smallFont)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
            if loading {
                VStack(alignment: .leading, spacing: 0) {
                    SkeletonBar(font: Self.figureFont, width: .fixed(column.skeletonWidth), height: 16)
                    SkeletonBar(font: Self.smallFont, width: .fixed(36), height: 8)
                }
                .skeletonShimmer()
            } else {
                figure(column.value?.parts ?? [StatTextPart(text: "–", isUnit: false)])
                // A line kept when there's no comparison, so the card doesn't change height as values land.
                Text(column.value?.comparison ?? " ")
                    .font(Self.smallFont)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // A "–" still says why when it can, such as "No reviews you were asked for in this period".
        .help(column.value?.hover ?? "")
    }

    /// The figures large in the primary colour, the units small and secondary: "3 h 10 m".
    private func figure(_ parts: [StatTextPart]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if part.isUnit {
                    Text(part.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.leading, 1)
                        .padding(.trailing, 3)
                } else {
                    Text(part.text)
                        .font(Self.figureFont)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .lineLimit(1)
    }
}

/// Up to three people with the most of your PRs reviewed: avatar, login, count. "No reviews yet" when
/// nobody has; "–" when your PRs didn't load.
private struct TopReviewersRow: View {
    let reviewers: [TopReviewer]?
    let loading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Top reviewers")
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            if loading {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.foreground)
                    .frame(width: 150, height: 12)
                    .skeletonShimmer()
            } else if let reviewers {
                if reviewers.isEmpty {
                    Text("No reviews yet")
                        .foregroundStyle(Palette.secondaryText)
                } else {
                    ForEach(reviewers, id: \.login) { reviewer in
                        HStack(spacing: 5) {
                            AvatarView(
                                login: reviewer.login,
                                url: reviewer.avatarURL ?? URL(string: "https://github.com/\(reviewer.login).png"),
                                size: 18)
                            Text(reviewer.login)
                                .lineLimit(1)
                            Text("\(reviewer.prCount)")
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondaryText)
                                .fixedSize()
                        }
                    }
                }
            } else {
                Text("–")
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .font(.system(size: 12))
        .frame(height: 22)
    }
}

/// One of Right now's two places: a caption over the row as the list draws it, or the line saying there
/// is none.
private struct RightNowSlot: View {
    let model: AppModel
    let item: RightNowItem?
    let tab: PRTab
    let now: Date
    let caption: String
    let empty: String

    /// Where a row's title starts: its padding and icon column.
    private static let titleInset: CGFloat = 8 + 20 + 10

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 0) {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .padding(.leading, Self.titleInset)
                    .padding(.top, 2)
                PRRow(
                    model: model, row: item.row, context: .stats(tab), compact: false, now: now,
                    selected: model.statsSelection == item.row.id)
                    .id(item.row.id)
            }
        } else {
            // As the list's "Nothing needs you": a checkmark in the rows' icon column, then the words.
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11))
                    .frame(width: 20)
                Text(empty)
                    .font(.system(size: 12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: ListSectionHeader.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(empty)
        }
    }
}
