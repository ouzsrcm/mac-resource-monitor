import SwiftUI
import UserNotifications

struct SettingsView: View {
    let engine: SamplingEngine

    @AppStorage(AppSettings.Key.showCPU) private var showCPU = true
    @AppStorage(AppSettings.Key.showRAM) private var showRAM = true
    @AppStorage(AppSettings.Key.showNetwork) private var showNetwork = true
    @AppStorage(AppSettings.Key.showDisk) private var showDisk = true
    @AppStorage(AppSettings.Key.showSystem) private var showSystem = true
    @AppStorage(AppSettings.Key.showDeviceBatteries) private var showDeviceBatteries = true
    @AppStorage(AppSettings.Key.iCloudBatterySync) private var iCloudBatterySync = true

    @AppStorage(AppSettings.Key.idleInterval) private var idleInterval = AppSettings.defaultIdleInterval
    @AppStorage(AppSettings.Key.activeInterval) private var activeInterval = AppSettings.defaultActiveInterval
    @AppStorage(AppSettings.Key.diskLabelMode) private var diskLabelMode = DiskLabelMode.freeSpace
    @AppStorage(AppSettings.Key.menuBarLabelStyle) private var labelStyle = AppSettings.defaultMenuBarLabelStyle
    @AppStorage(AppSettings.Key.appLanguage) private var language = AppLanguage.system

    private var visibleCount: Int {
        [showCPU, showRAM, showNetwork, showDisk, showSystem].filter { $0 }.count
    }

    var body: some View {
        Form {
            Section("Genel") {
                Picker("Dil", selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Text("Dil değişikliği yeniden başlatınca geçerli olur.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Yeniden Başlat") { relaunch() }
                    }
                }
                Picker("Menü bar", selection: $labelStyle) {
                    ForEach(MenuBarLabelStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section {
                visibilityToggle("İşlemci", isOn: $showCPU)
                visibilityToggle("Bellek", isOn: $showRAM)
                visibilityToggle("Ağ", isOn: $showNetwork)
                visibilityToggle("Disk", isOn: $showDisk)
                visibilityToggle("Sistem (termal ve pil)", isOn: $showSystem)
            } header: {
                Text("Görünür öğeler")
            } footer: {
                Text("Uygulama Dock'ta görünmediği için en az bir öğe açık kalmalı.")
                    .foregroundStyle(.secondary)
            }

            Section("Sistem paneli") {
                Toggle("Cihaz pillerini göster", isOn: $showDeviceBatteries)
                Toggle("iCloud cihaz senkronizasyonu", isOn: $iCloudBatterySync)
            }

            Section("Örnekleme") {
                Picker("Panel kapalıyken", selection: $idleInterval) {
                    ForEach(AppSettings.idleIntervalOptions, id: \.self) { value in
                        Text(Format.seconds(value)).tag(value)
                    }
                }
                Picker("Panel açıkken", selection: $activeInterval) {
                    ForEach(AppSettings.activeIntervalOptions, id: \.self) { value in
                        Text(Format.seconds(value)).tag(value)
                    }
                }
            }

            Section("Uyarılar") {
                ForEach(AlertKind.allCases) { kind in
                    AlertToggle(kind: kind)
                }
                if engine.alerts.authorizationStatus == .denied {
                    HStack {
                        Label("Bildirim izni kapalı", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Sistem Ayarları…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section("Disk etiketi") {
                Picker("Menü barda", selection: $diskLabelMode) {
                    ForEach(DiskLabelMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(labelStyle == .iconOnly)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Pencere zaten açıkken tekrar istenirse de öne gelsin.
            NSApp.activate()
        }
        .task {
            await engine.alerts.refreshAuthorizationStatus()
        }
        .onChange(of: idleInterval) { engine.samplingSettingsDidChange() }
        .onChange(of: activeInterval) { engine.samplingSettingsDidChange() }
        .onChange(of: showDeviceBatteries) { engine.deviceBatterySettingsDidChange() }
        .onChange(of: iCloudBatterySync) { engine.cloud.settingsDidChange() }
        .onChange(of: language) { language.apply() }
    }

    private func visibilityToggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .disabled(isOn.wrappedValue && visibleCount == 1)
    }

    /// Yeni bir kopya başlatıp mevcut süreci sonlandırır; yeni kopya
    /// `AppleLanguages` tercihini açılışta okur.
    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        Task {
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApp.terminate(nil)
        }
    }
}

private struct AlertToggle: View {
    let kind: AlertKind
    @AppStorage private var isOn: Bool

    init(kind: AlertKind) {
        self.kind = kind
        _isOn = AppStorage(wrappedValue: true, AppSettings.Key.alertEnabled(kind))
    }

    var body: some View {
        Toggle(kind.settingsTitle, isOn: $isOn)
    }
}
