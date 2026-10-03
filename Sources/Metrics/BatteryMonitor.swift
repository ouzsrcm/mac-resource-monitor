import Foundation
import IOKit.ps

struct BatteryStatus: Sendable, Equatable {
    /// 0.0–1.0
    var level: Double
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Pil kullanılırken tahmini kalan süre (dakika); sistem henüz
    /// hesaplayamadıysa nil.
    var minutesToEmpty: Int?
    /// Şarj olurken tam dolmasına kalan süre (dakika).
    var minutesToFull: Int?
}

/// Dahili pilin durumunu IOKit Power Sources API'si ile okur.
/// Pili olmayan Mac'lerde nil döner.
struct BatteryMonitor {
    mutating func read() -> BatteryStatus? {
        // IOPSCopyPowerSourcesInfo ve IOPSCopyPowerSourcesList "Copy" kuralına
        // uyar: +1 referanslı nesne döner. `takeRetainedValue` sahipliği ARC'ye
        // devreder; elle CFRelease gerekmez. `blob` tüm güç kaynaklarının
        // anlık görüntüsüdür ve aşağıdaki açıklamalar ona bağlıdır.
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            // IOPSGetPowerSourceDescription "Get" kuralına uyar: sahiplik bizde
            // değildir ve sözlük yalnızca `blob` yaşadığı sürece geçerlidir.
            // Bu yüzden `takeUnretainedValue` kullanıp hemen Swift sözlüğüne
            // köprülüyoruz (değerler kopyalanır).
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                description[kIOPSIsPresentKey] as? Bool ?? true,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            // Süreler dakika cinsindendir; sistem hesaplıyorsa -1 döner.
            let toEmpty = description[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = description[kIOPSTimeToFullChargeKey] as? Int ?? -1

            return BatteryStatus(
                level: min(1, Double(current) / Double(max)),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesToEmpty: !isPluggedIn && toEmpty > 0 ? toEmpty : nil,
                minutesToFull: isCharging && toFull > 0 ? toFull : nil
            )
        }
        return nil
    }
}
