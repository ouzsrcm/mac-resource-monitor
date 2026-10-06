import AppKit

/// İndirilen kopya Applications klasöründe değilse kurulumu sorar.
/// Disk imajı, İndirilenler veya karantinalı bir konumdan açılınca devreye girer.
@MainActor
enum AppInstaller {
    static func installIfNeeded() {
        guard needsInstall else { return }

        // Menü çubuğu uygulaması Dock'ta görünmez; kurulum penceresi öne çıksın diye
        // bu süreç kısa süreliğine normal uygulama olur.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = String(localized: "MenuMonitor'ü kur")
        alert.informativeText = String(localized: "Uygulama indirilen kopyadan çalışıyor. Applications klasörüne kurulunca menü çubuğunda kalıcı olur.")
        alert.addButton(withTitle: String(localized: "Kur"))
        alert.addButton(withTitle: String(localized: "Şimdi değil"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.setActivationPolicy(.accessory)
            return
        }

        let destination: URL
        do {
            destination = try installedCopy()
        } catch {
            presentFailure()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        Task { @MainActor in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: destination, configuration: configuration)
                // Kurulu kopya açıldı. Bu süreç indirilen konumda kalmasın.
                exit(0)
            } catch {
                presentFailure()
            }
        }
    }

    /// Xcode'dan veya DerivedData'dan çalışırken kurulum sorulmaz.
    private static var needsInstall: Bool {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }
        if isTranslocated {
            return true
        }
        if isInstalledLocation {
            return false
        }
        return isOnDiskImage || isInDownloads || hasQuarantine
    }

    private static var isTranslocated: Bool {
        Bundle.main.bundleURL.path.contains("/AppTranslocation/")
    }

    private static var isInstalledLocation: Bool {
        let parent = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return applicationFolders.contains { folder in
            folder.standardizedFileURL.resolvingSymlinksInPath() == parent
        }
    }

    private static var isOnDiskImage: Bool {
        Bundle.main.bundleURL.resolvingSymlinksInPath().path.hasPrefix("/Volumes/")
    }

    private static var isInDownloads: Bool {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            return false
        }
        let root = downloads.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix(prefix)
    }

    private static var hasQuarantine: Bool {
        let values = try? Bundle.main.bundleURL.resourceValues(forKeys: [.quarantinePropertiesKey])
        return values?.quarantineProperties != nil
    }

    private static var applicationFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    /// Önce /Applications, yazılamazsa kullanıcının Applications klasörü.
    private static func installedCopy() throws -> URL {
        let source = Bundle.main.bundleURL
        var lastError: Error = CocoaError(.fileWriteUnknown)
        for folder in applicationFolders {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent("MenuMonitor.app", isDirectory: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                // Finder kopyası noter biletini düşürebilir; ditto paketi olduğu gibi taşır.
                try copyWithDitto(from: source, to: destination)
                return destination
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func copyWithDitto(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func presentFailure() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Kurulum başarısız")
        alert.informativeText = String(localized: "MenuMonitor Applications klasörüne kopyalanamadı. Uygulamayı elle Applications klasörüne taşıyın.")
        alert.addButton(withTitle: String(localized: "Tamam"))
        alert.runModal()
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class AppLaunchDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        AppInstaller.installIfNeeded()
    }
}
