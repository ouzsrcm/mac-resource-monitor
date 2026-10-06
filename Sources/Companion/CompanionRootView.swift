import SwiftUI
import UIKit

struct CompanionRootView: View {
    @Bindable var session: CompanionSession
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var nameFocused: Bool
    @State private var nameAtFocus = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    batteryBlock
                    sendBlock
                    nameBlock
                    if let warning = session.iCloudWarning {
                        warningBlock(warning)
                    }
                    automationBlock
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Pil Senkronu")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            session.start()
            await session.refreshWhileOpen()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await session.refreshWhileOpen() }
            case .background:
                CompanionRefreshTask.schedule()
            default:
                break
            }
        }
    }

    private var batteryBlock: some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 44))
                .foregroundStyle(batteryColor)
                .symbolRenderingMode(.hierarchical)
            Text(percentText)
                .font(.system(size: 72, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(batteryColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(session.statusText)
                .font(.title3)
                .foregroundStyle(.secondary)
            LastSentLine(date: session.lastSentAt)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var sendBlock: some View {
        VStack(spacing: 8) {
            Button {
                Task { await session.sendNow() }
            } label: {
                if session.isSending {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Şimdi gönder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(session.isSending || session.percent == nil)

            if let banner = session.banner {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cihaz adı")
                .font(.subheadline.weight(.semibold))
            TextField("Cihaz adı", text: $session.deviceName, prompt: Text(UIDevice.current.model))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit(commitNameIfEdited)
            Text("Mac'teki listede bu ad görünür.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: nameFocused) { _, focused in
            if focused {
                nameAtFocus = session.deviceName
            } else if session.deviceName != nameAtFocus {
                commitNameIfEdited()
            }
        }
    }

    private func warningBlock(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.icloud")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private var automationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Otomatik güncelleme kurulumu")
                .font(.headline)
            Text("Saatlik arka plan yenilemesi iOS'un takdirindedir ve gecikebilir. Seviye veya şarj değişince gönderim için Kestirmeler'de otomasyon kurun.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(Self.automationSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                    Text(step)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var percentText: String {
        guard let percent = session.percent else { return "—" }
        return "\(percent)%"
    }

    private var symbolName: String {
        if session.isCharging { return "battery.100percent.bolt" }
        switch session.level ?? -1 {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        if session.isCharging { return .green }
        if let percent = session.percent, percent < 20 { return .red }
        return .primary
    }

    private func commitNameIfEdited() {
        Task { await session.commitDeviceName() }
    }

    private static let automationSteps = [
        "Kestirmeler'i açın, Otomasyon sekmesine geçin ve Yeni Otomasyon'a dokunun.",
        "Pil Seviyesi'ni seçin. Örneğin %80, %50 ve %20 için ayrı otomasyonlar kurun.",
        "Şarj Aleti ile iki otomasyon daha ekleyin: takıldığında ve çıkarıldığında.",
        "Eylem listesinde Pil Senkronu altında Pil Durumunu Gönder'i seçin.",
        "Hemen Çalıştır'ı açın. Çalıştırmadan önce sor kapalı kalsın; onay beklemeden gönderilir.",
    ]
}

private struct LastSentLine: View {
    let date: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.text(date: date, now: context.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private static func text(date: Date?, now: Date) -> String {
        guard let date else { return "Son gönderim: henüz yok" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "Son gönderim: az önce" }
        let minutes = seconds / 60
        if minutes < 60 { return "Son gönderim: \(minutes) dk önce" }
        let hours = minutes / 60
        if hours < 24 { return "Son gönderim: \(hours) sa önce" }
        return "Son gönderim: \(hours / 24) gün önce"
    }
}
