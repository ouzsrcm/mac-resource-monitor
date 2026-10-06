import SwiftUI

@main
struct MenuMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppLaunchDelegate.self) private var appLaunch
    @State private var engine = SamplingEngine()

    @AppStorage(AppSettings.Key.showCPU) private var showCPU = true
    @AppStorage(AppSettings.Key.showRAM) private var showRAM = true
    @AppStorage(AppSettings.Key.showNetwork) private var showNetwork = true
    @AppStorage(AppSettings.Key.showDisk) private var showDisk = true
    @AppStorage(AppSettings.Key.showSystem) private var showSystem = true

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

        MenuBarExtra(isInserted: $showDisk) {
            DiskPanel(engine: engine)
        } label: {
            DiskLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $showSystem) {
            SystemPanel(engine: engine)
        } label: {
            SystemLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: engine)
        }
    }
}
