import SwiftUI
import Charts

// Swift Charts is the only SwiftUI surface; all screens and navigation use UIKit.
struct PriceChart: View {
    let chart: StockChart
    var compact = false
    @State private var selection: Date?
    private var selectedPoint: ChartPoint? {
        guard let selection else { return chart.points.last }
        return chart.points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }
    private var domain: ClosedRange<Double> {
        let low = chart.min ?? chart.points.map(\.close).min() ?? 0
        let high = chart.max ?? chart.points.map(\.close).max() ?? 1
        let padding = max((high - low) * 0.12, max(abs(low) * 0.001, 0.01))
        return (low - padding)...(high + padding)
    }
    private var color: Color {
        (chart.points.last?.close ?? 0) < (chart.points.first?.close ?? 0) ? Color(Theme.red) : Color(Theme.positive)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 0 : 14) {
            if !compact, let point = selectedPoint {
                HStack(alignment: .top) {
                    Text(Display.time(point.time, zone: chart.timezone))
                        .font(.system(size: 10, design: .monospaced))
                    Spacer()
                    Text(Display.money(point.close, currency: chart.currency))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(Color(Theme.ink))
            }
            Chart {
                ForEach(chart.points) { point in
                    AreaMark(x: .value("Waktu", point.date), yStart: .value("Dasar", domain.lowerBound), yEnd: .value("Harga", point.close))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Waktu", point.date), y: .value("Harga", point.close))
                        .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: compact ? 1.6 : 2.2))
                        .accessibilityLabel(Display.time(point.time, zone: chart.timezone))
                        .accessibilityValue(Display.money(point.close, currency: chart.currency))
                }
                if !compact, selection != nil, let point = selectedPoint {
                    RuleMark(x: .value("Waktu", point.date))
                        .foregroundStyle(Color(Theme.purple).opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    PointMark(x: .value("Waktu", point.date), y: .value("Harga", point.close))
                        .foregroundStyle(Color(Theme.purple)).symbolSize(45)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis(compact ? .hidden : .visible)
            .chartYAxis {
                if !compact {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(Color(Theme.lavender))
                    }
                }
            }
            .chartXSelection(value: $selection)
            .chartLegend(.hidden)
            if !compact {
                HStack(alignment: .top) {
                    Text("Min.\n\(Display.money(chart.min, currency: chart.currency))")
                    Spacer()
                    Text("Vol. \(Display.compact(selectedPoint?.volume.map(Double.init)))")
                        .foregroundStyle(Color(Theme.green))
                    Spacer()
                    Text("Maks.\n\(Display.money(chart.max, currency: chart.currency))")
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(Color(Theme.secondary))
                Text("Sentuh dan geser grafik untuk melihat harga & volume.")
                    .font(.system(size: 10)).foregroundStyle(Color(Theme.secondary))
            }
        }
    }
}
