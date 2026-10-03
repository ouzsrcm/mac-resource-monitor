import SwiftUI

struct CPUPanel: View {
    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "İşlemci", engine: engine) {
            if let cpu = engine.cpu {
                StatRow("Toplam", Format.precisePercent(cpu.total))
                StatRow("Kullanıcı", Format.precisePercent(cpu.user))
                StatRow("Sistem", Format.precisePercent(cpu.system))
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
