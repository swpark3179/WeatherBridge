import SwiftUI

@main
struct WeatherBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(LiveActivityBridge.shared)
        }
    }
}
