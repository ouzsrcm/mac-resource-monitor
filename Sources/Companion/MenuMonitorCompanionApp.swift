import SwiftUI
import UIKit

@main
struct MenuMonitorCompanionApp: App {
    @UIApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
    @State private var session = CompanionSession.shared

    var body: some Scene {
        WindowGroup {
            CompanionRootView(session: session)
        }
    }
}

final class CompanionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CompanionRefreshTask.register()
        CompanionRefreshTask.schedule()
        CompanionSession.shared.start()
        return true
    }
}
