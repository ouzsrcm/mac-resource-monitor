import Foundation

/// Bir Bluetooth aksesuarının veya kulaklığın pil durumu.
struct DeviceBattery: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case mouse
        case keyboard
        case trackpad
        case headphones
        case other
    }

    /// Pilin hangi parçada ölçüldüğü. Tek parçalı cihazlarda `single`.
    enum Slot: String, Sendable, Hashable, Identifiable {
        case single
        case left
        case right
        case caseBattery

        var id: String { rawValue }
    }

    struct Level: Sendable, Equatable, Identifiable {
        var slot: Slot
        /// 0–100.
        var percent: Int

        var id: Slot { slot }
    }

    var id: String
    var name: String
    var kind: Kind
    var levels: [Level]
    /// Bilinmiyorsa nil. HID aksesuarlarında registry'den gelir; kulaklıklarda çoğu zaman yoktur.
    var isCharging: Bool?
    /// HID servisi yalnızca cihaz bağlıyken vardır. Kulaklık pili bağlı değilken de gelebilir.
    var isConnected: Bool = true

    /// Ad veya IOKit `Accessory Category` / `device_minorType` değerinden tür tahmini.
    static func kind(name: String, category: String?) -> Kind {
        if let fromCategory = kind(matching: category) {
            return fromCategory
        }
        return kind(matching: name) ?? .other
    }

    private static func kind(matching text: String?) -> Kind? {
        guard let text else { return nil }
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if folded.contains("trackpad") { return .trackpad }
        if folded.contains("mouse") || folded.contains("trackball") { return .mouse }
        if folded.contains("keyboard") || folded.contains("klavye") { return .keyboard }
        if folded.contains("airpod") || folded.contains("headphone") || folded.contains("headset")
            || folded.contains("earbud") || folded.contains("beat") || folded.contains("kulaklik") {
            return .headphones
        }
        return nil
    }
}

/// "%85", "85%" veya düz sayı olan pil değerlerini 0–100 aralığına çevirir.
/// Biçim tanınmazsa nil döner.
enum BatteryLevelValue {
    static func percent(from value: Any) -> Int? {
        let number: Int?
        if let int = value as? Int {
            number = int
        } else if let double = value as? Double {
            number = Int(double.rounded())
        } else if let text = value as? String {
            number = percent(from: text)
        } else if let numeric = value as? NSNumber {
            // CFBoolean da NSNumber'a köprülenir; onu yüzde sayma.
            if CFGetTypeID(numeric) == CFBooleanGetTypeID() { return nil }
            number = Int(numeric.doubleValue.rounded())
        } else {
            number = nil
        }
        guard let number, (0...100).contains(number) else { return nil }
        return number
    }

    private static func percent(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        // Yalnızca rakam, boşluk ve yüzde işaretinden oluşan metinleri kabul et.
        let unexpected = trimmed.contains { character in
            !character.isNumber && !character.isWhitespace && character != "%"
        }
        guard !unexpected else { return nil }
        return value
    }
}
