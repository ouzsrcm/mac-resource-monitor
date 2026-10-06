import Foundation

/// Bu kurulumun iCloud kayıt kimliği.
/// Donanım seri numarası ve IOPlatformUUID kullanılmaz; kimlik ilk çalıştırmada
/// üretilir ve yalnızca `UserDefaults`'ta durur. Uygulama silinirse yeni bir kimlik oluşur.
enum LocalDeviceIdentity {
    private static let defaultsKey = "menuMonitor.cloudDeviceId"

    static var identifier: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey),
           UUID(uuidString: existing) != nil {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: defaultsKey)
        return created
    }
}
