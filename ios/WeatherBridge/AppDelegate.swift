import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in
                LiveActivityBridge.shared.notificationsGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
        Task { @MainActor in
            LiveActivityBridge.shared.start()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.hexString
        Task { @MainActor in
            LiveActivityBridge.shared.apnsDeviceToken = hex
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            LiveActivityBridge.shared.lastError = "APNs 등록 실패: \(message)"
        }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
