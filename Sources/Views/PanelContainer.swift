import SwiftUI

/// Tüm panellerin ortak iskeleti: başlık, içerik, ayraç ve "Çıkış" butonu.
/// Görünürlüğünü `SamplingEngine`'e bildirerek uyarlanabilir örneklemeyi tetikler.
struct PanelContainer<Content: View>: View {
    let title: LocalizedStringKey
    let kind: PanelKind
    let engine: SamplingEngine
    @ViewBuilder let content: Content

    init(title: LocalizedStringKey, kind: PanelKind, engine: SamplingEngine, @ViewBuilder content: () -> Content) {
        self.title = title
        self.kind = kind
        self.engine = engine
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content
            }

            Divider()

            HStack {
                Button("Çıkış") {
                    NSApplication.shared.terminate(nil)
                }
                SettingsLink {
                    Text("Ayarlar…")
                }
                // LSUIElement uygulamaları kendiliğinden etkinleşmez; etkinleştirmezsek
                // ayarlar penceresi diğer uygulamaların arkasında açılır.
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
                Spacer(minLength: 4)
                if let selfUsage = engine.selfUsage {
                    Text(Format.selfUsage(selfUsage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .onAppear { engine.panelDidAppear(kind) }
        .onDisappear { engine.panelDidDisappear(kind) }
    }
}

struct StatRow: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
}
