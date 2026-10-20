import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bridge: LiveActivityBridge
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task { await model.start() }
            .onReceive(bridge.$apnsDeviceToken.combineLatest(bridge.$pushToStartToken)) { apns, pushToStart in
                model.updateTokens(apns: apns, pushToStart: pushToStart)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.didBecomeActive() }
                }
            }
            .alert("알림", isPresented: noticeBinding) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(model.notice ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("불러오는 중…")
        case .notConfigured:
            NavigationStack {
                ContentUnavailableView {
                    Label("서버 설정 없음", systemImage: "server.rack")
                } description: {
                    Text("이 빌드에는 서버 접속 정보가 없습니다. TestFlight로 설치한 앱을 써 주세요.")
                } actions: {
                    NavigationLink("실험실 열기") { SpikeView() }
                }
            }
        case let .failed(message):
            ContentUnavailableView {
                Label("연결하지 못했습니다", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("다시 시도") { Task { await model.start() } }
                    .buttonStyle(.borderedProminent)
            }
        case .onboarding:
            OnboardingView()
        case .ready:
            TabView(selection: $model.selectedTab) {
                Tab("오늘", systemImage: "cloud.sun", value: AppTab.today) {
                    TodayView()
                }
                Tab("비교", systemImage: "square.grid.3x3.fill", value: AppTab.compare) {
                    CompareView()
                }
                Tab("설정", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
        }
    }

    // 온보딩 화면은 안내를 직접 보여주므로 알림 창은 띄우지 않는다.
    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { model.notice != nil && model.phase != .onboarding },
            set: { if !$0 { model.notice = nil } }
        )
    }
}
