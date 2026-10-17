import ActivityKit
import Foundation
import WeatherCore

/// Live Activity 토큰 수집과 시작/종료를 담당한다.
/// Phase 0에서는 실험실 화면이 토큰을 보여주고, 이후 단계에서 서버 등록으로 이어진다.
@MainActor
final class LiveActivityBridge: ObservableObject {
    static let shared = LiveActivityBridge()

    @Published var notificationsGranted: Bool?
    @Published var apnsDeviceToken: String?
    @Published var pushToStartToken: String?
    @Published var activeCount = 0
    @Published var lastError: String?

    private var started = false

    var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start() {
        guard !started else { return }
        started = true
        endExpired()
        refreshCount()

        Task {
            for await data in Activity<CommuteActivityAttributes>.pushToStartTokenUpdates {
                self.pushToStartToken = data.hexString
            }
        }
        Task {
            for await _ in Activity<CommuteActivityAttributes>.activityUpdates {
                self.refreshCount()
            }
        }
    }

    /// 로컬에서 샘플 브리핑을 시작한다. channelId가 있으면 브로드캐스트 채널을 구독한다.
    func startSample(minutes: Int, channelId: String?) {
        let now = Date.now
        let end = now.addingTimeInterval(TimeInterval(minutes * 60))
        let attributes = CommuteActivityAttributes(
            windowEnd: Int(end.timeIntervalSince1970),
            firstHour: Calendar.current.component(.hour, from: now)
        )
        let state = SampleData.commuteState(updatedAt: now)
        let content = ActivityContent(state: state, staleDate: end)

        do {
            let channel = channelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pushType: PushType? = channel.isEmpty ? nil : .channel(channel)
            _ = try Activity.request(attributes: attributes, content: content, pushType: pushType)
            lastError = nil
        } catch {
            lastError = "시작 실패: \(error.localizedDescription)"
        }
        refreshCount()
    }

    func endAll() {
        Task {
            for activity in Activity<CommuteActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            refreshCount()
        }
    }

    /// 출근 시각이 지난 활동은 즉시 종료한다(종료 푸시가 유실된 경우 대비).
    func endExpired() {
        let now = Int(Date.now.timeIntervalSince1970)
        Task {
            for activity in Activity<CommuteActivityAttributes>.activities where activity.attributes.windowEnd <= now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            refreshCount()
        }
    }

    private func refreshCount() {
        activeCount = Activity<CommuteActivityAttributes>.activities.count
    }
}
