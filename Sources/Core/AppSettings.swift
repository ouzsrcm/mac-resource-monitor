import Foundation

/// Disk menü bar öğesinde gösterilecek bilgi.
enum DiskLabelMode: String, CaseIterable, Sendable {
    case freeSpace
    case throughput

    var title: String {
        switch self {
        case .freeSpace: "Boş alan"
        case .throughput: "Okuma/yazma hızı"
        }
    }
}

/// Kalıcı ayarların (`UserDefaults` / `@AppStorage`) anahtarları ve varsayılanları.
enum AppSettings {
    enum Key {
        static let showCPU = "showCPU"
        static let showRAM = "showRAM"
        static let showNetwork = "showNetwork"
        static let showDisk = "showDisk"
        static let showSystem = "showSystem"
        static let idleInterval = "idleIntervalSeconds"
        static let activeInterval = "activeIntervalSeconds"
        static let diskLabelMode = "diskLabelMode"

        static func alertEnabled(_ kind: AlertKind) -> String {
            "alert.\(kind.rawValue)"
        }
    }

    static let idleIntervalOptions: [Double] = [1, 2, 3, 5]
    static let activeIntervalOptions: [Double] = [0.5, 1, 2]
    static let defaultIdleInterval: Double = 3
    static let defaultActiveInterval: Double = 1

    /// `UserDefaults` okumalarının (`@AppStorage` dışında) da doğru
    /// varsayılanları görmesi için uygulama açılışında çağrılır.
    static func registerDefaults() {
        var defaults: [String: Any] = [
            Key.idleInterval: defaultIdleInterval,
            Key.activeInterval: defaultActiveInterval,
            Key.diskLabelMode: DiskLabelMode.freeSpace.rawValue,
        ]
        for kind in AlertKind.allCases {
            defaults[Key.alertEnabled(kind)] = true
        }
        UserDefaults.standard.register(defaults: defaults)
    }

    /// Hiçbir panel açık değilken örnekleme aralığı.
    static var idleInterval: Duration {
        interval(forKey: Key.idleInterval, allowed: idleIntervalOptions, fallback: defaultIdleInterval)
    }

    /// En az bir panel açıkken örnekleme aralığı.
    static var activeInterval: Duration {
        interval(forKey: Key.activeInterval, allowed: activeIntervalOptions, fallback: defaultActiveInterval)
    }

    static func isAlertEnabled(_ kind: AlertKind) -> Bool {
        UserDefaults.standard.bool(forKey: Key.alertEnabled(kind))
    }

    private static func interval(forKey key: String, allowed: [Double], fallback: Double) -> Duration {
        let stored = UserDefaults.standard.double(forKey: key)
        let seconds = allowed.contains(stored) ? stored : fallback
        return .milliseconds(Int(seconds * 1000))
    }
}
