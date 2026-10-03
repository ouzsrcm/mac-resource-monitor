import SwiftUI

struct MemoryPanel: View {
    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "Bellek", kind: .memory, engine: engine) {
            if let memory = engine.memory {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.bytes(memory.used))
                        .font(.title2.bold())
                    Text("/ \(Format.bytes(memory.total))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.percent(memory.usedFraction))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()

                MemoryBreakdownBar(stats: memory)

                HStack {
                    Text("Bellek Baskısı")
                        .foregroundStyle(.secondary)
                    Spacer()
                    PressureBadge(pressure: memory.pressure)
                }

                PercentHistoryChart(
                    samples: engine.memoryHistory.elements,
                    tint: memory.pressure?.color ?? .green
                )

                VStack(alignment: .leading, spacing: 4) {
                    StatRow("Takas", "\(Format.bytes(memory.swapUsed)) / \(Format.bytes(memory.swapTotal))")
                    if memory.swapUsed > 0 {
                        Label("Swap kullanılıyor, RAM yetersiz kalabilir", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ProcessList(title: "En çok bellek kullananlar", processes: engine.processes?.topMemory) {
                    Format.bytes($0.memory)
                }
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
