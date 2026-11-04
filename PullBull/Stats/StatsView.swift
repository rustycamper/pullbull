import SwiftUI
import PullBullKit

/// The Stats screen, pushed over the list or the search like a detail: the header, the period chips, the
/// error line when a source failed, the cards scrolling between them and the footer. The popover owns its
/// keys.
struct StatsView: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header
                Hairline()
                periodChips
                if let failure = model.statsReport?.failures.first {
                    FailureBanner(
                        message: "Couldn't load stats: \(failure)", symbol: "exclamationmark.triangle",
                        action: .init(title: "Retry", perform: retry))
                        .padding(.horizontal, Metrics.listGutter)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        StatsCards(model: model, now: context.date)
                            .padding(.horizontal, Metrics.rowInset)
                            .padding(.bottom, 6)
                    }
                    .onChange(of: model.statsSelection) { _, key in
                        guard let key else { return }
                        proxy.scrollTo(key)
                    }
                }
                .frame(maxHeight: .infinity)
                footer(now: context.date)
            }
        }
    }

    private func retry() {
        if !model.statsLoading { model.refreshStats() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            DetailBackButton(title: backTitle, action: model.closeStats)
            Spacer(minLength: 0)
            if model.statsLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Refreshing")
            } else {
                DetailIconButton(symbol: "arrow.clockwise", help: "Refresh", action: model.refreshStats)
            }
        }
        // Centred on the whole bar, clear of the buttons on either side.
        .overlay {
            Text("Stats")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
    }

    private var backTitle: String {
        model.statsReturnsToSearch ? "Search" : model.selectedTabTitle
    }

    // MARK: Period chips

    /// Styled as the list's scope chips; ← and → move between them.
    private var periodChips: some View {
        HStack(spacing: 4) {
            ForEach(StatsPeriod.allCases, id: \.self) { period in
                ScopeChip(
                    title: period.title, count: nil, selected: period == model.settings.statsPeriod, hot: false,
                    crowded: false, help: period.summary, spoken: period.title
                ) {
                    model.setStatsPeriod(period)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "← →")
                .font(.system(size: 11))
                .tracking(1)
                .foregroundStyle(Palette.secondaryText)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Period")
        .padding(.horizontal, 8)
        .frame(height: 28)
    }

    // MARK: Footer

    /// Where the figures come from, and the cap note when a cap cut in; the tooltip says how old they are.
    private func footer(now: Date) -> some View {
        Text(footerText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Metrics.listGutter)
            .padding(.trailing, 8)
            .frame(height: 34)
            .contentShape(Rectangle())
            .help(StatsFooter.help(fetchedAt: model.statsReport?.fetchedAt, now: now))
            .overlay(alignment: .top) { Hairline() }
    }

    private var footerText: String {
        guard let login = model.runningAccount?.login else { return "" }
        return StatsFooter.text(
            login: login, org: model.shownSnapshot?.org.scope.org, capNote: model.statsReport?.footerCapNote)
    }
}
