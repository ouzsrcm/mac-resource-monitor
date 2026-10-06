import Foundation

/// Disk menü bar öğesinde gösterilecek bilgi.
enum DiskLabelMode: String, CaseIterable, Sendable {
    case freeSpace
    case throughput

    var title: String {
        switch self {
        case .freeSpace: String(localized: "Boş alan")
        case .throughput: String(localized: "Okuma/yazma hızı")
        }
    }
}

/// Menü bar öğelerinin yalnızca ikonla mı, ikon ve değerle mi gösterileceği.
enum MenuBarLabelStyle: String, CaseIterable, Sendable {
    case iconOnly
    case iconAndValue

    var title: String {
        switch self {
        case .iconOnly: String(localized: "Yalnızca ikon")
        case .iconAndValue: String(localized: "İkon ve değer")
        }
    }
}

/// Arayüz dili. `system` dışındaki seçimler uygulamanın `AppleLanguages`
/// tercihini değiştirir; Foundation bunu yalnızca açılışta okuduğu için
/// değişiklik yeniden başlatınca geçerli olur.
enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case turkish = "tr"
    case english = "en"

    private static let appleLanguagesKey = "AppleLanguages"

    /// Uygulama açılırken geçerli olan seçim; ayarlarda yeniden başlatma
    /// gerekip gerekmediğini anlamak için kullanılır.
    static let atLaunch = stored

    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: AppSettings.Key.appLanguage).flatMap(AppLanguage.init) ?? .system
    }

    /// Dil adları her zaman kendi dillerinde gösterilir.
    var title: String {
        switch self {
        case .system: String(localized: "Sistem dili")
        case .turkish: "Türkçe"
        case .english: "English"
        }
    }

    func apply() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: Self.appleLanguagesKey)
        case .turkish, .english:
            UserDefaults.standard.set([rawValue], forKey: Self.appleLanguagesKey)
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
        static let showDeviceBatteries = "showDeviceBatteries"
        static let idleInterval = "idleIntervalSeconds"
        static let activeInterval = "activeIntervalSeconds"
        static let diskLabelMode = "diskLabelMode"
        static let menuBarLabelStyle = "menuBarLabelStyle"
        static let appLanguage = "appLanguage"

        static func alertEnabled(_ kind: AlertKind) -> String {
            "alert.\(kind.rawValue)"
        }
    }

    static let idleIntervalOptions: [Double] = [1, 2, 3, 5]
    static let activeIntervalOptions: [Double] = [0.5, 1, 2]
    static let defaultIdleInterval: Double = 3
    static let defaultActiveInterval: Double = 1
    static let defaultMenuBarLabelStyle = MenuBarLabelStyle.iconOnly

    /// `UserDefaults` okumalarının (`@AppStorage` dışında) da doğru
    /// varsayılanları görmesi için uygulama açılışında çağrılır.
    static func registerDefaults() {
        var defaults: [String: Any] = [
            Key.idleInterval: defaultIdleInterval,
            Key.activeInterval: defaultActiveInterval,
            Key.diskLabelMode: DiskLabelMode.freeSpace.rawValue,
            Key.menuBarLabelStyle: defaultMenuBarLabelStyle.rawValue,
            Key.appLanguage: AppLanguage.system.rawValue,
            Key.showDeviceBatteries: true,
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

    /// Sistem panelindeki Bluetooth cihaz pilleri. Varsayılan açık.
    static var showDeviceBatteries: Bool {
        UserDefaults.standard.bool(forKey: Key.showDeviceBatteries)
    }

    private static func interval(forKey key: String, allowed: [Double], fallback: Double) -> Duration {
        let stored = UserDefaults.standard.double(forKey: key)
        let seconds = allowed.contains(stored) ? stored : fallback
        return .milliseconds(Int(seconds * 1000))
    }
}
