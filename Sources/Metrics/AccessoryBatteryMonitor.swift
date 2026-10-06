import Foundation
import IOKit

/// Magic Mouse, Magic Keyboard ve Magic Trackpad gibi HID aksesuarlarının
/// pilini IORegistry'den okur.
///
/// Bu Mac'te `ioreg -r -l -k BatteryPercent` boş: bağlı, pil bildiren aksesuar yok.
/// Kayıtlı tek `AppleDeviceManagementHIDEventService` dahili klavye/trackpad
/// (`Transport` = "SPI", `Built-In` = Yes) ve `BatteryPercent` taşımıyor.
/// Sürücü kişilikleri (`AppleTopCaseDriverV2`) Bluetooth aksesuarlarını aynı
/// sınıfa bağlıyor. Okunan anahtarlar: `Product`, `BatteryPercent`,
/// `SerialNumber`, `Accessory Category`, `Transport`, `Built-In`. Şarj için
/// varsa `BatteryStatusFlags`, yoksa benzer alan `BatteryState` (0…2).
struct AccessoryBatteryMonitor {
    mutating func read() -> [DeviceBattery] {
        // IOServiceMatching sözlüğü IOServiceGetMatchingServices tarafından
        // tüketilir; çağıran ayrıca serbest bırakmaz.
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleDeviceManagementHIDEventService"),
            &iterator
        )
        guard status == KERN_SUCCESS else { return [] }
        // Yineleyici +1 referansla döner; dolaşma bitince bırakılır.
        defer { IOObjectRelease(iterator) }

        var devices: [DeviceBattery] = []
        var seen = Set<String>()
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            let device = Self.device(from: service)
            // IOIteratorNext her servis için +1 referans verir.
            IOObjectRelease(service)
            guard let device, seen.insert(device.id).inserted else { continue }
            devices.append(device)
        }
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func device(from service: io_registry_entry_t) -> DeviceBattery? {
        // Dahili klavye/trackpad aynı sınıfta görünür; pili yoktur ve Bluetooth değildir.
        if boolProperty(service, "Built-In") == true { return nil }
        if let transport = stringProperty(service, "Transport")?.lowercased(),
           !transport.contains("bluetooth") {
            return nil
        }
        guard let percent = intProperty(service, "BatteryPercent"),
              (0...100).contains(percent)
        else { return nil }

        let name = stringProperty(service, "Product")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "Bluetooth cihazı")
        let serial = nonEmpty(stringProperty(service, "SerialNumber"))
        let address = addressProperty(service)
        // Aynı aksesuar klavye ve tüketici kontrolü gibi birden fazla serviste
        // görünebilir; seri veya adres ile tek kayıt tutulur.
        let identity = serial ?? address ?? name
        let category = stringProperty(service, "Accessory Category")

        return DeviceBattery(
            id: "hid:\(identity)",
            name: name,
            kind: DeviceBattery.kind(name: name, category: category),
            levels: [DeviceBattery.Level(slot: .single, percent: percent)],
            isCharging: charging(service)
        )
    }

    /// `BatteryStatusFlags` düşük biti şarjı belirtir. Bu Mac'te özellik şu an
    /// hiçbir serviste yok. Benzer alan `BatteryState`: 0 deşarj, 1 şarj, 2 dolu.
    private static func charging(_ service: io_registry_entry_t) -> Bool? {
        if let flags = intProperty(service, "BatteryStatusFlags") {
            return (flags & 0x1) != 0
        }
        switch intProperty(service, "BatteryState") {
        case 0: return false
        case 1, 2: return true
        default: return nil
        }
    }

    private static func addressProperty(_ service: io_registry_entry_t) -> String? {
        for key in ["DeviceAddress", "BD_ADDR"] {
            guard let raw = copyProperty(service, key) else { continue }
            if let text = raw as? String, let cleaned = nonEmpty(text) { return cleaned }
            if let data = raw as? Data, !data.isEmpty {
                return data.map { String(format: "%02X", $0) }.joined(separator: ":")
            }
        }
        return nil
    }

    /// IORegistryEntryCreateCFProperty "Create" kuralına uyar: dönen nesne +1
    /// referanslıdır. `takeRetainedValue` sahipliği ARC'ye bırakır.
    private static func copyProperty(_ service: io_registry_entry_t, _ key: String) -> CFTypeRef? {
        guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return property.takeRetainedValue()
    }

    private static func stringProperty(_ service: io_registry_entry_t, _ key: String) -> String? {
        copyProperty(service, key) as? String
    }

    private static func intProperty(_ service: io_registry_entry_t, _ key: String) -> Int? {
        guard let raw = copyProperty(service, key) else { return nil }
        if CFGetTypeID(raw) == CFBooleanGetTypeID() { return nil }
        guard CFGetTypeID(raw) == CFNumberGetTypeID(), let number = raw as? NSNumber else { return nil }
        return number.intValue
    }

    private static func boolProperty(_ service: io_registry_entry_t, _ key: String) -> Bool? {
        guard let raw = copyProperty(service, key), CFGetTypeID(raw) == CFBooleanGetTypeID() else { return nil }
        return raw as? Bool
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
