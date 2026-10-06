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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                generalCard
                VStack(spacing: 12) {
                    samplingCard
                    systemCard
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            HStack(alignment: .top, spacing: 12) {
                visibilityCard
                alertsCard
            }
        }
        .padding(16)
        .frame(width: 760)
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

    private var generalCard: some View {
        SettingsCard("Genel", systemImage: "gearshape") {
            menuRow("Dil", selection: $language) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.title).tag(language)
                }
            }
            if language != AppLanguage.atLaunch {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Dil değişikliği yeniden başlatınca geçerli olur.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Yeniden Başlat") { relaunch() }
                        .controlSize(.small)
                }
            }

            segmentedRow("Menü bar", selection: $labelStyle) {
                ForEach(MenuBarLabelStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }

            segmentedRow("Disk etiketi", selection: $diskLabelMode) {
                ForEach(DiskLabelMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .disabled(labelStyle == .iconOnly)
            if labelStyle == .iconOnly {
                Text("İkon ve değer seçilince menü barda görünür.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var samplingCard: some View {
        SettingsCard("Örnekleme", systemImage: "timer") {
            menuRow("Panel kapalıyken", selection: $idleInterval) {
                ForEach(AppSettings.idleIntervalOptions, id: \.self) { value in
                    Text(Format.seconds(value)).tag(value)
                }
            }
            menuRow("Panel açıkken", selection: $activeInterval) {
                ForEach(AppSettings.activeIntervalOptions, id: \.self) { value in
                    Text(Format.seconds(value)).tag(value)
                }
            }
        }
    }

    private var systemCard: some View {
        SettingsCard("Sistem paneli", systemImage: "battery.100percent") {
            Toggle("Cihaz pillerini göster", isOn: $showDeviceBatteries)
            if AppSettings.iCloudSyncAvailable {
                Toggle("iCloud cihaz senkronizasyonu", isOn: $iCloudBatterySync)
            }
        }
    }

    private var visibilityCard: some View {
        SettingsCard("Görünür öğeler", systemImage: "eye") {
            visibilityToggle("İşlemci", isOn: $showCPU)
            visibilityToggle("Bellek", isOn: $showRAM)
            visibilityToggle("Ağ", isOn: $showNetwork)
            visibilityToggle("Disk", isOn: $showDisk)
            visibilityToggle("Sistem (termal ve pil)", isOn: $showSystem)
            Text("Uygulama Dock'ta görünmediği için en az bir öğe açık kalmalı.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var alertsCard: some View {
        SettingsCard("Uyarılar", systemImage: "bell") {
            ForEach(AlertKind.allCases.filter { AppSettings.iCloudSyncAvailable || $0 != .lowRemoteBattery }) { kind in
                AlertToggle(kind: kind)
            }
            if engine.alerts.authorizationStatus == .denied {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Bildirim izni kapalı", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Sistem Ayarları…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func visibilityToggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .disabled(isOn.wrappedValue && visibleCount == 1)
    }

    private func menuRow<Selection: Hashable>(
        _ title: LocalizedStringKey,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        LabeledContent(title) {
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func segmentedRow<Selection: Hashable>(
        _ title: LocalizedStringKey,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Picker(title, selection: selection, content: content)
                .pickerStyle(.segmented)
                .labelsHidden()
        }
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

/// Ayar kartı. Gruplu formun tek sütunlu dikey akışı yerine yan yana durur.
private struct SettingsCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
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
