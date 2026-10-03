import SwiftUI

// Menü bar etiketleri tek bir `Text` olarak kurulur; MenuBarExtra etiketinde
// HStack gibi düzen kapları güvenilir şekilde çizilmez.

struct CPULabel: View {
    let engine: SamplingEngine

    var body: some View {
        let value = engine.cpu.map { Format.percent($0.total) } ?? "–%"
        Text("\(Image(systemName: "cpu")) \(value)")
            .monospacedDigit()
    }
}

struct MemoryLabel: View {
    let engine: SamplingEngine

    var body: some View {
        let value = engine.memory.map { Format.percent($0.usedFraction) } ?? "–%"
        Text("\(Image(systemName: "memorychip")) \(value)")
            .monospacedDigit()
    }
}

struct NetworkLabel: View {
    let engine: SamplingEngine

    var body: some View {
        let throughput = engine.network?.throughput
        let download = throughput.map { Format.rate($0.download) } ?? "–"
        let upload = throughput.map { Format.rate($0.upload) } ?? "–"
        Text(verbatim: "↓\(download) ↑\(upload)")
            .monospacedDigit()
    }
}
