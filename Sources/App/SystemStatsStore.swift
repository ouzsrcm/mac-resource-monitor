import Foundation
import Observation

@MainActor
@Observable
final class SystemStatsStore {
    var cpu: Double = 0

    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            var monitor = CPUMonitor()
            _ = monitor.read()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if let value = monitor.read() {
                    self.cpu = value
                }
            }
        }
    }

    deinit {
        task?.cancel()
    }
}
