import BackgroundTasks
import Foundation
import os

/// Saatlik `BGAppRefreshTask`. `Info.plist` içindeki izin listesiyle aynı kimlik kullanılır.
enum CompanionRefreshTask {
    static let identifier = "tr.ouzsrcm.MenuMonitor.companion.refresh"
    /// İstenen en erken çalışma. iOS bu süreyi alt sınır sayar, söz vermez.
    private static let earliestInterval: TimeInterval = 60 * 60
    private static let logger = Logger(subsystem: "tr.ouzsrcm.MenuMonitor.companion", category: "refresh")

    /// Her açılışta, `application(_:didFinishLaunchingWithOptions:)` bitmeden kaydolunur.
    /// Kayıt yoksa sistem zamanlanmış görevi teslim etmez.
    static func register() {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
        if !registered {
            logger.error("Arka plan görevi kaydedilemedi.")
        }
    }

    /// Yaklaşık bir saat sonrası için yenileme ister.
    /// `earliestBeginDate` bir alt sınırdır. iOS görevi bu andan önce çalıştırmaz;
    /// daha geç çalıştırması, bütçe bitince ertelemesi veya hiç çalıştırmaması sistemin takdirindedir.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            if isBenignScheduleError(error) { return }
            logger.error("Arka plan yenilemesi planlanamadı: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Süre dolup iş yarıda kesilse bile sonraki istek kuyrukta kalsın.
        schedule()
        let completion = RefreshCompletion(task)
        let work = Task { @MainActor in
            await CompanionSession.shared.sendNow() == .saved
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
        Task {
            let saved = await work.value
            completion.finish(success: saved && !work.isCancelled)
        }
    }

    private static func isBenignScheduleError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == BGTaskScheduler.errorDomain else { return false }
        return nsError.code == BGTaskScheduler.Error.Code.unavailable.rawValue
            || nsError.code == BGTaskScheduler.Error.Code.tooManyPendingTaskRequests.rawValue
    }
}

/// `setTaskCompleted` bir kez çağrılsın. Süre dolması ile işin bitmesi aynı anda gelebilir.
private final class RefreshCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let task: BGAppRefreshTask

    init(_ task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        if didFinish {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}
