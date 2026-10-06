import SwiftUI

struct SystemPanel: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.showDeviceBatteries) private var showDeviceBatteries = true
    @AppStorage(AppSettings.Key.iCloudBatterySync) private var iCloudSyncSetting = true

    private var iCloudSync: Bool {
        AppSettings.iCloudSyncAvailable && iCloudSyncSetting
    }

    private var localDevices: [DeviceBattery] {
        showDeviceBatteries ? engine.deviceBatteries : []
    }

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

            if !localDevices.isEmpty || iCloudSync {
                Divider()
                DeviceBatterySection(
                    devices: localDevices,
                    showsICloud: iCloudSync,
                    iCloudStatusKnown: engine.cloud.statusKnown,
                    iCloudAccount: engine.cloud.account,
                    iCloudDevices: engine.cloud.remoteBatteries,
                    iCloudHasFetched: engine.cloud.hasFetched
                )
            }
        }
    }
}

private struct BatterySection: View {
    let battery: BatteryStatus

    private var tint: Color {
        if battery.isCharging { return .green }
        return battery.level < AlertEngine.batteryThreshold ? .red : .primary
    }

    private var status: String {
        if battery.isCharging { return String(localized: "Şarj oluyor") }
        if battery.isPluggedIn { return String(localized: "Adaptöre bağlı") }
        return String(localized: "Pil kullanılıyor")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: battery.symbolName)
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
