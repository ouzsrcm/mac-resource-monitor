import SwiftUI

/// App / wired / compressed bellek miktarlarını toplam belleğe oranla
/// yatay yığılmış tek bir çubukta ve altında renk açıklamalarıyla gösterir.
struct MemoryBreakdownBar: View {
    let stats: MemoryStats

    private struct Segment: Identifiable {
        let id: String
        let bytes: UInt64
        let color: Color
    }

    private var segments: [Segment] {
        [
            Segment(id: String(localized: "Uygulama Belleği"), bytes: stats.app, color: .blue),
            Segment(id: String(localized: "Kalıcı Bellek"), bytes: stats.wired, color: .orange),
            Segment(id: String(localized: "Sıkıştırılmış"), bytes: stats.compressed, color: .purple),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: proxy.size.width * fraction(of: segment))
                    }
                    Spacer(minLength: 0)
                }
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 10)

            ForEach(segments) { segment in
                HStack(spacing: 6) {
                    Circle()
                        .fill(segment.color)
                        .frame(width: 8, height: 8)
                    Text(segment.id)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.bytes(segment.bytes))
                        .monospacedDigit()
                }
            }
        }
    }

    private func fraction(of segment: Segment) -> Double {
        guard stats.total > 0 else { return 0 }
        return min(1, Double(segment.bytes) / Double(stats.total))
    }
}
