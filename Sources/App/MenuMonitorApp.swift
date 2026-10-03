import SwiftUI

@main
struct MenuMonitorApp: App {
    @State private var store = SystemStatsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(store: store)
        } label: {
            Text("CPU \(Int((store.cpu * 100).rounded()))%")
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuPanel: View {
    let store: SystemStatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CPU")
                Spacer()
                Text(String(format: "%.1f%%", store.cpu * 100))
                    .monospacedDigit()
            }
            .font(.headline)

            Divider()

            Button("Çıkış") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
