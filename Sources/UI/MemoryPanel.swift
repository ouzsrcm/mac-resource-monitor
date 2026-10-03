import SwiftUI

struct MemoryPanel: View {
    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "Bellek", engine: engine) {
            if let memory = engine.memory {
                StatRow(
                    "Kullanılan",
                    "\(Format.bytes(memory.used)) / \(Format.bytes(memory.total)) (\(Format.percent(memory.usedFraction)))"
                )
                StatRow("Uygulama Belleği", Format.bytes(memory.app))
                StatRow("Kalıcı Bellek", Format.bytes(memory.wired))
                StatRow("Sıkıştırılmış", Format.bytes(memory.compressed))
                StatRow("Bellek Baskısı", memory.pressure?.title ?? "Bilinmiyor")
                StatRow("Takas", "\(Format.bytes(memory.swapUsed)) / \(Format.bytes(memory.swapTotal))")
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
