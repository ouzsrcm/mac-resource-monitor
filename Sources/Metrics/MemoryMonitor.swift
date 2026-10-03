import Darwin
import Foundation

/// Çekirdeğin bildirdiği bellek baskısı seviyesi.
/// Ham değerler `kern.memorystatus_vm_pressure_level` sysctl'inden gelir.
enum MemoryPressure: Int32, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

/// Anlık bellek durumu. Tüm boyutlar byte cinsindendir.
struct MemoryStats: Sendable, Equatable {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var pressure: MemoryPressure?
    var swapTotal: UInt64
    var swapUsed: UInt64

    /// Activity Monitor'deki "Kullanılan Bellek" ile aynı tanım.
    var used: UInt64 { app + wired + compressed }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }
}

/// Sistem bellek istatistiklerini Mach VM API'si ve sysctl ile okur.
/// Delta gerektirmez; her okuma o anın durumunu verir.
struct MemoryMonitor {
    /// Port referansı sızıntısını önlemek için host portunu bir kez alıyoruz
    /// (ayrıntı için `CPUMonitor.host` açıklamasına bakın).
    private let host: host_t = mach_host_self()

    /// `vm_statistics64` içindeki sayaçlar çekirdek sayfası cinsindendir
    /// (Apple Silicon'da 16 KB, Intel'de 4 KB).
    private let pageSize: UInt64

    private let physicalMemory = ProcessInfo.processInfo.physicalMemory

    init() {
        // Doğrudan `vm_kernel_page_size` C global'ini okumak Swift 6'da
        // "paylaşılan değiştirilebilir durum" hatası verir. `host_page_size`
        // libsyscall içinde tam olarak bu global'in değerini döndürür, bu
        // yüzden aynı sonucu concurrency açısından güvenli şekilde alıyoruz.
        // Çekirdek değeri `size`'a yazar; hata durumunda kern_return_t döner.
        var size: vm_size_t = 0
        let result = host_page_size(host, &size)
        pageSize = result == KERN_SUCCESS && size > 0 ? UInt64(size) : UInt64(getpagesize())
    }

    mutating func read() -> MemoryStats? {
        guard let vm = vmStatistics() else { return nil }

        // "App memory" = anonim (dosyaya bağlı olmayan) sayfalar eksi
        // sistemin gerektiğinde atabileceği "purgeable" sayfalar.
        let internalPages = UInt64(vm.internal_page_count)
        let purgeablePages = UInt64(vm.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0

        let swap = swapUsage()

        return MemoryStats(
            total: physicalMemory,
            app: appPages * pageSize,
            wired: UInt64(vm.wire_count) * pageSize,
            compressed: UInt64(vm.compressor_page_count) * pageSize,
            pressure: pressureLevel(),
            swapTotal: swap?.xsu_total ?? 0,
            swapUsed: swap?.xsu_used ?? 0
        )
    }

    /// Çekirdekten 64-bit VM istatistiklerini okur.
    private func vmStatistics() -> vm_statistics64? {
        var info = vm_statistics64()

        // HOST_VM_INFO64_COUNT makrosu Swift'e aktarılmadığı için struct
        // boyutunu `integer_t` (32-bit) eleman sayısı olarak elle hesaplıyoruz.
        // Çağrıdan sonra çekirdek gerçekte yazdığı eleman sayısını buraya koyar.
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )

        // withUnsafeMutablePointer: `info`'nun adresini yalnızca closure
        // süresince geçerli bir pointer olarak verir; dışarı taşınmamalı.
        //
        // withMemoryRebound: `host_statistics64` tipsiz bir `integer_t*`
        // (host_info64_t) beklediği için aynı belleği geçici olarak `integer_t`
        // dizisi gibi görüyoruz. `vm_statistics64` 8 byte hizalıdır; daha küçük
        // hizalamalı (4 byte) `integer_t` olarak görmek güvenlidir ve struct
        // boyutu 4'ün katıdır.
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPointer in
                // HOST_VM_INFO64: sanal bellek sayaçlarını (free, active,
                // wired, compressed, purgeable...) 64-bit sürümüyle iste.
                host_statistics64(host, HOST_VM_INFO64, rawPointer, &count)
            }
        }

        // Mach hata kodu döndürür; KERN_SUCCESS değilse `info` geçersizdir.
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    private func pressureLevel() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size

        // sysctlbyname(ad, çıktı tamponu, tampon boyutu (in-out), yeni değer, yeni değer boyutu)
        // Sadece okuduğumuz için yeni değer nil/0. `&level` Swift tarafından
        // çağrı süresince geçerli bir ham pointer'a çevrilir; çekirdek oraya
        // 32-bit seviye değerini, `size`'a da yazdığı byte sayısını yazar.
        // Başarıda 0, hatada -1 döner (ayrıntı errno'dadır).
        let result = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        guard result == 0, size == MemoryLayout<Int32>.size else { return nil }
        return MemoryPressure(rawValue: level)
    }

    private func swapUsage() -> xsw_usage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size

        // "vm.swapusage" bir `struct xsw_usage` döndürür
        // (xsu_total, xsu_avail, xsu_used: byte cinsinden UInt64).
        // `&usage` çağrı süresince struct'ın adresine ham pointer olarak
        // köprülenir ve çekirdek struct'ı doğrudan doldurur.
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage
    }
}
