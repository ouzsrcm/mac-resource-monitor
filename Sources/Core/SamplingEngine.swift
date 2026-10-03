import Foundation
import Observation

enum PanelKind: Sendable, Hashable {
    case cpu
    case memory
    case network
}

/// Tüm metrik okuyucularını tek bir async döngüde sırayla çağırır ve
/// sonuçları yayınlar. Menü bar öğeleri kendi zamanlayıcılarını kurmaz.
@MainActor
@Observable
final class SamplingEngine {
    nonisolated static let historyCapacity = 120
    nonisolated static let idleInterval: Duration = .seconds(3)
    nonisolated static let activeInterval: Duration = .seconds(1)

    private(set) var cpu: CPUUsage?
    private(set) var perCore: PerCoreCPUUsage?
    private(set) var memory: MemoryStats?
    private(set) var network: NetworkStats?
    /// Yalnızca CPU veya bellek paneli açıkken güncellenir; aksi halde nil.
    private(set) var processes: ProcessSnapshot?
    private(set) var selfUsage: SelfUsage?

    /// Toplam CPU kullanımı (0.0–1.0).
    private(set) var cpuHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)
    /// Kullanılan bellek oranı (0.0–1.0).
    private(set) var memoryHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)
    /// Byte/saniye.
    private(set) var downloadHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)
    /// Byte/saniye.
    private(set) var uploadHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)

    let connection = ConnectionMonitor()

    /// Şu anda açık olan paneller. Paneller `panelDidAppear(_:)` /
    /// `panelDidDisappear(_:)` ile günceller.
    private(set) var openPanels: Set<PanelKind> = []

    var openPanelCount: Int { openPanels.count }

    var interval: Duration {
        openPanels.isEmpty ? Self.idleInterval : Self.activeInterval
    }

    /// Süreç taraması pahalı olduğu için yalnızca süreç listesi gösteren
    /// paneller açıkken yapılır.
    private var needsProcesses: Bool {
        !openPanels.isDisjoint(with: [.cpu, .memory])
    }

    @ObservationIgnored private var cpuMonitor = CPUMonitor()
    @ObservationIgnored private var perCoreMonitor = PerCoreCPUMonitor()
    @ObservationIgnored private var memoryMonitor = MemoryMonitor()
    @ObservationIgnored private var networkMonitor = NetworkMonitor()
    @ObservationIgnored private var selfUsageMonitor = SelfUsageMonitor()
    @ObservationIgnored private let processSampler = ProcessSampler()

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pendingSleep: Task<Void, Never>?
    /// Devam eden arka plan süreç okuması; varken yenisi başlatılmaz.
    @ObservationIgnored private var processRead: Task<Void, Never>?
    @ObservationIgnored private var processResetPending = false

    init() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // `self`'i yalnızca senkron adımda güçlü tutuyoruz; beklerken
                // tutmamak motorun serbest bırakılabilmesini sağlar.
                guard let sleep = self?.sampleAndScheduleSleep() else { return }
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
        pendingSleep?.cancel()
        processRead?.cancel()
    }

    func panelDidAppear(_ kind: PanelKind) {
        updateOpenPanels { $0.insert(kind) }
    }

    func panelDidDisappear(_ kind: PanelKind) {
        updateOpenPanels { $0.remove(kind) }
    }

    private func updateOpenPanels(_ change: (inout Set<PanelKind>) -> Void) {
        let oldInterval = interval
        let neededProcesses = needsProcesses
        change(&openPanels)

        if neededProcesses && !needsProcesses {
            // Panel kapalıyken eski liste gösterilmesin ve tekrar açıldığında
            // CPU farkı uzun aradan değil, yeni örneklerden hesaplansın.
            processes = nil
            processResetPending = true
        }
        if interval != oldInterval || (needsProcesses && !neededProcesses) {
            // Bekleyen uykuyu kesmek döngünün hemen örnek almasını ve
            // yeni aralıkla devam etmesini sağlar.
            pendingSleep?.cancel()
        }
    }

    private func sampleAndScheduleSleep() -> Task<Void, Never> {
        sample()
        let duration = interval
        let sleep = Task {
            _ = try? await Task.sleep(for: duration)
        }
        pendingSleep = sleep
        return sleep
    }

    private func sample() {
        let now = Date()
        if let value = cpuMonitor.read() {
            cpu = value
            cpuHistory.append(TimedSample(date: now, value: value.total))
        }
        if let value = perCoreMonitor.read() {
            perCore = value
        }
        if let value = memoryMonitor.read() {
            memory = value
            memoryHistory.append(TimedSample(date: now, value: value.usedFraction))
        }
        if let value = networkMonitor.read() {
            network = value
            if let throughput = value.throughput {
                downloadHistory.append(TimedSample(date: now, value: throughput.download))
                uploadHistory.append(TimedSample(date: now, value: throughput.upload))
            }
        }
        if let value = selfUsageMonitor.read() {
            selfUsage = value
        }
        startProcessReadIfNeeded()
    }

    private func startProcessReadIfNeeded() {
        guard needsProcesses, processRead == nil else { return }
        let reset = processResetPending
        processResetPending = false

        // Task ana aktörde oluşur; `await` ile tarama ProcessSampler actor'ünde
        // (ana thread dışında) yapılır ve sonuç yeniden ana aktöre döner.
        processRead = Task { [weak self, processSampler] in
            let snapshot = await processSampler.read(reset: reset)
            self?.finishProcessRead(snapshot)
        }
    }

    private func finishProcessRead(_ snapshot: ProcessSnapshot?) {
        processRead = nil
        // Okuma sürerken paneller kapandıysa sonucu atıyoruz.
        guard needsProcesses, let snapshot else { return }
        processes = snapshot
    }
}
