/// `ProcessMonitor`'ü ana thread dışında çalıştırır. Actor, varsayılan
/// (genel) yürütücüde çalıştığı için yüzlerce süreçlik tarama arayüzü bloklamaz;
/// okuma zamanlaması yine `SamplingEngine` döngüsünden gelir.
actor ProcessSampler {
    private var monitor = ProcessMonitor()

    /// `reset` true ise önceki örnekler atılır; uzun bir aradan sonra ilk
    /// CPU farkının dakikalarca süren bir ortalama olmasını önler.
    func read(reset: Bool) -> ProcessSnapshot? {
        if reset {
            monitor = ProcessMonitor()
        }
        return monitor.read()
    }
}
