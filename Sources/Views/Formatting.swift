import Foundation

enum Format {
    /// Menü bar için tam sayı yüzde, ör. "23%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Paneller için bir ondalıklı yüzde, ör. "23.4%".
    static func precisePercent(_ fraction: Double) -> String {
        String(format: "%.1f%%", fraction * 100)
    }

    /// Bellek boyutları (1024 tabanlı).
    static func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }

    /// Aktarılan veri miktarı (1000 tabanlı, ağ hızlarıyla tutarlı).
    static func dataSize(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    /// Byte/saniye değerini KB/s, MB/s, GB/s olarak otomatik birimle biçimlendirir.
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = bytesPerSecond.isFinite ? max(0, bytesPerSecond) : 0
        let formatted = Int64(value.rounded()).formatted(
            .byteCount(style: .file, allowedUnits: [.kb, .mb, .gb], spellsOutZero: false)
        )
        return formatted + "/s"
    }

    /// Panel altındaki kendi tüketim satırı, ör. "MenuMonitor: %0,4 CPU · 31 MB".
    static func selfUsage(_ usage: SelfUsage) -> String {
        let cpu = (usage.cpu * 100).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "MenuMonitor: %\(cpu) CPU · \(bytes(usage.memory))")
    }

    /// Dakika cinsinden süre, ör. "3 sa 12 dk" veya "45 dk".
    static func minutes(_ total: Int) -> String {
        let hours = total / 60
        let minutes = total % 60
        return hours > 0
            ? String(localized: "\(hours) sa \(minutes) dk")
            : String(localized: "\(minutes) dk")
    }

    /// Ayarlardaki aralık seçenekleri, ör. "0,5 sn" (yerel ondalık ayırıcıyla).
    static func seconds(_ value: Double) -> String {
        String(localized: "\(value.formatted()) sn")
    }
}

extension MemoryPressure {
    var title: String {
        switch self {
        case .normal: String(localized: "Normal")
        case .warning: String(localized: "Uyarı")
        case .critical: String(localized: "Kritik")
        }
    }
}

extension ProcessInfo.ThermalState {
    var title: String {
        switch self {
        case .nominal: String(localized: "Normal")
        case .fair: String(localized: "Ilık")
        case .serious: String(localized: "Sıcak")
        case .critical: String(localized: "Kritik")
        @unknown default: String(localized: "Bilinmiyor")
        }
    }
}
