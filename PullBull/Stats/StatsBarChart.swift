import SwiftUI
import PullBullKit

/// Reviews per day under a "Per day" caption: one bar per day of the period, today's last in the accent
/// colour, the busiest day's count above its bar, and the days named underneath (every weekday initial
/// for 7 days, the first and last dates for 30 and 90). A day with none is a stub on the baseline and a
/// day not loaded is left out. The tooltip, also the chart's one VoiceOver label, gives the total and the
/// busiest day; the caption, count and axis are drawn into that one element.
struct StatsBarChart: View {
    let bars: ReviewBars
    let period: StatsPeriod

    static let barHeight: CGFloat = 36
    /// Room above the bars for the busiest day's count, so the tallest bar's label never clips.
    private static let countSpace: CGFloat = 12
    private static let rowHeight: CGFloat = 13
    private static let spacing: CGFloat = 3
    private static let plotHeight = countSpace + barHeight + spacing + rowHeight
    /// Caption to axis, for the placeholders that stand in before the report, so nothing jumps.
    static let totalHeight = rowHeight + spacing + plotHeight

    var body: some View {
        let calendar = Calendar.current
        let hover = bars.hover(period: period, calendar: calendar)
        let labels = bars.axisLabels(period: period, calendar: calendar)
        VStack(alignment: .leading, spacing: Self.spacing) {
            Self.caption
            Canvas { context, size in
                drawBars(in: &context, width: size.width)
                drawCount(in: &context, width: size.width)
                drawAxis(labels, in: &context, width: size.width)
            }
            .frame(height: Self.plotHeight)
        }
        .frame(height: Self.totalHeight, alignment: .top)
        .help(hover)
        .accessibilityElement()
        .accessibilityLabel(hover)
        .accessibilityAddTraits(.isImage)
    }

    /// Stands in while the first report loads: the real caption, a shimmer where the bars go, and the
    /// count and axis rows left empty, at the chart's full height.
    static var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: spacing) {
            caption
            RoundedRectangle(cornerRadius: 3)
                .fill(.foreground)
                .frame(height: barHeight)
                .skeletonShimmer()
                .padding(.top, countSpace)
        }
        .frame(height: totalHeight, alignment: .top)
        .accessibilityHidden(true)
    }

    private static var caption: some View {
        Text("Per day")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: rowHeight)
    }

    private static let baseline = countSpace + barHeight

    private func drawBars(in context: inout GraphicsContext, width: CGFloat) {
        for mark in bars.marks(width: width, height: Self.barHeight) {
            let rect = CGRect(x: mark.x, y: Self.baseline - mark.height, width: mark.width, height: mark.height)
            let radius = min(1.5, mark.width / 2, mark.height / 2)
            let shading: GraphicsContext.Shading = mark.isToday
                ? .color(.accentColor) : mark.isEmpty ? .color(Palette.tertiary) : .style(.secondary)
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: shading)
        }
    }

    /// The busiest day's count, centred above its full-height bar and kept inside the chart's width.
    private func drawCount(in context: inout GraphicsContext, width: CGFloat) {
        guard let busiest = bars.busiest else { return }
        var text = context.resolve(Text("\(busiest.count)").font(.caption2.monospacedDigit()))
        text.shading = busiest.index == bars.todayIndex ? .color(.accentColor) : .style(.secondary)
        let half = text.measure(in: CGSize(width: width, height: Self.countSpace * 2)).width / 2
        let center = bars.centerX(of: busiest.index, width: width)
        let x = min(max(center, half), max(width - half, half))
        context.draw(text, at: CGPoint(x: x, y: Self.countSpace), anchor: .bottom)
    }

    /// For 7 days each initial sits under its bar, today's in the accent colour; for 30 and 90 the first
    /// date starts at the first bar's leading edge and the last ends at the last bar's trailing edge.
    private func drawAxis(_ labels: [ReviewBarLabel], in context: inout GraphicsContext, width: CGFloat) {
        let y = Self.baseline + Self.spacing
        let extent = bars.extent(width: width)
        for label in labels {
            var text = context.resolve(Text(label.text).font(.caption2))
            let point: CGPoint
            let anchor: UnitPoint
            if period == .week {
                text.shading = label.index == bars.todayIndex ? .color(.accentColor) : .style(.secondary)
                point = CGPoint(x: bars.centerX(of: label.index, width: width), y: y)
                anchor = .top
            } else {
                text.shading = .style(.secondary)
                let first = label.index == 0
                point = CGPoint(x: first ? extent.lowerBound : extent.upperBound, y: y)
                anchor = first ? .topLeading : .topTrailing
            }
            context.draw(text, at: point, anchor: anchor)
        }
    }
}

#if DEBUG
#Preview("Bars by period") {
    let now = Date()
    VStack(alignment: .leading, spacing: 16) {
        ForEach(StatsPeriod.allCases, id: \.self) { period in
            let window = period.window(now: now, calendar: .current)
            // A few reviews on most days, none on every fifth, two today.
            let dates = window.dayStarts(calendar: .current).enumerated().flatMap { index, day in
                Array(repeating: day.addingTimeInterval(3600), count: index % 5 == 0 ? 0 : index % 4 + 1)
            } + [now, now]
            Text(period.title).font(.caption.bold())
            StatsBarChart(
                bars: ReviewBars.make(reviewDates: dates, window: window, loadedFrom: nil, calendar: .current),
                period: period)
        }
    }
    .padding()
    .frame(width: 332)
}

#Preview("Loading") {
    StatsBarChart.loadingPlaceholder
        .padding()
        .frame(width: 332)
}

#Preview("One busy day, today busiest, capped") {
    let now = Date()
    let window = StatsPeriod.week.window(now: now, calendar: .current)
    let days = window.dayStarts(calendar: .current).map { $0.addingTimeInterval(3600) }
    VStack(alignment: .leading, spacing: 16) {
        // 1 on the first day, 106 the day before today, none today.
        StatsBarChart(
            bars: ReviewBars.make(reviewDates: [days[0]] + Array(repeating: days[5], count: 106),
                                  window: window, loadedFrom: nil, calendar: .current),
            period: .week)
        StatsBarChart(
            bars: ReviewBars.make(reviewDates: [days[2], now, now], window: window, loadedFrom: nil,
                                  calendar: .current),
            period: .week)
        StatsBarChart(
            bars: ReviewBars.make(reviewDates: [days[4], days[4], days[6]], window: window,
                                  loadedFrom: window.dayStarts(calendar: .current)[3], calendar: .current),
            period: .week)
    }
    .padding()
    .frame(width: 332)
}
#endif
