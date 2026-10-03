import SwiftUI

struct SystemPanel: View {
    let engine: SamplingEngine

    var body: some View {
        PanelContainer(title: "Sistem", kind: .system, engine: engine) {
            HStack {
                Label("Termal Durum", systemImage: engine.thermal?.symbolName ?? "thermometer.medium")
                    .foregroundStyle(.secondary)
                Spacer()
                ThermalBadge(state: engine.thermal)
            }

            if let battery = engine.battery {
                BatterySection(battery: battery)
            }
        }
    }
}

private struct BatterySection: View {
    let battery: BatteryStatus

    private var symbolName: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var tint: Color {
        if battery.isCharging { return .green }
        return battery.level < AlertEngine.batteryThreshold ? .red : .primary
    }

    private var status: String {
        if battery.isCharging { return "Şarj oluyor" }
        if battery.isPluggedIn { return "Adaptöre bağlı" }
        return "Pil kullanılıyor"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(Format.percent(battery.level))
                    .font(.title2.bold())
                    .monospacedDigit()
            }
            StatRow("Durum", status)
            if let minutes = battery.minutesToEmpty {
                StatRow("Kalan süre", Format.minutes(minutes))
            } else if let minutes = battery.minutesToFull {
                StatRow("Tam dolmasına", Format.minutes(minutes))
            }
        }
    }
}
