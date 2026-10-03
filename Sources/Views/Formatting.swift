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
}

extension MemoryPressure {
    var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Uyarı"
        case .critical: "Kritik"
        }
    }
}
