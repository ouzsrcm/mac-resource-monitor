import SwiftUI

struct CPUPanel: View {
    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "İşlemci", kind: .cpu, engine: engine) {
            if let cpu = engine.cpu {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.precisePercent(cpu.total))
                        .font(.title2.bold())
                        .monospacedDigit()
                    StatRow("Kullanıcı", Format.precisePercent(cpu.user))
                    StatRow("Sistem", Format.precisePercent(cpu.system))
                }

                PercentHistoryChart(samples: engine.cpuHistory.elements, tint: .blue)

                if let perCore = engine.perCore {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(perCore.groups.indices, id: \.self) { index in
                            CoreGroupView(group: perCore.groups[index])
                        }
                    }
                }

                ProcessList(title: "En çok CPU kullananlar", processes: engine.processes?.topCPU) {
                    Format.precisePercent($0.cpu)
                }
            } else {
                Text("Ölçülüyor…")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
