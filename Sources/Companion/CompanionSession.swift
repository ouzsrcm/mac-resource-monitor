import Observation
import UIKit

/// Gönderimin sonucu. Kestirmeler eylemi okunamayan pil ile iCloud hatasını ayırır.
enum CompanionSendOutcome: Equatable {
    case saved
    case skipped
    case unreadable
    case failed
}

/// Bu iPhone veya iPad'in pilini okur ve paylaşılan `BatterySyncService` ile iCloud'a yazar.
/// Görünen ad `UIDevice.current.name` değildir: iOS 16 ve sonrasında bu özellik, özel bir
/// entitlement olmadan genel "iPhone" döner. O entitlement istenmez; adı kullanıcı belirler.
@MainActor
@Observable
final class CompanionSession {
    static let shared = CompanionSession()

    /// Son başarılı gönderime göre en az bu kadar yüzde oynadıysa yeniden yazılır.
    private static let levelDeltaPercent = 2

    private enum Store {
        static let deviceName = "companion.deviceName"
        static let lastSentAt = "companion.lastSentAt"
        static let lastPercent = "companion.lastSentPercent"
        static let lastCharging = "companion.lastSentCharging"
        static let lastName = "companion.lastSentName"
    }

    private(set) var level: Double?
    private(set) var batteryState: UIDevice.BatteryState = .unknown
    private(set) var account: iCloudAccountStatus = .unknown
    private(set) var accountKnown = false
    private(set) var lastSentAt: Date?
    private(set) var isSending = false
    /// Düğmeden gönderim başarısız olursa kısa açıklama. iCloud uyarısı ayrıca gösterilir.
    private(set) var banner: String?

    var deviceName: String {
        didSet { UserDefaults.standard.set(deviceName, forKey: Store.deviceName) }
    }

    @ObservationIgnored private let service = BatterySyncService()
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var lastUploadedPercent: Int?
    @ObservationIgnored private var lastUploadedCharging: Bool?
    @ObservationIgnored private var lastUploadedName: String?
    @ObservationIgnored private var activeUpload: Task<CompanionSendOutcome, Never>?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Store.deviceName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty {
            deviceName = UIDevice.current.model
            UserDefaults.standard.set(deviceName, forKey: Store.deviceName)
        } else {
            deviceName = stored
        }
        lastSentAt = UserDefaults.standard.object(forKey: Store.lastSentAt) as? Date
        if UserDefaults.standard.object(forKey: Store.lastPercent) != nil {
            lastUploadedPercent = UserDefaults.standard.integer(forKey: Store.lastPercent)
            lastUploadedCharging = UserDefaults.standard.bool(forKey: Store.lastCharging)
        }
        lastUploadedName = UserDefaults.standard.string(forKey: Store.lastName)
    }

    var percent: Int? {
        guard let level else { return nil }
        return Int((min(max(level, 0), 1) * 100).rounded())
    }

    /// `.charging` ve `.full` şarjda sayılır.
    var isCharging: Bool {
        batteryState == .charging || batteryState == .full
    }

    var statusText: String {
        switch batteryState {
        case .charging:
            return "Şarj oluyor"
        case .full:
            return "Dolu"
        case .unplugged:
            return "Şarjda değil"
        case .unknown:
            return "Pil durumu okunamadı"
        @unknown default:
            return "Pil durumu okunamadı"
        }
    }

    var iCloudWarning: String? {
        guard accountKnown else { return nil }
        switch account {
        case .noAccount:
            return "iCloud hesabı yok. Pilin Mac'e yazılması için Ayarlar'dan iCloud'a giriş yapın."
        case .restricted:
            return "iCloud bu cihazda kısıtlı. Pil durumu gönderilemiyor."
        case .couldNotDetermine, .temporarilyUnavailable:
            return "iCloud'a şu an ulaşılamıyor."
        case .unknown, .available:
            return nil
        }
    }

    /// Pil bildirimlerini dinlemeye başlar. Yeniden çağrı ek gözlemci kurmaz.
    func start() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        readBattery()
        guard observerTokens.isEmpty else { return }
        let names = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: device,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    CompanionSession.shared.batteryDidChange()
                }
            }
            observerTokens.append(token)
        }
    }

    /// Uygulama açıkken veya öne gelince. Son gönderim yoksa, şarj değiştiyse
    /// veya yüzde en az 2 oynadıysa yazar. Bildirim kaçmış olsa da eşik korunur.
    func refreshWhileOpen() async {
        readBattery()
        await refreshAccount()
        await considerUpload()
    }

    func batteryDidChange() {
        readBattery()
        Task { await considerUpload() }
    }

    /// Düğme, Kestirmeler ve arka plan görevi eşiğe bakmadan güncel durumu yazar.
    func sendNow() async -> CompanionSendOutcome {
        let outcome = await enqueue(force: true)
        switch outcome {
        case .saved, .skipped:
            banner = nil
        case .unreadable:
            banner = "Pil durumu okunamadı."
        case .failed:
            banner = iCloudWarning == nil ? "Gönderilemedi." : nil
        }
        return outcome
    }

    /// Ad alanı düzenlemesi bitince. Ad değişmediyse yeni bir yazma yapmaz.
    func commitDeviceName() async {
        let resolved = resolvedDeviceName
        if deviceName != resolved {
            deviceName = resolved
        }
        guard resolved != lastUploadedName else { return }
        _ = await sendNow()
    }

    private func considerUpload() async {
        _ = await enqueue(force: false)
    }

    private func enqueue(force: Bool) async -> CompanionSendOutcome {
        if !force, !shouldUpload() { return .skipped }
        if let current = activeUpload {
            _ = await current.value
            if activeUpload == current {
                activeUpload = nil
            }
            if !force { return .skipped }
            return await enqueue(force: true)
        }

        let task = Task { @MainActor in
            await self.performUpload()
        }
        activeUpload = task
        let outcome = await task.value
        if activeUpload == task {
            activeUpload = nil
        }
        return outcome
    }

    private func performUpload() async -> CompanionSendOutcome {
        readBattery()
        guard let level, let percent else { return .unreadable }
        if Task.isCancelled { return .failed }

        let charging = isCharging
        let name = resolvedDeviceName
        let record = DeviceBatteryRecord(
            deviceId: LocalDeviceIdentity.identifier,
            deviceName: name,
            deviceModel: CompanionHardware.modelIdentifier,
            platform: CompanionHardware.platform,
            level: level,
            isCharging: charging ? 1 : 0,
            updatedAt: Date()
        )

        isSending = true
        defer { isSending = false }
        let result = await service.upsert(record)
        switch result {
        case .saved:
            rememberSend(percent: percent, charging: charging, name: name, at: record.updatedAt)
            account = .available
            accountKnown = true
            return .saved
        case .notNow, .failed:
            await refreshAccount()
            return .failed
        }
    }

    private func shouldUpload() -> Bool {
        guard let percent else { return false }
        guard let previous = lastUploadedPercent, let previousCharging = lastUploadedCharging else {
            return true
        }
        if isCharging != previousCharging { return true }
        return abs(percent - previous) >= Self.levelDeltaPercent
    }

    private func readBattery() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let raw = device.batteryLevel
        if raw >= 0 {
            level = Double(raw)
        } else {
            level = nil
        }
        batteryState = device.batteryState
    }

    private func refreshAccount() async {
        account = await service.accountStatus()
        accountKnown = true
    }

    private var resolvedDeviceName: String {
        let trimmed = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? UIDevice.current.model : trimmed
    }

    private func rememberSend(percent: Int, charging: Bool, name: String, at date: Date) {
        lastUploadedPercent = percent
        lastUploadedCharging = charging
        lastUploadedName = name
        lastSentAt = date
        banner = nil
        let defaults = UserDefaults.standard
        defaults.set(date, forKey: Store.lastSentAt)
        defaults.set(percent, forKey: Store.lastPercent)
        defaults.set(charging, forKey: Store.lastCharging)
        defaults.set(name, forKey: Store.lastName)
    }
}

/// Kayıttaki `deviceModel` ve `platform`. Pazarlama adı değil, `utsname` kimliği yazılır.
@MainActor
enum CompanionHardware {
    static var modelIdentifier: String {
        var system = utsname()
        uname(&system)
        // machine, utsname içindeki sabit C dizisidir. İşaretçi yalnızca bu yerel kopyayı okur.
        let model = withUnsafePointer(to: &system.machine) { pointer -> String in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? ""
            }
        }
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? UIDevice.current.model : trimmed
    }

    static var platform: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? DeviceBatteryRecord.Platform.iPadOS
            : DeviceBatteryRecord.Platform.iOS
    }
}
