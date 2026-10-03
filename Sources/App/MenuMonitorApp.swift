import SwiftUI

@main
struct MenuMonitorApp: App {
    @State private var engine = SamplingEngine()

    @AppStorage("showCPU") private var showCPU = true
    @AppStorage("showRAM") private var showRAM = true
    @AppStorage("showNetwork") private var showNetwork = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showCPU) {
            CPUPanel(engine: engine)
        } label: {
            CPULabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $showRAM) {
            MemoryPanel(engine: engine)
        } label: {
            MemoryLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $showNetwork) {
            NetworkPanel(engine: engine)
        } label: {
            NetworkLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
