import AppIntents

/// Kestirmeler'den, uygulamayı açmadan pil durumunu iCloud'a yazar.
struct SendBatteryIntent: AppIntent {
    static var title: LocalizedStringResource { "Pil Durumunu Gönder" }
    static var description: IntentDescription {
        IntentDescription("Bu cihazın pil yüzdesini ve şarj durumunu iCloud'a yazar.")
    }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        switch await CompanionSession.shared.sendNow() {
        case .saved, .skipped:
            return .result()
        case .unreadable:
            throw CompanionIntentError.unreadable
        case .failed:
            throw CompanionIntentError.failed
        }
    }
}

private enum CompanionIntentError: LocalizedError {
    case unreadable
    case failed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "Pil durumu okunamadı."
        case .failed:
            "Pil durumu iCloud'a yazılamadı."
        }
    }
}

struct CompanionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendBatteryIntent(),
            phrases: [
                "Pil durumunu \(.applicationName) ile gönder",
                "\(.applicationName) ile pil durumunu gönder",
                "\(.applicationName) pil durumunu güncelle",
            ],
            shortTitle: "Pil Durumunu Gönder",
            systemImageName: "battery.100percent"
        )
    }
}
