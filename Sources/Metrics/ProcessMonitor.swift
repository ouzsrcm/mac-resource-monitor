import Darwin

/// Tek bir sürecin bir ölçüm aralığındaki kaynak kullanımı.
struct ProcessUsage: Sendable, Equatable, Identifiable {
    let pid: pid_t
    let name: String
    /// 1.0 = bir çekirdeğin tamamı. Çok çekirdekli süreçlerde 1.0'ı aşabilir.
    let cpu: Double
    /// Fiziksel bellek ayak izi (byte).
    let memory: UInt64

    var id: pid_t { pid }
}

struct ProcessSnapshot: Sendable, Equatable {
    /// İlk ölçümde (karşılaştırılacak önceki örnek yokken) boştur.
    var topCPU: [ProcessUsage]
    var topMemory: [ProcessUsage]
}

/// Tüm süreçleri libproc ile tarayıp en çok CPU ve bellek kullananları bulur.
///
/// Yüzlerce süreç için sistem çağrısı yaptığından pahalıdır; ana thread
/// dışında ve yalnızca ilgili paneller açıkken çalıştırılmalıdır.
struct ProcessMonitor {
    static let topCount = 5

    private struct Sample {
        var cpuTime: UInt64
        var startTime: UInt64
    }

    /// PID → önceki örnek. Her okumada yalnızca o an var olan PID'lerle
    /// yeniden kurulur; böylece kapanan süreçler sözlükte birikmez.
    private var previous: [pid_t: Sample] = [:]
    private var previousTime: ContinuousClock.Instant?

    mutating func read() -> ProcessSnapshot? {
        guard let pids = Self.allPIDs() else { return nil }
        let now = ContinuousClock.now
        let elapsed = previousTime.map { $0.duration(to: now).seconds }

        var current: [pid_t: Sample] = [:]
        current.reserveCapacity(pids.count)
        var cpuUsages: [(pid: pid_t, cpu: Double, memory: UInt64)] = []
        var memoryUsages: [(pid: pid_t, cpu: Double, memory: UInt64)] = []
        cpuUsages.reserveCapacity(pids.count)
        memoryUsages.reserveCapacity(pids.count)

        // PID 0 çekirdeğin kendisidir (kernel_task); okunamaz, atlıyoruz.
        for pid in pids where pid > 0 {
            // Erişim izni olmayan veya o arada kapanmış süreçlerde nil döner.
            guard let usage = ProcessResourceUsage(pid: pid) else { continue }
            current[pid] = Sample(cpuTime: usage.cpuTime, startTime: usage.startTime)

            var cpu = 0.0
            // Başlangıç zamanı farklıysa PID başka bir sürece yeniden atanmıştır;
            // eski örnekle karşılaştırmak anlamsız olur.
            if let elapsed, elapsed > 0,
               let old = previous[pid],
               old.startTime == usage.startTime,
               usage.cpuTime >= old.cpuTime {
                cpu = ProcessResourceUsage.seconds(fromMachTime: usage.cpuTime - old.cpuTime) / elapsed
                cpuUsages.append((pid, cpu, usage.memory))
            }
            memoryUsages.append((pid, cpu, usage.memory))
        }

        previous = current
        previousTime = now

        cpuUsages.sort { $0.cpu > $1.cpu }
        memoryUsages.sort { $0.memory > $1.memory }
        return ProcessSnapshot(
            topCPU: Self.named(cpuUsages),
            topMemory: Self.named(memoryUsages)
        )
    }

    /// Sıralı listenin başından, adı okunabilen ilk `topCount` süreci alır.
    /// İsimleri yalnızca burada okuyoruz ki yüzlerce süreç için boşuna
    /// sistem çağrısı yapılmasın.
    private static func named(_ sorted: [(pid: pid_t, cpu: Double, memory: UInt64)]) -> [ProcessUsage] {
        var result: [ProcessUsage] = []
        for entry in sorted {
            guard result.count < topCount else { break }
            guard let name = name(of: entry.pid) else { continue }
            result.append(ProcessUsage(pid: entry.pid, name: name, cpu: entry.cpu, memory: entry.memory))
        }
        return result
    }

    private static func allPIDs() -> [pid_t]? {
        // Tampon olmadan çağrıldığında proc_listallpids o anki süreç sayısını
        // (tahmini olarak) döndürür. İki çağrı arasında yeni süreçler
        // açılabileceği için tamponu biraz büyük ayırıyoruz.
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return nil }

        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        // proc_listallpids, verdiğimiz tampona (boyutu byte cinsinden) PID'leri
        // `int` dizisi olarak yazar ve kaç PID yazdığını döndürür; hata
        // durumunda -1 döner. Pointer yalnızca closure süresince geçerlidir.
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return nil }
        return Array(pids.prefix(Int(count)))
    }

    private static func name(of pid: pid_t) -> String? {
        // proc_name, sürecin kısa adını NUL ile biten bir C dizgesi olarak
        // tampona yazar ve uzunluğunu döndürür; süreç yoksa veya erişim
        // izni yoksa 0 döner. Tamponu NUL ile doldurduğumuz ve boyutunu bir
        // eksik verdiğimiz için dizge her durumda NUL ile sonlanır.
        var buffer = [CChar](repeating: 0, count: 256)
        let length = buffer.withUnsafeMutableBufferPointer { output in
            proc_name(pid, output.baseAddress, UInt32(output.count - 1))
        }
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}

/// `proc_pid_rusage` ile tek bir süreçten okunan ham değerler.
/// Hem `ProcessMonitor` hem `SelfUsageMonitor` bu okumayı kullanır.
struct ProcessResourceUsage {
    /// Kullanıcı + sistem modunda harcanan toplam CPU süresi (mach absolute time birimi).
    let cpuTime: UInt64
    /// Fiziksel bellek ayak izi (byte); Activity Monitor'deki "Bellek" sütununa en yakın değer.
    let memory: UInt64
    /// Sürecin başlangıç anı (mach absolute time); PID yeniden kullanımını ayırt etmek için.
    let startTime: UInt64

    init?(pid: pid_t) {
        var info = rusage_info_v2()
        // proc_pid_rusage, istenen sürümdeki (`RUSAGE_INFO_V2`) struct'ı
        // verdiğimiz belleğe yazar. C imzası `rusage_info_t *buffer` şeklindedir;
        // `rusage_info_t` aslında `void *` olduğu için Swift bunu
        // `UnsafeMutablePointer<rusage_info_t?>` olarak görür. Gerçekte çekirdek
        // bu adrese doğrudan `struct rusage_info_v2` yazar; bu yüzden
        // `info`'nun adresini geçici olarak o tipe yeniden bağlıyoruz.
        // Pointer yalnızca closure süresince geçerlidir.
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rawPointer in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, rawPointer)
            }
        }
        // Başarıda 0 döner. Başka kullanıcıya ait (izin yok, EPERM) veya
        // listeyi aldığımızdan beri kapanmış (ESRCH) süreçlerde -1 döner.
        guard result == 0 else { return nil }

        cpuTime = info.ri_user_time &+ info.ri_system_time
        memory = info.ri_phys_footprint
        startTime = info.ri_proc_start_abstime
    }

    /// Mach absolute time birimindeki bir süreyi saniyeye çevirir.
    ///
    /// DİKKAT: `ri_user_time` / `ri_system_time` adlarına ve belgelere rağmen
    /// nanosaniye değil, mach absolute time "tick" birimindedir. Intel'de
    /// tick = 1 ns olduğu için fark edilmez; Apple Silicon'da ise tick
    /// 125/3 ns'dir (24 MHz zamanlayıcı) ve dönüştürülmezse CPU kullanımı
    /// ~41 kat düşük görünür. Oran `mach_timebase_info` ile alınır:
    /// nanosaniye = tick × numer / denom.
    static func seconds(fromMachTime ticks: UInt64) -> Double {
        Double(ticks) * nanosecondsPerTick / 1e9
    }

    private static let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        // mach_timebase_info, `timebase`'e numer/denom oranını yazar.
        // Değer açılış boyunca sabit olduğu için bir kez okuyoruz.
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return 1 }
        return Double(timebase.numer) / Double(timebase.denom)
    }()
}
