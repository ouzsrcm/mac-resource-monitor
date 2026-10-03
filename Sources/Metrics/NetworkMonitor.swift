import Darwin

/// Bir ölçüm aralığındaki ortalama ağ hızı, byte/saniye cinsinden.
struct NetworkThroughput: Sendable, Equatable {
    var download: Double
    var upload: Double
}

struct NetworkStats: Sendable, Equatable {
    /// Son ölçümden bu yana ortalama hız; ilk ölçümde nil.
    var throughput: NetworkThroughput?
    /// Uygulama açıldığından (ilk ölçümden) beri toplam byte.
    var totalReceived: UInt64
    var totalSent: UInt64
    /// Arayüz adı → yerel IPv4 adresi (yalnızca açık ve çalışan arayüzler).
    var ipv4Addresses: [String: String]
}

/// Fiziksel ağ arayüzlerinin byte sayaçlarından hız ve toplam trafiği,
/// ayrıca arayüzlerin IPv4 adreslerini okur.
struct NetworkMonitor {
    private struct Counters {
        var received: UInt32
        var sent: UInt32
    }

    private struct Snapshot {
        var counters: [String: Counters] = [:]
        var ipv4Addresses: [String: String] = [:]
    }

    /// Loopback ve sanal arayüzler: VPN tünelleri (utun), AirDrop/AWDL (awdl),
    /// düşük gecikmeli WLAN (llw) ve köprüler (bridge). Bunlardaki trafik
    /// zaten fiziksel bir arayüzden de geçtiği için sayılırsa çift sayılır.
    private static let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge"]

    /// Arayüz adına göre önceki sayaçlar. Arayüzler arada eklenip
    /// kaldırılabildiği için toplamı değil, arayüz bazında farkı tutuyoruz.
    private var previousCounters: [String: Counters] = [:]
    private var previousTime: ContinuousClock.Instant?
    private var totalReceived: UInt64 = 0
    private var totalSent: UInt64 = 0

    mutating func read() -> NetworkStats? {
        guard let snapshot = takeSnapshot() else { return nil }
        let now = ContinuousClock.now
        defer {
            self.previousCounters = snapshot.counters
            self.previousTime = now
        }

        var throughput: NetworkThroughput?
        if let lastTime = previousTime {
            var received: UInt64 = 0
            var sent: UInt64 = 0
            for (name, counters) in snapshot.counters {
                guard let old = previousCounters[name] else { continue }
                // `if_data` sayaçları 32-bit'tir ve ~4 GB'da sıfıra sarar.
                // `&-` modüler çıkarma yaptığı için sarma sonrasında da fark doğru
                // çıkar (aralık içinde 4 GB'dan az trafik olduğu sürece).
                received += UInt64(counters.received &- old.received)
                sent += UInt64(counters.sent &- old.sent)
            }
            totalReceived += received
            totalSent += sent

            // Örnekleme aralığı panel durumuna göre değişebildiği (ve uyku/zamanlayıcı
            // gecikmeleri olabildiği) için gerçek geçen süreyi kullanıyoruz.
            let elapsed = lastTime.duration(to: now).seconds
            if elapsed > 0 {
                throughput = NetworkThroughput(
                    download: Double(received) / elapsed,
                    upload: Double(sent) / elapsed
                )
            }
        }

        return NetworkStats(
            throughput: throughput,
            totalReceived: totalReceived,
            totalSent: totalSent,
            ipv4Addresses: snapshot.ipv4Addresses
        )
    }

    private func takeSnapshot() -> Snapshot? {
        // getifaddrs, çekirdekten tüm arayüz adreslerini okuyup heap'te bağlı
        // bir `ifaddrs` listesi oluşturur ve başını `head`'e yazar.
        // Başarıda 0 döner. Liste bizim sorumluluğumuzdadır: işimiz bitince
        // `freeifaddrs` ile serbest bırakılmalı, aksi halde bellek sızar.
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(first) }

        var snapshot = Snapshot()
        let upAndRunning = UInt32(IFF_UP | IFF_RUNNING)

        // Listedeki pointer'lar yalnızca `freeifaddrs` çağrılana kadar geçerli;
        // bu yüzden ihtiyacımız olan değerleri döngü içinde kopyalıyoruz.
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee

            // Her arayüz için birden çok kayıt vardır (IPv4, IPv6, link...).
            // `ifa_addr` bazı kayıtlarda NULL olabilir.
            guard let address = entry.ifa_addr else { continue }

            // `ifa_name` NUL ile biten bir C dizgesi; Swift String'e kopyalıyoruz.
            let name = String(cString: entry.ifa_name)

            switch Int32(address.pointee.sa_family) {
            case AF_LINK:
                // Byte sayaçları yalnızca AF_LINK (veri bağlantı katmanı) kaydında bulunur.
                guard let data = entry.ifa_data,
                      !Self.excludedPrefixes.contains(where: name.hasPrefix)
                else { continue }

                // AF_LINK kayıtlarında `ifa_data` tipsiz (void*) bir pointer'dır ve
                // çekirdeğin doldurduğu `struct if_data`'yı gösterir. Bu belgelenmiş
                // bir sözleşme olduğu için belleği `if_data` olarak yorumlamak
                // güvenlidir; `.pointee` ile struct'ın bir kopyasını alıyoruz.
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                snapshot.counters[name] = Counters(received: stats.ifi_ibytes, sent: stats.ifi_obytes)

            case AF_INET:
                guard entry.ifa_flags & upAndRunning == upAndRunning,
                      snapshot.ipv4Addresses[name] == nil,
                      let text = Self.ipv4String(address)
                else { continue }
                snapshot.ipv4Addresses[name] = text

            default:
                continue
            }
        }

        return snapshot
    }

    private static func ipv4String(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        // `sockaddr` tüm adres ailelerinin ortak başlığıdır. `sa_family` AF_INET
        // olduğunda çekirdek bu konuma gerçekte bir `sockaddr_in` yazmıştır;
        // bu yüzden belleği geçici olarak `sockaddr_in` olarak görmek güvenlidir.
        // Yalnızca 4 byte'lık `sin_addr` alanını kopyalayıp closure'dan çıkıyoruz.
        var inAddr = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
            $0.pointee.sin_addr
        }

        // inet_ntop, ikili adresi "192.168.1.10" biçiminde NUL ile biten bir
        // C dizgesine çevirip verdiğimiz tampona yazar. INET_ADDRSTRLEN (16),
        // en uzun IPv4 dizgesi + NUL için yeterlidir. Başarısızlıkta NULL döner.
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        return buffer.withUnsafeMutableBufferPointer { output -> String? in
            guard let base = output.baseAddress,
                  inet_ntop(AF_INET, &inAddr, base, socklen_t(INET_ADDRSTRLEN)) != nil
            else { return nil }
            return String(cString: base)
        }
    }
}