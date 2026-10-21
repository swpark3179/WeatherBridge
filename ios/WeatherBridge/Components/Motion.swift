import Combine
import SwiftUI

/// 앱 공통 움직임. 동작 줄이기가 켜져 있으면 값은 바로 바뀌고, 나타나고 사라지는 것은 움직이지 않고 흐려지기만 한다.
enum Motion {
    /// 보기 전환, 새 값으로 바뀔 때
    static let standard = Animation.easeInOut(duration: 0.32)
    /// 장소·범위가 바뀌어 그래프가 새 값으로 옮겨 갈 때
    static let gentle = Animation.easeInOut(duration: 0.48)
    /// 막대·카드가 자라거나 들어올 때
    static let spring = Animation.spring(duration: 0.55, bounce: 0.25)
    /// 그래프 선이 왼쪽부터 그려질 때
    static let reveal = Animation.easeOut(duration: 1.1)
    /// 동작 줄이기에서 화면이 바뀔 때 (흐려지기만)
    static let fade = Animation.easeInOut(duration: 0.2)
}

extension View {
    /// `value`가 바뀌면 `animation`으로 움직인다. 동작 줄이기가 켜져 있으면 `reduced`(기본: 바로 바뀜).
    /// 화면 내용이 통째로 바뀌는 곳은 `reduced: Motion.fade`로 흐려지게 한다.
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, reduced: Animation? = nil, value: V) -> some View {
        modifier(MotionAnimation(animation: animation, reduced: reduced, value: value))
    }

    /// 나타나고 사라질 때 `transition`. 동작 줄이기가 켜져 있으면 흐려지기만 한다.
    func motionTransition(_ transition: AnyTransition) -> some View {
        modifier(MotionTransition(transition: transition))
    }
}

/// 동작 줄이기면 `reduced`(기본: 바로 바뀜), 아니면 `animation`으로 `body`의 상태 변화를 움직인다.
@MainActor
func withMotion<Result>(
    _ animation: Animation = Motion.standard,
    reduceMotion: Bool,
    reduced: Animation? = nil,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(reduceMotion ? reduced : animation, body)
}

private struct MotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let reduced: Animation?
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? reduced : animation, value: value)
    }
}

private struct MotionTransition: ViewModifier {
    let transition: AnyTransition

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? .opacity : transition)
    }
}

extension EnvironmentValues {
    /// 저전력 모드. 켜지면 날씨 장면·빗줄기가 멈춘다 (ContentView가 바뀔 때마다 넣는다)
    @Entry var isLowPowerMode: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
}

extension View {
    /// 저전력 모드가 바뀔 때마다 `isLowPowerMode`를 새로 넣는다. 앱 맨 위 화면에 한 번 건다.
    func tracksLowPowerMode() -> some View {
        modifier(LowPowerModeTracker())
    }
}

private struct LowPowerModeTracker: ViewModifier {
    @State private var isOn = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.isLowPowerMode, isOn)
            // 알림은 아무 스레드에서나 오므로 메인으로 옮겨 받는다
            .onReceive(
                NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
                    .receive(on: DispatchQueue.main)
            ) { _ in
                isOn = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}
