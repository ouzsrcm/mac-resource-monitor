import Charts
import SwiftUI

/// İndirme ve yükleme hızlarını iki ayrı çizgi serisi olarak çizer.
struct NetworkHistoryChart: View {
    static let downloadColor = Color.blue
    static let uploadColor = Color.orange

    private static let downloadSeries = "İndirme"
    private static let uploadSeries = "Yükleme"

    let download: [TimedSample<Double>]
    let upload: [TimedSample<Double>]

    /// Trafik yokken eksenin 0–0 aralığına çökmemesi için en az ~10 KB/s ölçek.
    private var upperBound: Double {
        let peak = (download + upload).map(\.value).max() ?? 0
        return max(peak * 1.1, 10_000)
    }

    var body: some View {
        Chart {
            ForEach(download, id: \.date) { sample in
                LineMark(
                    x: .value("Zaman", sample.date),
                    y: .value("Hız", sample.value),
                    series: .value("Yön", Self.downloadSeries)
                )
                .foregroundStyle(by: .value("Yön", Self.downloadSeries))
                .interpolationMethod(.monotone)
            }
            ForEach(upload, id: \.date) { sample in
                LineMark(
                    x: .value("Zaman", sample.date),
                    y: .value("Hız", sample.value),
                    series: .value("Yön", Self.uploadSeries)
                )
                .foregroundStyle(by: .value("Yön", Self.uploadSeries))
                .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([
            Self.downloadSeries: Self.downloadColor,
            Self.uploadSeries: Self.uploadColor,
        ])
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
