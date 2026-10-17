import ActivityKit
import WeatherCore

// 앱과 위젯 확장 양쪽에 컴파일된다.
// 데이터 계약은 WeatherCore(Linux에서도 테스트)에 두고, ActivityKit 적합성만 여기서 붙인다.
extension CommuteActivityAttributes: @retroactive ActivityAttributes {
    public typealias ContentState = CommuteState
}
