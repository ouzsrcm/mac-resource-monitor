import Foundation

/// Sistemin termal durumunu okur. Değişiklikler ayrıca
/// `ProcessInfo.thermalStateDidChangeNotification` ile de bildirilir.
struct ThermalMonitor {
    mutating func read() -> ProcessInfo.ThermalState? {
        ProcessInfo.processInfo.thermalState
    }
}
