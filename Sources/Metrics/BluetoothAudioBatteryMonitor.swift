import Foundation

/// AirPods ve Beats pillerini `system_profiler` JSON çıktısından okur.
///
/// Bu Mac'te (`SPBluetoothDataType -json`) bağlı cihaz yok; kayıtlı cihazlar
/// `device_not_connected` altında. AirPods Pro orada da pil bildirir
/// (`device_batteryLevelLeft`, `device_batteryLevelRight`, `device_batteryLevelCase`,
/// değerler "%100" gibi metin). Bağlı olanlar `device_connected` anahtarında gelir.
/// Tek parça cihazlar için raporlayıcı `device_batteryLevelMain` de tanımlar.
/// Yüzde alanı olmayan kayıtlar (bu Mac'te iPhone, iPad, Watch, MX Master) atlanır.
///
/// Komut pahalıdır; `SamplingEngine` örnekleme döngüsünden ayrı, 60 saniyede
/// bir ve ana thread dışında çalıştırılır. 5 saniyede bitmezse süreç sonlandırılır.
struct BluetoothAudioBatteryMonitor: Sendable {
    static let interval: Duration = .seconds(60)
    static let timeout: Duration = .seconds(5)

    /// nil: komut başarısız oldu, önceki sonuç korunmalı.
    /// Boş dizi: komut bitti, pil yüzdesi bilinen cihaz yok.
    func read() async -> [DeviceBattery]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: Self.readOffMainThread())
            }
        }
    }

    private static func readOffMainThread() -> [DeviceBattery]? {
        guard let data = runProfiler() else { return nil }
        return parse(data)
    }

    private static func runProfiler() -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while process.isRunning && clock.now < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let killDeadline = clock.now.advanced(by: .seconds(1))
            while process.isRunning && clock.now < killDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    private static func parse(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [Any]
        else { return [] }

        var devices: [DeviceBattery] = []
        var indexByID: [String: Int] = [:]
        for case let section as [String: Any] in sections {
            // Aynı cihaz iki listede varsa bağlı kaydı tutulur.
            absorb(section["device_connected"], connected: true, into: &devices, indexByID: &indexByID)
            absorb(section["device_not_connected"], connected: false, into: &devices, indexByID: &indexByID)
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func absorb(
        _ value: Any?,
        connected: Bool,
        into devices: inout [DeviceBattery],
        indexByID: inout [String: Int]
    ) {
        guard let value else { return }
        for entry in deviceEntries(in: value) {
            guard let device = makeDevice(name: entry.name, properties: entry.properties, isConnected: connected) else {
                continue
            }
            if let index = indexByID[device.id] {
                if connected && !devices[index].isConnected {
                    devices[index] = device
                }
                continue
            }
            indexByID[device.id] = devices.count
            devices.append(device)
        }
    }

    private struct Entry {
        var name: String
        var properties: [String: Any]
    }

    /// Her iki liste de bir dizi: her öğe `{ "Cihaz Adı": { device_… } }`.
    /// Sözlük olarak gelirse onu da kabul ederiz.
    private static func deviceEntries(in value: Any) -> [Entry] {
        if let array = value as? [Any] {
            return array.flatMap { item -> [Entry] in
                guard let dictionary = item as? [String: Any] else { return [] }
                return entries(in: dictionary)
            }
        }
        if let dictionary = value as? [String: Any] {
            return entries(in: dictionary)
        }
        return []
    }

    private static func entries(in dictionary: [String: Any]) -> [Entry] {
        dictionary.compactMap { key, value in
            guard let properties = value as? [String: Any],
                  properties.keys.contains(where: { $0.hasPrefix("device_") })
            else { return nil }
            return Entry(name: key, properties: properties)
        }
    }

    private static func makeDevice(name: String, properties: [String: Any], isConnected: Bool) -> DeviceBattery? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let minorType = properties["device_minorType"] as? String

        var levels: [DeviceBattery.Level] = []
        func append(_ key: String, _ slot: DeviceBattery.Slot) {
            guard let raw = properties[key], let percent = BatteryLevelValue.percent(from: raw) else { return }
            levels.append(DeviceBattery.Level(slot: slot, percent: percent))
        }
        append("device_batteryLevelLeft", .left)
        append("device_batteryLevelRight", .right)
        append("device_batteryLevelCase", .caseBattery)
        // Sol/sağ/kutu varsa ana yüzde onların kopyası olabilir; yalnızca tek parça
        // cihazlarda (ör. AirPods Max) `device_batteryLevelMain` kullanılır.
        if levels.isEmpty {
            append("device_batteryLevelMain", .single)
        }
        guard !levels.isEmpty else { return nil }

        let address = properties["device_address"] as? String
        let serial = properties["device_serialNumber"] as? String
        let identity = nonEmpty(address) ?? nonEmpty(serial) ?? trimmed
        return DeviceBattery(
            id: "bt:\(identity)",
            name: trimmed,
            kind: DeviceBattery.kind(name: trimmed, category: minorType),
            levels: levels,
            isCharging: nil,
            isConnected: isConnected
        )
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
