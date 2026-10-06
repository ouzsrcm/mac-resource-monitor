import Foundation

/// AirPods ve Beats pillerini `system_profiler` JSON çıktısından okur.
///
/// Bu Mac'te (`SPBluetoothDataType -json`) bağlı cihaz yok; kayıtlı cihazlar
/// `device_not_connected` altında. Bağlı olanlar aynı biçimle `device_connected`
/// anahtarında gelir. Gözlenen pil alanları (değerler "%100" gibi metin):
/// `device_batteryLevelLeft`, `device_batteryLevelRight`, `device_batteryLevelCase`.
/// Tek parça cihazlar için raporlayıcı `device_batteryLevelMain` de tanımlar.
/// iPhone, iPad ve Watch bu okumaya dahil edilmez.
///
/// Komut pahalıdır; `SamplingEngine` örnekleme döngüsünden ayrı, 60 saniyede
/// bir ve ana thread dışında çalıştırılır. 5 saniyede bitmezse süreç sonlandırılır.
struct BluetoothAudioBatteryMonitor: Sendable {
    static let interval: Duration = .seconds(60)
    static let timeout: Duration = .seconds(5)

    /// nil: komut başarısız oldu, önceki sonuç korunmalı.
    /// Boş dizi: komut bitti, bağlı ve pili bilinen kulaklık yok.
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
        var seen = Set<String>()
        for case let section as [String: Any] in sections {
            guard let connected = section["device_connected"] else { continue }
            for entry in deviceEntries(in: connected) {
                guard let device = makeDevice(name: entry.name, properties: entry.properties),
                      seen.insert(device.id).inserted
                else { continue }
                devices.append(device)
            }
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private struct Entry {
        var name: String
        var properties: [String: Any]
    }

    /// `device_connected` bu Mac'te (bağlı cihaz olmadığından) yok. Kardeş anahtar
    /// `device_not_connected` bir dizi: her öğe `{ "Cihaz Adı": { device_… } }`.
    /// Bağlı liste aynı biçimde gelir; sözlük olarak gelirse onu da kabul ederiz.
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

    private static func makeDevice(name: String, properties: [String: Any]) -> DeviceBattery? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let minorType = properties["device_minorType"] as? String
        if isPhoneTabletOrWatch(name: trimmed, minorType: minorType) { return nil }

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
            isCharging: nil
        )
    }

    private static func isPhoneTabletOrWatch(name: String, minorType: String?) -> Bool {
        let blob = (name + " " + (minorType ?? ""))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if blob.contains("iphone") || blob.contains("ipad") { return true }
        let words = blob.split { !$0.isLetter }
        return words.contains("watch")
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
