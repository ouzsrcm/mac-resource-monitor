import Charts
import SwiftUI

/// Byte/saniye cinsinden bir hız serisinin adı, rengi ve geçmişi.
struct RateSeries {
    let name: String
    let color: Color
    let samples: [TimedSample<Double>]
}

/// Birden çok hız serisini (ör. indirme/yükleme, okuma/yazma) çizgi olarak çizer.
struct RateHistoryChart: View {
    let series: [RateSeries]

    /// Trafik yokken eksenin 0–0 aralığına çökmemesi için en az ~10 KB/s ölçek.
    private var upperBound: Double {
        let peak = series.flatMap(\.samples).map(\.value).max() ?? 0
        return max(peak * 1.1, 10_000)
    }

    var body: some View {
        Chart {
            ForEach(series, id: \.name) { line in
                ForEach(line.samples, id: \.date) { sample in
                    LineMark(
                        x: .value("Zaman", sample.date),
                        y: .value("Hız", sample.value),
                        series: .value("Seri", line.name)
                    )
                    .foregroundStyle(by: .value("Seri", line.name))
                    .interpolationMethod(.monotone)
                }
            }
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(position: .top, alignment: .leading, spacing: 4)
        .chartYScale(domain: 0...upperBound)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(Format.rate(rate))
                    }
                }
                .font(.system(size: 9))
            }
        }
        .historyChartFrame()
    }
}
