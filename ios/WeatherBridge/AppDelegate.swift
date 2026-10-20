import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 알림 권한은 요약 알림을 켤 때 묻는다(NotificationPermission). 기기 토큰은 권한과 상관없이 받을 수 있다.
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        Task { @MainActor in
            LiveActivityBridge.shared.start()
            let status = await NotificationPermission.status()
            LiveActivityBridge.shared.notificationsGranted = status == .notDetermined ? nil : status == .authorized
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

    /// 앱을 보고 있을 때 온 요약 알림도 배너로 보여준다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
