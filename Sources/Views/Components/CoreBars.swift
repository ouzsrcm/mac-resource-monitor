import SwiftUI

/// Bir çekirdek grubunun başlığı ve her çekirdek için ince dikey kullanım çubuğu.
struct CoreGroupView: View {
    let group: CoreGroup

    private var title: String {
        switch group.kind {
        case .performance: "Performans (P)"
        case .efficiency: "Verimlilik (E)"
        case .unified: "Çekirdekler"
        }
    }

    private var tint: Color {
        switch group.kind {
        case .performance, .unified: .blue
        case .efficiency: .teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(group.usages.indices, id: \.self) { index in
                    CoreBar(usage: group.usages[index], tint: tint)
                        .help("Çekirdek \(index + 1): \(Format.percent(group.usages[index]))")
                }
            }
            .frame(height: 36)
        }
    }
}

private struct CoreBar: View {
    let usage: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(height: proxy.size.height * min(max(usage, 0), 1))
            }
        }
        .frame(maxWidth: 8)
        .animation(.easeOut(duration: 0.25), value: usage)
    }
}
