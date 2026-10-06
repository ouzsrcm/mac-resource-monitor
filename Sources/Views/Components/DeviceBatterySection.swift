import AppKit
import SwiftUI

struct DeviceBatterySection: View {
    let devices: [DeviceBattery]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cihazlar")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(devices) { device in
                DeviceBatteryRow(device: device)
            }
        }
    }
}

private struct DeviceBatteryRow: View {
    let device: DeviceBattery

    private var showsSingleLine: Bool {
        device.levels.count == 1 && device.levels[0].slot == .single
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: deviceSymbol(device))
                    .frame(width: 18)
                    .foregroundStyle(iconTint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(device.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !device.isConnected {
                        Text("Bağlı değil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                if showsSingleLine, let level = device.levels.first {
                    percentLabel(level.percent, charging: device.isCharging == true)
                }
            }
            if showsSingleLine, let level = device.levels.first {
                DeviceBatteryBar(percent: level.percent)
                    .padding(.leading, 26)
            } else {
                ForEach(device.levels) { level in
                    HStack(spacing: 6) {
                        slotSymbol(level.slot)
                            .frame(width: 16)
                        Text(slotTitle(level.slot))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                        percentLabel(level.percent, charging: false)
                        DeviceBatteryBar(percent: level.percent)
                    }
                    .padding(.leading, 26)
                }
            }
        }
    }

    private var iconTint: Color {
        guard let worst = device.levels.map(\.percent).min() else { return .secondary }
        if worst < AlertEngine.deviceBatteryThreshold { return .red }
        if worst < 20 { return .orange }
        return .secondary
    }

    @ViewBuilder
    private func slotSymbol(_ slot: DeviceBattery.Slot) -> some View {
        if slot == .caseBattery {
            Image(systemName: caseSymbol)
                .foregroundStyle(.secondary)
        } else {
            Color.clear
        }
    }

    private var caseSymbol: String {
        let name = device.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if name.contains("airpod") {
            return DeviceSymbol.named("airpods.chargingcase", fallback: "earbuds.case")
        }
        return DeviceSymbol.named("earbuds.case", fallback: "battery.100")
    }

    private func percentLabel(_ percent: Int, charging: Bool) -> some View {
        HStack(spacing: 2) {
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            Text("\(percent)%")
                .monospacedDigit()
                .foregroundStyle(batteryTint(percent))
                .frame(minWidth: 36, alignment: .trailing)
        }
    }

    private func slotTitle(_ slot: DeviceBattery.Slot) -> String {
        switch slot {
        case .single: ""
        case .left: String(localized: "Sol")
        case .right: String(localized: "Sağ")
        case .caseBattery: String(localized: "Kutu")
        }
    }
}

private struct DeviceBatteryBar: View {
    let percent: Int

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(min(max(percent, 0), 100)) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(batteryTint(percent))
                    .frame(width: width)
            }
        }
        .frame(height: 6)
        .accessibilityLabel("\(percent)%")
    }
}

private func batteryTint(_ percent: Int) -> Color {
    if percent < AlertEngine.deviceBatteryThreshold { return .red }
    if percent < 20 { return .orange }
    return .green
}

private func deviceSymbol(_ device: DeviceBattery) -> String {
    switch device.kind {
    case .mouse:
        return DeviceSymbol.named("magicmouse", fallback: "computermouse")
    case .keyboard:
        return DeviceSymbol.named("keyboard", fallback: "keyboard")
    case .trackpad:
        // "trackpad" bu macOS sürümünde yok; el ve dikdörtgen sembolü kullanılır.
        return DeviceSymbol.named("trackpad", fallback: "rectangle.and.hand.point.up.left")
    case .headphones:
        let name = device.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if name.contains("airpod") {
            return DeviceSymbol.named("airpods", fallback: "headphones")
        }
        if name.contains("beat") {
            return DeviceSymbol.named("beats.headphones", fallback: "headphones")
        }
        return DeviceSymbol.named("headphones", fallback: "earbuds")
    case .other:
        return DeviceSymbol.named("wave.3.right", fallback: "dot.radiowaves.right")
    }
}

private enum DeviceSymbol {
    static func named(_ preferred: String, fallback: String) -> String {
        if NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil {
            return preferred
        }
        if NSImage(systemSymbolName: fallback, accessibilityDescription: nil) != nil {
            return fallback
        }
        return "wave.3.right"
    }
}
