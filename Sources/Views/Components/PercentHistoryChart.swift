import Charts
import SwiftUI

/// 0.0–1.0 arası bir oranın geçmişini alan grafik olarak çizer (CPU, RAM).
struct PercentHistoryChart: View {
    let samples: [TimedSample<Double>]
    let tint: Color

    var body: some View {
        Chart(samples, id: \.date) { sample in
            AreaMark(
                x: .value("Zaman", sample.date),
                y: .value("Oran", sample.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [tint.opacity(0.45), tint.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Zaman", sample.date),
                y: .value("Oran", sample.value)
            )
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let fraction = value.as(Double.self) {
                        Text(Format.percent(fraction))
                    }
                }
                .font(.system(size: 9))
            }
        }
        .historyChartFrame()
    }
}

extension View {
    /// Tüm geçmiş grafiklerinin ortak boyutu ve sade x ekseni.
    func historyChartFrame() -> some View {
        chartXAxis(.hidden)
            .frame(height: 80)
    }
}
