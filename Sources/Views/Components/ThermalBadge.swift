import SwiftUI

extension ProcessInfo.ThermalState {
    var color: Color {
        switch self {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .gray
        }
    }

    /// Menü bar ve panel için duruma göre değişen termometre sembolü.
    var symbolName: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious: "thermometer.high"
        case .critical: "thermometer.sun.fill"
        @unknown default: "thermometer.medium"
        }
    }
}

struct ThermalBadge: View {
    let state: ProcessInfo.ThermalState?

    var body: some View {
        StatusBadge(title: state?.title ?? "Bilinmiyor", color: state?.color ?? .gray)
    }
}
