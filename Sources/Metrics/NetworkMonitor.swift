import Darwin

/// Bir ölçüm aralığındaki ortalama ağ hızı, byte/saniye cinsinden.
struct NetworkThroughput: Sendable, Equatable {
    var download: Double
    var upload: Double
}

/// Fiziksel ağ arayüzlerinin byte sayaçlarından indirme/yükleme hızını hesaplar.
struct NetworkMonitor {
    private struct Counters {
        var received: UInt32
        var sent: UInt32
    }

    /// Loopback ve sanal arayüzler: VPN tünelleri (utun), AirDrop/AWDL (awdl),
    /// düşük gecikmeli WLAN (llw) ve köprüler (bridge). Bunlardaki trafik
    /// zaten fiziksel bir arayüzden de geçtiği için sayılırsa çift sayılır.
    private static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge"]

    /// Arayüz adına göre önceki sayaçlar. Arayüzler arada eklenip
    /// kaldırılabildiği için toplamı değil, arayüz bazında farkı tutuyoruz.
    private var previousCounters: [String: Counters] = [:]
    private var previousTime: ContinuousClock.Instant?

    /// Son ölçümden bu yana ortalama hız. İlk çağrıda nil döner.
    mutating func read() -> NetworkThroughput? {
        guard let current = sampleCounters() else { return nil }
        let now = ContinuousClock.now
        defer {
            self.previousCounters = current
            self.previousTime = now
        }
        guard let lastTime = previousTime else { return nil }

        // Örnekleme aralığı panel durumuna göre değişebildiği (ve uyku/zamanlayıcı
        // gecikmeleri olabildiği) için gerçek geçen süreyi kullanıyoruz.
        let elapsed = lastTime.duration(to: now).seconds
        guard elapsed > 0 else { return nil }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        for (name, counters) in current {
            guard let old = previousCounters[name] else { continue }
            // `if_data` sayaçları 32-bit'tir ve ~4 GB'da sıfıra sarar.
            // `&-` modüler çıkarma yaptığı için sarma sonrasında da fark doğru
            // çıkar (aralık içinde 4 GB'dan az trafik olduğu sürece).
            received += UInt64(counters.received &- old.received)
            sent += UInt64(counters.sent &- old.sent)
        }

        return NetworkThroughput(
            download: Double(received) / elapsed,
            upload: Double(sent) / elapsed
        )
    }

    private func sampleCounters() -> [String: Counters]? {
        // getifaddrs, çekirdekten tüm arayüz adreslerini okuyup heap'te bağlı
        // bir `ifaddrs` listesi oluşturur ve başını `head`'e yazar.
        // Başarıda 0 döner. Liste bizim sorumluluğumuzdadır: işimiz bitince
        // `freeifaddrs` ile serbest bırakılmalı, aksi halde bellek sızar.
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(first) }

        var result: [String: Counters] = [:]

        // Listedeki pointer'lar yalnızca `freeifaddrs` çağrılana kadar geçerli;
        // bu yüzden ihtiyacımız olan değerleri döngü içinde kopyalıyoruz.
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee

            // Her arayüz için birden çok kayıt vardır (IPv4, IPv6, link...).
            // Byte sayaçları yalnızca AF_LINK (veri bağlantı katmanı) kaydında
            // bulunur. `ifa_addr` bazı kayıtlarda NULL olabilir.
            guard let address = entry.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data
            else { continue }

            // `ifa_name` NUL ile biten bir C dizgesi; Swift String'e kopyalıyoruz.
            let name = String(cString: entry.ifa_name)
            guard !Self.excludedPrefixes.contains(where: name.hasPrefix) else { continue }

            // AF_LINK kayıtlarında `ifa_data` tipsiz (void*) bir pointer'dır ve
            // çekirdeğin doldurduğu `struct if_data`'yı gösterir. Bu belgelenmiş
            // bir sözleşme olduğu için belleği `if_data` olarak yorumlamak
            // güvenlidir; `.pointee` ile struct'ın bir kopyasını alıyoruz.
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = Counters(received: stats.ifi_ibytes, sent: stats.ifi_obytes)
        }

        return result
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
