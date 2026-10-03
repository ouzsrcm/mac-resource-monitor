import SwiftUI

struct NetworkPanel: View {
    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "Ağ", engine: engine) {
            if let network = engine.network {
                StatRow("İndirme", Format.rate(network.download))
                StatRow("Yükleme", Format.rate(network.upload))
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }
            StatRow("Bağlantı", engine.connection.type.title)
        }
    }
}
