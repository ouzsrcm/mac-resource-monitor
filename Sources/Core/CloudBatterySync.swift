import Foundation
import Observation

/// Bu Mac'in pilini iCloud'a yazar ve diğer cihazları okur.
/// `SamplingEngine` örnekleme döngüsünden ayrı, düşük frekanslı bir görevde çalışır;
/// CloudKit beklerken metrik okuması durmaz.
@MainActor
@Observable
final class CloudBatterySync {
    private(set) var remoteBatteries: [DeviceBatteryRecord] = []
    private(set) var account: iCloudAccountStatus = .unknown
    private(set) var statusKnown = false
    /// En az bir başarılı sorgudan sonra boş liste anlamlıdır.
    private(set) var hasFetched = false

    /// Son başarılı yazmadan bu kadar farklıysa (0–1 ölçeğinde) hemen gönderilir.
    private static let levelDelta = 0.02
    /// Değer değişmese bile `updatedAt` bu süreden daha eski kalmasın.
    private static let heartbeat: TimeInterval = 10 * 60
    private static let openFetchInterval: Duration = .seconds(2 * 60)
    private static let closedFetchInterval: Duration = .seconds(10 * 60)
    /// `retryAfter` yoksa aynı değeri her örnekte yeniden denemeyiz.
    private static let failedUploadPause: TimeInterval = 60

    private struct SentBattery {
        var level: Double
        var isCharging: Bool
        var sentAt: Date
    }

    @ObservationIgnored private let alerts: AlertEngine
    @ObservationIgnored private let service = BatterySyncService()
    @ObservationIgnored private var latestBattery: BatteryStatus?
    @ObservationIgnored private var lastSent: SentBattery?
    @ObservationIgnored private var uploadBlockedUntil: Date?
    @ObservationIgnored private var systemPanelOpen = false
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var uploadTask: Task<Void, Never>?

    init(alerts: AlertEngine) {
        self.alerts = alerts
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self, !Task.isCancelled else { return }
                let interval = self.fetchInterval
                let sleep = Task {
                    _ = try? await Task.sleep(for: interval)
                }
                self.sleepTask = sleep
                await withTaskCancellationHandler {
                    await sleep.value
                } onCancel: {
                    sleep.cancel()
                }
            }
        }
    }

    deinit {
        loop?.cancel()
        sleepTask?.cancel()
        uploadTask?.cancel()
    }

    func setSystemPanelOpen(_ isOpen: Bool) {
        guard systemPanelOpen != isOpen else { return }
        systemPanelOpen = isOpen
        sleepTask?.cancel()
    }

    func settingsDidChange() {
        epoch += 1
        sleepTask?.cancel()
        uploadTask?.cancel()
        uploadTask = nil
        uploadBlockedUntil = nil
        guard AppSettings.iCloudBatterySyncEnabled else {
            remoteBatteries = []
            account = .unknown
            statusKnown = false
            hasFetched = false
            lastSent = nil
            return
        }
    }

    /// Her örneklemede çağrılır. Ağ işi başlatır ama örnekleme döngüsünü beklemez.
    func noteLocalBattery(_ battery: BatteryStatus?) {
        latestBattery = battery
        scheduleUploadIfNeeded()
    }

    private var fetchInterval: Duration {
        systemPanelOpen ? Self.openFetchInterval : Self.closedFetchInterval
    }

    private func refresh() async {
        guard AppSettings.iCloudBatterySyncEnabled else { return }
        if await service.backoffDeadline() != nil { return }

        let generation = epoch
        let status = await service.accountStatus()
        guard !Task.isCancelled, generation == epoch else { return }
        account = status
        statusKnown = true
        guard status == .available else {
            if status == .noAccount || status == .restricted {
                remoteBatteries = []
                hasFetched = false
            }
            return
        }

        let fetched = await service.fetchAll()
        guard !Task.isCancelled, generation == epoch else { return }
        if case .records(let records) = fetched {
            let ownID = LocalDeviceIdentity.identifier
            let others = records.filter { $0.deviceId != ownID }
            let cutoff = Date().addingTimeInterval(-DeviceBatteryRecord.recentWindow)
            let visible = others.filter { $0.updatedAt > cutoff }
            if visible != remoteBatteries {
                remoteBatteries = visible
            }
            hasFetched = true
            alerts.evaluateRemoteBatteries(others)
        }
        scheduleUploadIfNeeded()
    }

    private func scheduleUploadIfNeeded() {
        guard AppSettings.iCloudBatterySyncEnabled else { return }
        guard account == .available else { return }
        guard uploadTask == nil else { return }
        guard let battery = latestBattery else { return }
        guard shouldUpload(battery) else { return }

        let record = DeviceBatteryRecord(
            deviceId: LocalDeviceIdentity.identifier,
            deviceName: MacDeviceInfo.name,
            deviceModel: MacDeviceInfo.modelIdentifier,
            platform: DeviceBatteryRecord.Platform.macOS,
            level: battery.level,
            isCharging: battery.isCharging ? 1 : 0,
            updatedAt: Date()
        )
        let generation = epoch
        let snapshot = SentBattery(level: battery.level, isCharging: battery.isCharging, sentAt: Date())
        uploadTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.service.upsert(record)
            guard !Task.isCancelled, generation == self.epoch else { return }
            self.finishUpload(result, snapshot: snapshot)
        }
    }

    /// Açılışta bir kez, şarj değişince, seviye en az %2 oynayınca ve en geç 10 dakikada bir yazar.
    /// Aynı seviye ve şarj, bu süre dolmadan tekrar gönderilmez.
    private func shouldUpload(_ battery: BatteryStatus) -> Bool {
        if let blocked = uploadBlockedUntil, Date() < blocked {
            guard let last = lastSent else { return false }
            let urgent = battery.isCharging != last.isCharging || abs(battery.level - last.level) >= Self.levelDelta
            if !urgent { return false }
        }
        guard let last = lastSent else { return true }
        if battery.isCharging != last.isCharging { return true }
        if abs(battery.level - last.level) >= Self.levelDelta { return true }
        if Date().timeIntervalSince(last.sentAt) >= Self.heartbeat { return true }
        return false
    }

    private func finishUpload(_ result: CloudWriteResult, snapshot: SentBattery) {
        uploadTask = nil
        switch result {
        case .saved:
            lastSent = SentBattery(level: snapshot.level, isCharging: snapshot.isCharging, sentAt: Date())
            uploadBlockedUntil = nil
        case .notNow(let until):
            uploadBlockedUntil = until
        case .failed:
            uploadBlockedUntil = Date().addingTimeInterval(Self.failedUploadPause)
        }
    }
}
