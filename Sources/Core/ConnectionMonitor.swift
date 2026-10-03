import Foundation
import Network
import Observation

enum ConnectionType: Sendable {
    case wifi
    case ethernet
    case other
    case disconnected

    init(path: NWPath) {
        guard path.status == .satisfied else {
            self = .disconnected
            return
        }
        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .ethernet
        } else {
            self = .other
        }
    }

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .other: "Diğer"
        case .disconnected: "Yok"
        }
    }
}

/// Aktif internet bağlantısının türünü `NWPathMonitor` ile izler.
/// Değişiklikler sistemden olay olarak geldiği için örnekleme döngüsüne dahil değildir.
@MainActor
@Observable
final class ConnectionMonitor {
    private(set) var type: ConnectionType = .disconnected
    /// Aktif fiziksel arayüzün BSD adı, ör. "en0".
    private(set) var interfaceName: String?

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        // Güncelleme işleyicisi arka plan kuyruğunda çalışır; bu yüzden
        // açıkça @Sendable işaretliyoruz ve durumu ana aktöre aktarıyoruz.
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let type = ConnectionType(path: path)
            let interfaceName = Self.primaryInterfaceName(of: path)
            Task { @MainActor [weak self] in
                self?.type = type
                self?.interfaceName = interfaceName
            }
        }
        monitor.start(queue: DispatchQueue(label: "tr.ouzsrcm.MenuMonitor.path-monitor"))
    }

    deinit {
        monitor.cancel()
    }

    /// `availableInterfaces` tercih sırasındadır; VPN açıkken ilk sırada sanal
    /// tünel (utun) olabileceği için önce Wi-Fi/Ethernet arayüzünü arıyoruz.
    private nonisolated static func primaryInterfaceName(of path: NWPath) -> String? {
        guard path.status == .satisfied else { return nil }
        let physical = path.availableInterfaces.first {
            $0.type == .wifi || $0.type == .wiredEthernet
        }
        return (physical ?? path.availableInterfaces.first)?.name
    }
}
