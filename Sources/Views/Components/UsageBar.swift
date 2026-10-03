import SwiftUI

/// 0.0–1.0 arası bir doluluk oranını yatay çubuk olarak gösterir.
struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.quaternary)
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }
}
