import Darwin

enum CoreKind: Sendable {
    case performance
    case efficiency
    /// Intel gibi çekirdek türü ayrımı olmayan sistemler.
    case unified
}

struct CoreGroup: Sendable, Equatable {
    var kind: CoreKind
    /// Gruptaki her mantıksal çekirdeğin 0.0–1.0 arası kullanımı.
    var usages: [Double]
}

struct PerCoreCPUUsage: Sendable, Equatable {
    /// Apple Silicon'da önce P sonra E grubu; diğer sistemlerde tek grup.
    var groups: [CoreGroup]
}

/// Her mantıksal çekirdeğin kullanımını ayrı ayrı ölçer.
struct PerCoreCPUMonitor {
    private struct Ticks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    private struct GroupLayout {
        var kind: CoreKind
        var range: Range<Int>
    }

    /// Port referansı sızıntısını önlemek için host portunu bir kez alıyoruz
    /// (ayrıntı için `CPUMonitor.host` açıklamasına bakın).
    private let host: host_t = mach_host_self()
    private let layout: [GroupLayout]?
    private var previous: [Ticks]?

    init() {
        layout = Self.detectLayout()
    }

    /// Son ölçümden bu yana her çekirdeğin kullanımı. İlk çağrıda veya okuma
    /// başarısız olursa nil döner.
    mutating func read() -> PerCoreCPUUsage? {
        guard let current = sample() else { return nil }
        defer { previous = current }
        // Çekirdek sayısı değiştiyse (pratikte olmaz) eski ölçüm karşılaştırılamaz.
        guard let previous, previous.count == current.count else { return nil }

        let usages = zip(current, previous).map { now, old in
            // Sayaçlar 32-bit ve sarabilir; `&-` sarma sonrasında da doğru farkı verir.
            let user = Double(now.user &- old.user) + Double(now.nice &- old.nice)
            let system = Double(now.system &- old.system)
            let idle = Double(now.idle &- old.idle)
            let total = user + system + idle
            return total > 0 ? (user + system) / total : 0
        }

        return PerCoreCPUUsage(groups: groups(for: usages))
    }

    private func groups(for usages: [Double]) -> [CoreGroup] {
        guard let layout, layout.reduce(0, { $0 + $1.range.count }) == usages.count else {
            return [CoreGroup(kind: .unified, usages: usages)]
        }
        return layout.map { CoreGroup(kind: $0.kind, usages: Array(usages[$0.range])) }
    }

    /// Çekirdek türlerinin indeks aralıklarını sysctl ile bir kez belirler.
    ///
    /// VARSAYIM: Apple Silicon'da çekirdek, verimlilik (E) çekirdeklerini düşük
    /// indekslere, performans (P) çekirdeklerini onlardan sonra numaralandırır
    /// (ör. M1: 0–3 E, 4–7 P). Apple bu sıralamayı belgelemez; sysctl yalnızca
    /// her türden kaç çekirdek olduğunu söyler. İleride sıralama değişirse
    /// P/E etiketleri yanlış gruba düşebilir.
    private static func detectLayout() -> [GroupLayout]? {
        // hw.nperflevels: performans seviyesi sayısı. Apple Silicon'da 2
        // (perflevel0 = P, perflevel1 = E); Intel'de bu anahtar yoktur.
        guard sysctlInt32("hw.nperflevels") == 2,
              let performance = sysctlInt32("hw.perflevel0.logicalcpu"),
              let efficiency = sysctlInt32("hw.perflevel1.logicalcpu"),
              performance > 0, efficiency > 0
        else { return nil }

        let eCount = Int(efficiency)
        let pCount = Int(performance)
        // Gösterimde P önce gelir, ama indeks aralıkları varsayıma göre E önce.
        return [
            GroupLayout(kind: .performance, range: eCount..<(eCount + pCount)),
            GroupLayout(kind: .efficiency, range: 0..<eCount),
        ]
    }

    private static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        // sysctlbyname, anahtarın değerini `&value` ile köprülenen ham pointer'a
        // yazar; anahtar yoksa (ör. Intel'de hw.nperflevels) -1 döner.
        guard sysctlbyname(name, &value, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size
        else { return nil }
        return value
    }

    /// Tüm çekirdeklerin anlık tick sayaçlarını okur.
    private func sample() -> [Ticks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        // PROCESSOR_CPU_LOAD_INFO: her mantıksal çekirdek için
        // CPU_STATE_MAX (4) adet `integer_t` tick sayacı iste. Çekirdek sonucu
        // bizim tamponumuza yazmaz; Mach mesajı ile görevimizin adres alanında
        // YENİ bir bellek bölgesi ayırır ve adresini `info`'ya, toplam
        // `integer_t` sayısını `infoCount`'a yazar.
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }

        // ÖNEMLİ: Bu bölge malloc ile ayrılmadığı için `free` ile değil,
        // `vm_deallocate` ile görevimizin adres alanından kaldırılmalıdır.
        // Unutulursa her örneklemede (saniyede bir) birkaç yüz byte'lık sayfa
        // sızar ve uygulamanın belleği sürekli büyür. `defer`, aşağıdaki
        // kopyalama hangi yoldan biterse bitsin serbest bırakmayı garanti eder.
        // Boyut byte cinsindendir: eleman sayısı × `integer_t` boyutu.
        // `mach_task_self_`, kendi görevimizin portudur (C'deki
        // `mach_task_self()` makrosu Swift'e aktarılmaz); her çağrıda yeni
        // referans üretmediği için saklamaya gerek yoktur.
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let stateCount = Int(CPU_STATE_MAX)
        guard Int(infoCount) >= Int(cpuCount) * stateCount else { return nil }

        // `info`, `infoCount` elemanlı düz bir `integer_t` dizisini gösterir;
        // i. çekirdeğin sayaçları [i * 4 ..< i * 4 + 4] aralığındadır ve sıra
        // CPU_STATE_USER, SYSTEM, IDLE, NICE'tır. Pointer yalnızca
        // `vm_deallocate`'e kadar geçerli olduğu için değerleri Swift dizisine
        // kopyalıyoruz. Sayaçlar C'de işaretsiz tutulur ama `integer_t`
        // (Int32) olarak gelir; `bitPattern` ile bitleri değiştirmeden UInt32'ye
        // çeviriyoruz.
        return (0..<Int(cpuCount)).map { cpu in
            let base = cpu * stateCount
            return Ticks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }
}
