import SwiftUI

// Menü bar etiketleri tek bir `Text` veya `Image` olarak kurulur; MenuBarExtra
// etiketinde HStack gibi düzen kapları güvenilir şekilde çizilmez.

struct CPULabel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.menuBarLabelStyle) private var style = AppSettings.defaultMenuBarLabelStyle

    var body: some View {
        switch style {
        case .iconOnly:
            Image(systemName: "cpu")
        case .iconAndValue:
            let value = engine.cpu.map { Format.percent($0.total) } ?? "–%"
            Text("\(Image(systemName: "cpu")) \(value)")
                .monospacedDigit()
        }
    }
}

struct MemoryLabel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.menuBarLabelStyle) private var style = AppSettings.defaultMenuBarLabelStyle

    var body: some View {
        switch style {
        case .iconOnly:
            Image(systemName: "memorychip")
        case .iconAndValue:
            let value = engine.memory.map { Format.percent($0.usedFraction) } ?? "–%"
            Text("\(Image(systemName: "memorychip")) \(value)")
                .monospacedDigit()
        }
    }
}

struct NetworkLabel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.menuBarLabelStyle) private var style = AppSettings.defaultMenuBarLabelStyle

    var body: some View {
        switch style {
        case .iconOnly:
            Image(systemName: "network")
        case .iconAndValue:
            let throughput = engine.network?.throughput
            let download = throughput.map { Format.rate($0.download) } ?? "–"
            let upload = throughput.map { Format.rate($0.upload) } ?? "–"
            Text(verbatim: "↓\(download) ↑\(upload)")
                .monospacedDigit()
        }
    }
}

struct DiskLabel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.menuBarLabelStyle) private var style = AppSettings.defaultMenuBarLabelStyle
    @AppStorage(AppSettings.Key.diskLabelMode) private var mode = DiskLabelMode.freeSpace

    var body: some View {
        switch (style, mode) {
        case (.iconOnly, _):
            Image(systemName: "internaldrive")
        case (.iconAndValue, .freeSpace):
            let value = engine.diskSpace.map { Format.percent($0.freeFraction) } ?? "–%"
            Text("\(Image(systemName: "internaldrive")) \(value)")
                .monospacedDigit()
        case (.iconAndValue, .throughput):
            let read = engine.diskIO.map { Format.rate($0.read) } ?? "–"
            let write = engine.diskIO.map { Format.rate($0.write) } ?? "–"
            Text("\(Image(systemName: "internaldrive")) R \(read) W \(write)")
                .monospacedDigit()
        }
    }
}

struct SystemLabel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.menuBarLabelStyle) private var style = AppSettings.defaultMenuBarLabelStyle

    var body: some View {
        let thermometer = Image(systemName: engine.thermal?.symbolName ?? "thermometer.medium")
        switch (style, engine.battery) {
        case (_, nil):
            Text("\(thermometer)")
        case (.iconOnly, let battery?):
            Text("\(thermometer) \(Image(systemName: battery.symbolName))")
        case (.iconAndValue, let battery?):
            Text("\(thermometer) \(Format.percent(battery.level))")
                .monospacedDigit()
        }
    }
}
