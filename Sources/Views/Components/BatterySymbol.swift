import Foundation

extension BatteryStatus {
    /// Menü bar ve panel için doluluk ve şarj durumuna göre değişen pil sembolü.
    var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
