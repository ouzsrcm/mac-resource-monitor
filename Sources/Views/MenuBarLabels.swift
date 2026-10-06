import AppKit
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
        let thermal = engine.thermal?.symbolName ?? "thermometer.medium"
        switch (style, engine.battery) {
        case (_, nil):
            Image(systemName: thermal)
        case (.iconOnly, let battery?):
            // Yalnızca görsel içeren `Text` menü barında sıfır genişlikte kalıyor;
            // öğe tıklanır ama simge çizilmez. İki sembol tek şablon görselde birleşir.
            SystemStatusIcon(symbols: [thermal, battery.symbolName])
        case (.iconAndValue, let battery?):
            Text("\(Image(systemName: thermal)) \(Format.percent(battery.level))")
                .monospacedDigit()
        }
    }
}

/// Menü barında yan yana duran sembolleri tek `Image` olarak çizer.
private struct SystemStatusIcon: View {
    let symbols: [String]

    var body: some View {
        Image(nsImage: SystemStatusIconImage.image(symbols: symbols))
            .renderingMode(.template)
            .accessibilityLabel(Text("Sistem"))
    }
}

@MainActor
private enum SystemStatusIconImage {
    private static var cache: [String: NSImage] = [:]

    static func image(symbols: [String]) -> NSImage {
        let key = symbols.joined(separator: "|")
        if let cached = cache[key] { return cached }
        let image = render(symbols: symbols)
        cache[key] = image
        return image
    }

    private static func render(symbols: [String]) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .regular)
        let parts = symbols.compactMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        }
        guard !parts.isEmpty else {
            return NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: nil) ?? NSImage()
        }
        if parts.count == 1, let only = parts.first {
            only.isTemplate = true
            return only
        }

        let spacing: CGFloat = 4
        let width = parts.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(parts.count - 1)
        let height = parts.map(\.size.height).max() ?? 0
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for part in parts {
                let rect = NSRect(
                    x: x,
                    y: (height - part.size.height) / 2,
                    width: part.size.width,
                    height: part.size.height
                )
                part.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                x += part.size.width + spacing
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
