/// 출근 브리핑 Live Activity의 데이터 계약.
///
/// 서버(`server/supabase/functions/_shared/apns.ts`)가 APNs 페이로드의 `attributes` /
/// `content-state`로 같은 키를 보낸다. 날짜는 ActivityKit 디코딩 방식에 의존하지 않도록
/// 모두 epoch 초(Int)로 주고받는다. 계약 샘플: Tests/WeatherCoreTests/Fixtures/live_activity_start.json
public struct CommuteActivityAttributes: Codable, Hashable, Sendable {
    /// 출근 시각 T (epoch 초). 잠금화면 표시는 이 시각에 끝난다.
    public var windowEnd: Int
    /// `PlaceBrief.pops[0]`이 가리키는 현지 시각(0–23시).
    public var firstHour: Int

    public init(windowEnd: Int, firstHour: Int) {
        self.windowEnd = windowEnd
        self.firstHour = firstHour
    }
}

public struct CommuteState: Codable, Hashable, Sendable {
    /// 한 줄 요약. 예: "☔ 회사 15–18시 최대 70%", "오늘 비 소식 없음"
    public var headline: String
    /// 집·회사 중 오늘 비 가능 시간대가 있으면 true (강조 표시)
    public var highlight: Bool
    public var places: [PlaceBrief]
    /// 서버가 내용을 만든 시각 (epoch 초)
    public var updatedAt: Int

    public init(headline: String, highlight: Bool, places: [PlaceBrief], updatedAt: Int) {
        self.headline = headline
        self.highlight = highlight
        self.places = places
        self.updatedAt = updatedAt
    }

    /// 모든 장소 중 가장 높은 강수확률
    public var maxPop: Int {
        places.map(\.maxPop).max() ?? 0
    }
}

public struct PlaceBrief: Codable, Hashable, Sendable {
    /// "집", "회사"
    public var name: String
    /// 현재 기온(°C). 소스가 없으면 nil
    public var temp: Int?
    /// `firstHour`부터 시간별 종합 강수확률(0–100)
    public var pops: [Int]
    /// 오늘 남은 시간 중 최대 강수확률
    public var maxPop: Int
    /// 비 구간 요약. 예: "15–18시". 없으면 nil
    public var rainWindow: String?

    public init(name: String, temp: Int?, pops: [Int], maxPop: Int, rainWindow: String?) {
        self.name = name
        self.temp = temp
        self.pops = pops
        self.maxPop = maxPop
        self.rainWindow = rainWindow
    }

    public var level: RainLevel {
        RainLevel(pop: maxPop)
    }
}
