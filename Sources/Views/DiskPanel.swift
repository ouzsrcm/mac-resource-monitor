import SwiftUI

struct DiskPanel: View {
    private static let readColor = Color.blue
    private static let writeColor = Color.pink

    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "Disk", kind: .disk, engine: engine) {
            if let space = engine.diskSpace {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.dataSize(space.available))
                        .font(.title2.bold())
                    Text("boş / \(Format.dataSize(space.total))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.percent(space.usedFraction))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()

                UsageBar(
                    fraction: space.usedFraction,
                    tint: space.freeFraction < AlertEngine.diskFreeThreshold ? .red : .blue
                )
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }

            if let io = engine.diskIO {
                HStack(spacing: 16) {
                    rate(title: "Okuma", value: io.read, color: Self.readColor)
                    rate(title: "Yazma", value: io.write, color: Self.writeColor)
                }

                RateHistoryChart(series: [
                    RateSeries(name: "Okuma", color: Self.readColor, samples: engine.diskReadHistory.elements),
                    RateSeries(name: "Yazma", color: Self.writeColor, samples: engine.diskWriteHistory.elements),
                ])
            }
        }
    }

    private func rate(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(color)
            Text(Format.rate(value))
                .font(.title3.bold())
                .monospacedDigit()
        }
    }
}
