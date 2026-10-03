import Foundation
import Observation

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

    /// Toplam CPU kullanımı (0.0–1.0).
    private(set) var cpuHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)
    /// Kullanılan bellek oranı (0.0–1.0).
    private(set) var memoryHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)
    /// Byte/saniye.
    private(set) var downloadHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)
    /// Byte/saniye.
    private(set) var uploadHistory = RingBuffer<TimedSample<Double>>(capacity: SamplingEngine.historyCapacity)

    let connection = ConnectionMonitor()

    /// Şu anda açık olan panel sayısı. Paneller `panelDidAppear()` /
    /// `panelDidDisappear()` ile günceller.
    private(set) var openPanelCount = 0

    var interval: Duration {
        openPanelCount > 0 ? Self.activeInterval : Self.idleInterval
    }

    @ObservationIgnored private var cpuMonitor = CPUMonitor()
    @ObservationIgnored private var perCoreMonitor = PerCoreCPUMonitor()
    @ObservationIgnored private var memoryMonitor = MemoryMonitor()
    @ObservationIgnored private var networkMonitor = NetworkMonitor()

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pendingSleep: Task<Void, Never>?

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
    }

    func panelDidAppear() {
        updateOpenPanelCount(openPanelCount + 1)
    }

    func panelDidDisappear() {
        updateOpenPanelCount(max(0, openPanelCount - 1))
    }

    private func updateOpenPanelCount(_ newValue: Int) {
        let oldInterval = interval
        openPanelCount = newValue
        if interval != oldInterval {
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
    }
}
