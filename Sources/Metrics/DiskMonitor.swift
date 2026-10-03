import Foundation
import IOKit

/// Byte/saniye cinsinden disk okuma/yazma hızı.
struct DiskThroughput: Sendable, Equatable {
    var read: Double
    var write: Double
}

/// Blok depolama sürücülerinin IOKit istatistiklerinden okuma/yazma hızını hesaplar.
struct DiskMonitor {
    private struct Counters {
        var read: UInt64
        var write: UInt64
    }

    /// Kayıt (registry) kimliği → önceki sayaçlar. Harici diskler takılıp
    /// çıkarılabildiği için toplamı değil, sürücü bazında farkı tutuyoruz.
    private var previousCounters: [UInt64: Counters] = [:]
    private var previousTime: ContinuousClock.Instant?

    /// Son ölçümden bu yana ortalama hız. İlk çağrıda nil döner.
    mutating func read() -> DiskThroughput? {
        guard let current = Self.sampleCounters() else { return nil }
        let now = ContinuousClock.now
        defer {
            previousCounters = current
            previousTime = now
        }
        guard let lastTime = previousTime else { return nil }
        let elapsed = lastTime.duration(to: now).seconds
        guard elapsed > 0 else { return nil }

        var read: UInt64 = 0
        var write: UInt64 = 0
        for (id, counters) in current {
            // Sayaçlar 64-bit'tir ve pratikte sarmaz; azalmışsa sürücü
            // yeniden başlatılmıştır, o aralığı atlıyoruz.
            guard let old = previousCounters[id],
                  counters.read >= old.read, counters.write >= old.write
            else { continue }
            read += counters.read - old.read
            write += counters.write - old.write
        }
        return DiskThroughput(read: Double(read) / elapsed, write: Double(write) / elapsed)
    }

    private static func sampleCounters() -> [UInt64: Counters]? {
        var iterator: io_iterator_t = 0
        // IOServiceMatching, "IOBlockStorageDriver sınıfındaki servisler" için
        // +1 referanslı bir eşleme sözlüğü oluşturur; IOServiceGetMatchingServices
        // bu referansı tüketir. İkisi de CF sahiplik açıklamalarıyla Swift'e
        // aktarıldığı için ARC bunu doğru yönetir, elle CFRelease gerekmez.
        // Sonuç, eşleşen servisleri gezmek için bir iterator'dır.
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return nil }
        // io_iterator_t ve io_object_t aslında çekirdekteki nesnelere işaret
        // eden mach port'larıdır; ARC bunları tanımaz. Her biri için
        // IOObjectRelease çağrılmazsa port referansları her örneklemede
        // birikir (sızıntı). `defer` her çıkış yolunda serbest bırakmayı garanti eder.
        defer { IOObjectRelease(iterator) }

        var counters: [UInt64: Counters] = [:]
        while true {
            // IOIteratorNext +1 referanslı bir servis döndürür; liste bitince 0.
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            // Kayıt kimliği, servis yeniden listelense de aynı kalan 64-bit bir anahtardır.
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { continue }

            // IORegistryEntryCreateCFProperty "Create" kuralına uyar: +1 referanslı
            // bir CF nesnesi döner. `takeRetainedValue` bu referansı ARC'ye devreder,
            // böylece nesne Swift tarafında bittiğinde otomatik serbest kalır.
            guard let property = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
                let statistics = property as? [String: Any]
            else { continue }

            counters[entryID] = Counters(
                read: (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                write: (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            )
        }
        return counters
    }
}
