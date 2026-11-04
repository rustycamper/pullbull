import SwiftUI
import PullBullKit

/// Reviews per day, one bar per day of the period with today's last in the accent colour. A day with
/// none is a stub on the baseline, a day not loaded is left out, and there is no axis: the tooltip, also
/// the chart's one VoiceOver label, gives the total and the busiest day.
struct StatsBarChart: View {
    let bars: ReviewBars
    let period: StatsPeriod

    static let height: CGFloat = 20

    var body: some View {
        let hover = bars.hover(period: period, calendar: .current)
        Canvas { context, size in
            for mark in bars.marks(width: size.width, height: size.height) {
                let rect = CGRect(x: mark.x, y: size.height - mark.height, width: mark.width, height: mark.height)
                let radius = min(1.5, mark.width / 2, mark.height / 2)
                let shading: GraphicsContext.Shading = mark.isToday
                    ? .color(.accentColor) : mark.isEmpty ? .color(Palette.tertiary) : .style(.secondary)
                context.fill(Path(roundedRect: rect, cornerRadius: radius), with: shading)
            }
        }
        .frame(height: Self.height)
        .help(hover)
        .accessibilityElement()
        .accessibilityLabel(hover)
        .accessibilityAddTraits(.isImage)
    }
}

#if DEBUG
#Preview("Bars by period") {
    let now = Date()
    VStack(spacing: 12) {
        ForEach(StatsPeriod.allCases, id: \.self) { period in
            let window = period.window(now: now, calendar: .current)
            // A few reviews on most days, none on every fifth, two today.
            let dates = window.dayStarts(calendar: .current).enumerated().flatMap { index, day in
                Array(repeating: day.addingTimeInterval(3600), count: index % 5 == 0 ? 0 : index % 4 + 1)
            } + [now, now]
            StatsBarChart(
                bars: ReviewBars.make(reviewDates: dates, window: window, loadedFrom: nil, calendar: .current),
                period: period)
        }
    }
    .padding()
    .frame(width: 332)
}
#endif
