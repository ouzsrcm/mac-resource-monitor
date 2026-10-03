/// Pahalı okumaları (süreç taraması, disk kapasitesi) ana thread dışında
/// çalıştırır. Actor, varsayılan (genel) yürütücüde çalıştığı için arayüzü
/// bloklamaz; okuma zamanlaması yine `SamplingEngine` döngüsünden gelir.
actor BackgroundSampler {
    private var processMonitor = ProcessMonitor()
    private var diskSpaceMonitor = DiskSpaceMonitor()

    /// `reset` true ise önceki örnekler atılır; uzun bir aradan sonra ilk
    /// CPU farkının dakikalarca süren bir ortalama olmasını önler.
    func readProcesses(reset: Bool) -> ProcessSnapshot? {
        if reset {
            processMonitor = ProcessMonitor()
        }
        return processMonitor.read()
    }

    func readDiskSpace() -> DiskSpace? {
        diskSpaceMonitor.read()
    }

    /// Panellerden bağımsız, tek seferlik ölçüm: CPU farkı için iki örnek
    /// arasında kısa bir süre bekler. Bekleme sırasında actor diğer
    /// isteklere açıktır; yalnızca yerel bir okuyucu kullanıldığı için
    /// paylaşılan durum bozulmaz.
    func topCPUProcess(window: Duration = .seconds(1)) async -> ProcessUsage? {
        var monitor = ProcessMonitor()
        _ = monitor.read()
        try? await Task.sleep(for: window)
        return monitor.read()?.topCPU.first
    }
}
