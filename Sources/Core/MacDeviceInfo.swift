import Darwin
import Foundation

/// Bu Mac'in iCloud kaydına yazılacak görünen ad ve donanım kimliği.
/// Seri numarası ve IOPlatformUUID okunmaz.
enum MacDeviceInfo {
    static var name: String {
        let localized = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localized, !localized.isEmpty { return localized }
        let host = ProcessInfo.processInfo.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? "Mac" : host
    }

    /// Pazarlama adı değil, `hw.model` kimliği (ör. MacBookPro18,3).
    static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return "Mac" }
        var buffer = [UInt8](repeating: 0, count: size)
        // sysctl model adını bu tampona yazar; işaretçi tamponun ömrü dışına çıkmaz.
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return sysctlbyname("hw.model", base, &size, nil, 0)
        }
        guard status == 0 else { return "Mac" }
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let model = String(decoding: buffer[..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? "Mac" : model
    }
}
