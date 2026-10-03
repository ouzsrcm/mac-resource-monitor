import Darwin

struct SelfUsage: Sendable, Equatable {
    /// 1.0 = bir çekirdeğin tamamı.
    var cpu: Double
    var memory: UInt64
}

/// MenuMonitor'ün kendi CPU ve bellek tüketimini `ProcessMonitor` ile aynı
/// hesapla ölçer. Tek bir sistem çağrısı olduğu için her örneklemede çalışabilir.
struct SelfUsageMonitor {
    private let pid = getpid()
    private var previousCPUTime: UInt64?
    private var previousTime: ContinuousClock.Instant?

    /// İlk çağrıda (fark hesaplanamadığı için) nil döner.
    mutating func read() -> SelfUsage? {
        guard let usage = ProcessResourceUsage(pid: pid) else { return nil }
        let now = ContinuousClock.now
        defer {
            previousCPUTime = usage.cpuTime
            previousTime = now
        }
        guard let previousCPUTime, let previousTime, usage.cpuTime >= previousCPUTime else { return nil }

        let elapsed = previousTime.duration(to: now).seconds
        guard elapsed > 0 else { return nil }
        return SelfUsage(
            cpu: ProcessResourceUsage.seconds(fromMachTime: usage.cpuTime - previousCPUTime) / elapsed,
            memory: usage.memory
        )
    }
}
