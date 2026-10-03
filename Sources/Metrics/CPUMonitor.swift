import Darwin

/// Sistem genelindeki toplam CPU kullanımını Mach çekirdek API'si ile ölçer.
///
/// Çekirdek, açılıştan beri her CPU durumunda (user, system, idle, nice)
/// geçen süreyi "tick" sayacı olarak tutar. Tek bir okuma anlamlı değildir;
/// iki okuma arasındaki farka bakarak o aralıktaki kullanım oranını buluruz.
struct CPUMonitor {
    /// `mach_host_self()` her çağrıldığında host portu için yeni bir "send right"
    /// (port referansı) döndürür ve bu referans serbest bırakılmazsa birikir.
    /// Bu yüzden portu bir kez alıp saklıyoruz.
    private let host: host_t = mach_host_self()

    /// Bir önceki ölçüm; fark hesabı için gerekli. İlk çağrıdan önce nil.
    private var previous: host_cpu_load_info?

    /// 0.0–1.0 arası toplam CPU kullanımı. İlk çağrıda (karşılaştırılacak
    /// önceki ölçüm olmadığı için) veya okuma başarısız olursa nil döner.
    mutating func read() -> Double? {
        guard let current = sample() else { return nil }
        defer { previous = current }
        guard let previous else { return nil }

        // `cpu_ticks` C tarafında `natural_t cpu_ticks[CPU_STATE_MAX]` dizisidir;
        // Swift'e sabit boyutlu bir tuple olarak gelir. İndeksler <mach/machine.h>
        // içindeki sabitlere karşılık gelir:
        //   .0 = CPU_STATE_USER, .1 = CPU_STATE_SYSTEM,
        //   .2 = CPU_STATE_IDLE, .3 = CPU_STATE_NICE
        //
        // Sayaçlar 32-bit işaretsizdir ve uzun süre açık kalan bir makinede
        // taşıp sıfırdan başlayabilir. Normal `-` bu durumda çökerdi; `&-`
        // modüler (sarmalayan) çıkarma yapar, böylece taşma sonrasında da
        // fark doğru çıkar.
        let user = current.cpu_ticks.0 &- previous.cpu_ticks.0
        let system = current.cpu_ticks.1 &- previous.cpu_ticks.1
        let idle = current.cpu_ticks.2 &- previous.cpu_ticks.2
        let nice = current.cpu_ticks.3 &- previous.cpu_ticks.3

        // Toplamayı Double'da yapıyoruz ki UInt32 toplamı da taşmasın.
        let busy = Double(user) + Double(system) + Double(nice)
        let total = busy + Double(idle)
        guard total > 0 else { return 0 }
        return busy / total
    }

    /// Çekirdekten anlık tick sayaçlarını okur.
    private func sample() -> host_cpu_load_info? {
        // Çekirdeğin dolduracağı boş C struct'ı.
        var info = host_cpu_load_info()

        // `host_statistics` tampon boyutunu struct'ın byte cinsinden değil,
        // `integer_t` (32-bit) cinsinden kaç eleman olduğu şeklinde ister.
        // C'deki HOST_CPU_LOAD_INFO_COUNT makrosu Swift'e aktarılmadığı için
        // aynı hesabı burada yapıyoruz. Bu değişken in-out'tur: çağrıdan sonra
        // çekirdek gerçekte kaç eleman yazdığını buraya geri yazar.
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )

        // `host_statistics` genel amaçlı bir API'dir: hangi istatistiği
        // istediğimize göre farklı struct'lar doldurur, bu yüzden parametre
        // olarak tipsiz bir `integer_t*` (host_info_t) bekler.
        //
        // withUnsafeMutablePointer: `info` değişkeninin bellekteki adresini
        // yalnızca bu closure süresince geçerli olan bir pointer olarak verir.
        // Pointer'ı closure dışına taşımak tanımsız davranıştır.
        //
        // withMemoryRebound: Aynı bellek bölgesini geçici olarak
        // `host_cpu_load_info` yerine `integer_t` dizisi olarak görmemizi sağlar.
        // Bu güvenlidir çünkü struct yalnızca `natural_t` (UInt32) alanlardan
        // oluşur ve `integer_t` ile aynı boyut/hizalamaya sahiptir.
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rawPointer in
                // HOST_CPU_LOAD_INFO: "bana tüm CPU'ların toplam tick
                // sayaçlarını ver" isteği. Çekirdek `rawPointer`'ın gösterdiği
                // belleğe yazar ve `count`'u günceller.
                host_statistics(host, HOST_CPU_LOAD_INFO, rawPointer, &count)
            }
        }

        // Mach çağrıları hata fırlatmaz, `kern_return_t` kodu döndürür.
        // KERN_SUCCESS dışındaki her değerde `info` güvenilir değildir.
        guard result == KERN_SUCCESS else { return nil }
        return info
    }
}
