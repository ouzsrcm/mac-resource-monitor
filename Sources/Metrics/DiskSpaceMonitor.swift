import Foundation

/// Başlangıç diskinin kapasitesi (byte).
struct DiskSpace: Sendable, Equatable {
    var total: UInt64
    /// Önemli kullanım için kullanılabilir alan (temizlenebilir önbellekler dahil);
    /// Finder'daki "kullanılabilir" değerine en yakın olanı.
    var available: UInt64

    var used: UInt64 { total > available ? total - available : 0 }

    var freeFraction: Double {
        guard total > 0 else { return 0 }
        return Double(available) / Double(total)
    }

    var usedFraction: Double { 1 - freeFraction }
}

/// Başlangıç diskinin boş/toplam alanını okur.
///
/// `volumeAvailableCapacityForImportantUsage` temizlenebilir alanı hesapladığı
/// için yavaştır (onlarca ms); ana thread dışında ve seyrek çağrılmalıdır.
struct DiskSpaceMonitor {
    mutating func read() -> DiskSpace? {
        // URL, okunan kaynak değerlerini kendi içinde önbelleğe alır; aynı
        // URL nesnesi tekrar kullanılırsa eski değer dönebilir. Bu yüzden
        // her okumada yeni bir URL oluşturuyoruz.
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]),
            let available = values.volumeAvailableCapacityForImportantUsage,
            let total = values.volumeTotalCapacity,
            total > 0
        else { return nil }

        let totalBytes = UInt64(total)
        return DiskSpace(total: totalBytes, available: min(UInt64(max(0, available)), totalBytes))
    }
}
