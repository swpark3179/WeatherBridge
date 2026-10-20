import UserNotifications

/// 알림 권한. 앱을 처음 열 때가 아니라 요약 알림을 켤 때 묻는다.
enum NotificationPermission {
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 아직 묻지 않았으면 묻고, 허용 여부를 돌려준다.
    @discardableResult
    static func request() async -> Bool {
        switch await status() {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await MainActor.run { LiveActivityBridge.shared.notificationsGranted = granted }
            return granted
        }
    }
}
