import SwiftUI

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }
}

/// Bellek baskısını renkli bir kapsül rozet olarak gösterir.
struct PressureBadge: View {
    let pressure: MemoryPressure?

    private var color: Color { pressure?.color ?? .gray }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(pressure?.title ?? "Bilinmiyor")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(color.opacity(0.2), in: Capsule())
    }
}
