import AppKit
import Observation
import os
import UserNotifications

enum AlertKind: String, CaseIterable, Identifiable, Sendable {
    case highCPU
    case memoryPressure
    case thermal
    case lowDiskSpace
    case lowBattery
    case lowDeviceBattery

    var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .highCPU: String(localized: "CPU 30 sn boyunca %90'ın üzerinde")
        case .memoryPressure: String(localized: "Bellek baskısı kritik")
        case .thermal: String(localized: "Termal durum Sıcak veya Kritik")
        case .lowDiskSpace: String(localized: "Disk boş alanı %10'un altında")
        case .lowBattery: String(localized: "Pil %15'in altında ve şarj olmuyor")
        case .lowDeviceBattery: String(localized: "Bir cihazın pili %10'un altında")
        }
    }
}

/// Her örneklemede değerleri kurallara göre kontrol eder ve gerekirse yerel
/// bildirim gönderir. Aynı tür uyarı bekleme süresi dolmadan tekrarlanmaz.
@MainActor
@Observable
final class AlertEngine {
    nonisolated static let cooldown: Duration = .seconds(10 * 60)
    nonisolated static let cpuThreshold = 0.9
    nonisolated static let cpuSustain: Duration = .seconds(30)
    nonisolated static let diskFreeThreshold = 0.1
    nonisolated static let batteryThreshold = 0.15
    /// Aksesuar ve kulaklık pili bu yüzdenin altına düşünce bildirim gider.
    nonisolated static let deviceBatteryThreshold = 10
    /// Aynı cihaz için bildirimler arasında beklenen süre.
    nonisolated static let deviceBatteryCooldown: Duration = .seconds(60 * 60)

    /// Ayarlar penceresinde uyarı göstermek için; henüz sorulmadıysa nil.
    private(set) var authorizationStatus: UNAuthorizationStatus?

    @ObservationIgnored private let sampler: BackgroundSampler
    @ObservationIgnored private let presenter = NotificationPresenter()
    @ObservationIgnored private var lastFired: [AlertKind: ContinuousClock.Instant] = [:]
    /// Cihaz kimliği başına son düşük pil bildirimi. Ortak 10 dakikalık beklemeden bağımsızdır.
    @ObservationIgnored private var deviceBatteryFired: [String: ContinuousClock.Instant] = [:]
    /// CPU'nun eşiği kesintisiz aştığı ilk an.
    @ObservationIgnored private var cpuHighSince: ContinuousClock.Instant?

    private nonisolated static let logger = Logger(subsystem: "tr.ouzsrcm.MenuMonitor", category: "alerts")

    init(sampler: BackgroundSampler) {
        self.sampler = sampler
        UNUserNotificationCenter.current().delegate = presenter
    }

    /// Sistem izin penceresini yalnızca ilk seferde gösterir; sonraki
    /// çağrılar kayıtlı kararı döndürür.
    func requestAuthorization() {
        Task { [weak self] in
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.logger.error("Bildirim izni alınamadı: \(error.localizedDescription, privacy: .public)")
            }
            await self?.refreshAuthorizationStatus()
        }
    }

    func refreshAuthorizationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        authorizationStatus = status
    }

    func evaluate(
        cpu: CPUUsage?,
        memory: MemoryStats?,
        thermal: ProcessInfo.ThermalState?,
        diskSpace: DiskSpace?,
        battery: BatteryStatus?,
        devices: [DeviceBattery]
    ) {
        let now = ContinuousClock.now

        if let cpu, cpu.total > Self.cpuThreshold {
            let since = cpuHighSince ?? now
            cpuHighSince = since
            if since.duration(to: now) >= Self.cpuSustain, shouldFire(.highCPU, at: now) {
                postHighCPU()
            }
        } else {
            cpuHighSince = nil
        }

        if memory?.pressure == .critical, shouldFire(.memoryPressure, at: now) {
            post(.memoryPressure,
                 title: String(localized: "Bellek baskısı kritik"),
                 body: String(localized: "Sistem belleği tükenmek üzere; bazı uygulamaları kapatmayı düşünün."))
        }

        if let thermal, thermal == .serious || thermal == .critical, shouldFire(.thermal, at: now) {
            post(.thermal,
                 title: String(localized: "Mac ısınıyor"),
                 body: String(localized: "Termal durum: \(thermal.title). Sistem performansı düşürebilir."))
        }

        if let diskSpace, diskSpace.freeFraction < Self.diskFreeThreshold, shouldFire(.lowDiskSpace, at: now) {
            let available = Format.dataSize(diskSpace.available)
            let fraction = Format.percent(diskSpace.freeFraction)
            post(.lowDiskSpace,
                 title: String(localized: "Disk alanı azaldı"),
                 body: String(localized: "Başlangıç diskinde \(available) (\(fraction)) boş alan kaldı."))
        }

        if let battery, battery.level < Self.batteryThreshold, !battery.isCharging,
           shouldFire(.lowBattery, at: now) {
            post(.lowBattery,
                 title: String(localized: "Pil azaldı"),
                 body: String(localized: "Pil seviyesi \(Format.percent(battery.level)); güç adaptörünü bağlayın."))
        }

        evaluateDeviceBatteries(devices, at: now)
    }

    private func evaluateDeviceBatteries(_ devices: [DeviceBattery], at now: ContinuousClock.Instant) {
        guard AppSettings.isAlertEnabled(.lowDeviceBattery) else { return }
        for device in devices {
            let low = device.levels.filter { $0.percent < Self.deviceBatteryThreshold }
            guard !low.isEmpty, shouldFireDevice(device.id, at: now) else { continue }
            post(
                .lowDeviceBattery,
                title: String(localized: "Cihaz pili azaldı"),
                body: deviceBatteryBody(name: device.name, low: low),
                identifier: "lowDeviceBattery.\(device.id)"
            )
        }
    }

    private func shouldFireDevice(_ id: String, at now: ContinuousClock.Instant) -> Bool {
        if let last = deviceBatteryFired[id], last.duration(to: now) < Self.deviceBatteryCooldown {
            return false
        }
        deviceBatteryFired[id] = now
        return true
    }

    /// Örnek: "Magic Mouse pili %8". Birden fazla parça düşükse hepsi aynı bildirimde.
    private func deviceBatteryBody(name: String, low: [DeviceBattery.Level]) -> String {
        if low.count == 1, let only = low.first {
            let shown = "%\(only.percent)"
            switch only.slot {
            case .single:
                return String(format: String(localized: "%@ pili %@"), name, shown)
            case .left:
                return String(format: String(localized: "%@ sol kulaklık pili %@"), name, shown)
            case .right:
                return String(format: String(localized: "%@ sağ kulaklık pili %@"), name, shown)
            case .caseBattery:
                return String(format: String(localized: "%@ kutu pili %@"), name, shown)
            }
        }
        let pieces = low.map { level -> String in
            let shown = "%\(level.percent)"
            switch level.slot {
            case .single:
                return shown
            case .left:
                return String(format: String(localized: "sol %@"), shown)
            case .right:
                return String(format: String(localized: "sağ %@"), shown)
            case .caseBattery:
                return String(format: String(localized: "kutu %@"), shown)
            }
        }.joined(separator: ", ")
        return String(format: String(localized: "%@ pili %@"), name, pieces)
    }

    /// Uyarı açık ve bekleme süresi dolmuşsa true döner ve zamanı kaydeder.
    private func shouldFire(_ kind: AlertKind, at now: ContinuousClock.Instant) -> Bool {
        guard AppSettings.isAlertEnabled(kind) else { return false }
        if let last = lastFired[kind], last.duration(to: now) < Self.cooldown {
            return false
        }
        lastFired[kind] = now
        return true
    }

    private func postHighCPU() {
        // En çok CPU kullanan süreci bulmak için ayrı, tek seferlik bir
        // ölçüm yapıyoruz (panel kapalıyken süreç listesi tutulmuyor).
        Task { [weak self, sampler] in
            let top = await sampler.topCPUProcess()
            var body = String(localized: "İşlemci 30 saniyedir %90'ın üzerinde.")
            if let top {
                let name = NSRunningApplication(processIdentifier: top.pid)?.localizedName ?? top.name
                let usage = Format.precisePercent(top.cpu)
                body += " " + String(localized: "En çok kullanan: \(name) (\(usage)).")
            }
            self?.post(.highCPU, title: String(localized: "Yüksek CPU kullanımı"), body: body)
        }
    }

    private func post(_ kind: AlertKind, title: String, body: String, identifier: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Tür başına sabit kimlik: aynı türün yeni bildirimi eskisinin yerini alır.
        // Cihaz pili cihaz kimliğini kullanır; böylece her cihazın bildirimi ayrı kalır.
        let request = UNNotificationRequest(identifier: identifier ?? kind.rawValue, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Bildirim gönderilemedi: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Uygulama öndeyken (ör. bir panel açıkken) de bildirimin banner olarak
/// gösterilmesini sağlar; aksi halde sistem öndeki uygulamanın bildirimini gizler.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
