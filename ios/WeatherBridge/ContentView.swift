import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bridge: LiveActivityBridge
    @Environment(\.scenePhase) private var scenePhase
    /// 날씨·기온 탭에서 고른 장소와 기온 보기. AppModel 값을 장면 상태로 비춰 둔다 (UserDefaults는 쓰지 않는다)
    @SceneStorage("focusedPlace") private var storedPlace: PlaceKind = .home
    @SceneStorage("temperatureMode") private var storedTemperatureMode: TemperatureMode = .threeDay

    var body: some View {
        content
            // 불러오는 중 → 온보딩·탭 화면은 흐려지며 바뀐다
            .motion(reduced: Motion.fade, value: model.phase)
            .tracksLowPowerMode()
            .task { await model.start() }
            .onReceive(bridge.$apnsDeviceToken.combineLatest(bridge.$pushToStartToken)) { apns, pushToStart in
                model.updateTokens(apns: apns, pushToStart: pushToStart)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.didBecomeActive() }
                }
            }
            .onAppear {
                model.focusedPlace = storedPlace
                model.temperatureMode = storedTemperatureMode
            }
            .onChange(of: model.focusedPlace) { _, place in storedPlace = place }
            .onChange(of: model.temperatureMode) { _, mode in storedTemperatureMode = mode }
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
                Tab("날씨", systemImage: "cloud.sun", value: AppTab.weather) {
                    TodayView()
                }
                Tab("기온", systemImage: "thermometer.medium", value: AppTab.temperature) {
                    TemperatureTab()
                }
                Tab("여행", systemImage: "airplane", value: AppTab.trips) {
                    TripListView()
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
