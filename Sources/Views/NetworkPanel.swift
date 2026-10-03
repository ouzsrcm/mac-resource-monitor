import SwiftUI

struct NetworkPanel: View {
    let engine: SamplingEngine

    private var interfaceName: String? { engine.connection.interfaceName }

    private var ipv4Address: String? {
        guard let interfaceName else { return nil }
        return engine.network?.ipv4Addresses[interfaceName]
    }

    var body: some View {
        PanelContainer(title: "Ağ", engine: engine) {
            if let throughput = engine.network?.throughput {
                HStack(spacing: 16) {
                    rate(symbol: "arrow.down", value: throughput.download, color: NetworkHistoryChart.downloadColor)
                    rate(symbol: "arrow.up", value: throughput.upload, color: NetworkHistoryChart.uploadColor)
                }

                NetworkHistoryChart(
                    download: engine.downloadHistory.elements,
                    upload: engine.uploadHistory.elements
                )
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
