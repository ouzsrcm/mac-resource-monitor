import AppKit
import SwiftUI

/// Başlık ve en çok kaynak tüketen süreçlerin satırları.
struct ProcessList: View {
    let title: LocalizedStringKey
    let processes: [ProcessUsage]?
    let value: (ProcessUsage) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let processes, !processes.isEmpty {
                ForEach(processes) { process in
                    ProcessRow(process: process, value: value(process))
                }
            } else {
                Text("Ölçülüyor…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage
    let value: String

    var body: some View {
        // Uygulama olan süreçlerde (Dock'taki veya arka plan uygulamaları)
        // yerelleştirilmiş ad ve ikon alınabilir; daemon'larda nil döner.
        let app = NSRunningApplication(processIdentifier: process.pid)

        HStack(spacing: 6) {
            Group {
                if let icon = app?.icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            Text(app?.localizedName ?? process.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
        .contentShape(Rectangle())
        .help("PID \(process.pid)")
        .contextMenu {
            Button("PID'i kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(process.pid), forType: .string)
            }
        }
    }
}
