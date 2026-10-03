import SwiftUI

struct NetworkPanel: View {
    private static let downloadColor = Color.blue
    private static let uploadColor = Color.orange

    let engine: SamplingEngine

    private var interfaceName: String? { engine.connection.interfaceName }

    private var ipv4Address: String? {
        guard let interfaceName else { return nil }
        return engine.network?.ipv4Addresses[interfaceName]
    }

    var body: some View {
        PanelContainer(title: "Ağ", kind: .network, engine: engine) {
            if let throughput = engine.network?.throughput {
                HStack(spacing: 16) {
                    rate(symbol: "arrow.down", value: throughput.download, color: Self.downloadColor)
                    rate(symbol: "arrow.up", value: throughput.upload, color: Self.uploadColor)
                }

                RateHistoryChart(series: [
                    RateSeries(name: "İndirme", color: Self.downloadColor, samples: engine.downloadHistory.elements),
                    RateSeries(name: "Yükleme", color: Self.uploadColor, samples: engine.uploadHistory.elements),
                ])
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                StatRow("Bağlantı", engine.connection.type.title)
                StatRow("Arayüz", interfaceName ?? "—")
                StatRow("IPv4", ipv4Address ?? "—")
            }

            if let network = engine.network {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Açılıştan beri")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StatRow("İndirilen", Format.dataSize(network.totalReceived))
                    StatRow("Yüklenen", Format.dataSize(network.totalSent))
                }
            }
        }
    }

    private func rate(symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(Format.rate(value))
                .font(.title3.bold())
                .monospacedDigit()
        }
    }
}
