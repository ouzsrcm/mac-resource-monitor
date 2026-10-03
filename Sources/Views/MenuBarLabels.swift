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

struct DiskLabel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.diskLabelMode) private var mode = DiskLabelMode.freeSpace

    var body: some View {
        switch mode {
        case .freeSpace:
            let value = engine.diskSpace.map { Format.percent($0.freeFraction) } ?? "–%"
            Text("\(Image(systemName: "internaldrive")) \(value)")
                .monospacedDigit()
        case .throughput:
            let read = engine.diskIO.map { Format.rate($0.read) } ?? "–"
            let write = engine.diskIO.map { Format.rate($0.write) } ?? "–"
            Text("\(Image(systemName: "internaldrive")) R \(read) W \(write)")
                .monospacedDigit()
        }
    }
}

struct SystemLabel: View {
    let engine: SamplingEngine

    var body: some View {
        let thermometer = Image(systemName: engine.thermal?.symbolName ?? "thermometer.medium")
        if let battery = engine.battery {
            Text("\(thermometer) \(Format.percent(battery.level))")
                .monospacedDigit()
        } else {
            Text("\(thermometer)")
        }
    }
}
