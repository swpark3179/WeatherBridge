/// 앱 "오늘"·"비교" 화면의 데이터 계약 (서버 `today` 함수 응답).
///
/// 서버(`server/supabase/functions/_shared/today.ts`)가 같은 키로 만든다. 날짜는 epoch 초(Int).
/// 계약 샘플: Tests/WeatherCoreTests/Fixtures/today_response.json (서버 테스트가 생성 결과와 비교한다)
public struct TodayResponse: Codable, Hashable, Sendable {
    /// 서버가 응답을 만든 시각
    public var generatedAt: Int
    /// IANA 시간대 (예: "Asia/Seoul")
    public var tz: String
    /// 강조 기준 강수확률(%)
    public var threshold: Int
    /// 오늘 남은 시간 기준 요약 (요약 알림·잠금화면과 같은 문구)
    public var briefing: TodayBriefing
    /// 집, 회사 순서
    public var places: [TodayPlace]
}

public struct TodayBriefing: Codable, Hashable, Sendable {
    /// Live Activity와 같은 형식
    public var state: CommuteState
    /// `state.places[].pops[0]`의 현지 시각(0–23시)
    public var firstHour: Int
    /// 알림 본문과 같은 한 줄 요약
    public var summary: String
}

public enum PlaceKind: String, Codable, Hashable, Sendable {
    case home, office, trip
}

public struct TodayPlace: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: PlaceKind
    public var name: String
    /// 응답 범위 중 가장 높은 종합 강수확률
    public var maxPop: Int
    /// 비 구간이 하나라도 있으면 true
    public var highlight: Bool
    public var windows: [RainWindow]
    /// 현재 시각부터 1시간 간격
    public var hours: [TodayHour]
    public var sources: [ForecastSource]
    /// 일부 소스를 받지 못했을 때의 메시지 (나머지 소스로 계산한 결과는 그대로 쓴다)
    public var errors: [String]
}

/// 연속된 비 시간
public struct RainWindow: Codable, Hashable, Sendable {
    public var start: Int
    /// 끝 시각 (포함하지 않음)
    public var end: Int
    public var maxPop: Int
    /// `maxPop` 시간에 임계값 이상인 계열 수 / 참여 계열 수
    public var agreeing: Int
    public var total: Int
}

public struct ForecastSource: Codable, Hashable, Sendable {
    /// "kma_short", "om_ecmwf", "om_gfs", "om_icon" …
    public var provider: String
    /// 상관된 소스끼리 묶은 계열: "kma", "ecmwf", "ncep", "dwd" …
    public var family: String
    public var issuedAt: Int
    public var fetchedAt: Int
}

public struct TodayHour: Codable, Hashable, Sendable {
    /// 시작 시각 (UTC 정시)
    public var t: Int
    /// 계열 가중 평균. 그 시간 값을 준 소스가 없으면 nil
    public var consensus: Int?
    public var min: Int?
    public var max: Int?
    /// 임계값 이상인 계열 수 / 참여 계열 수
    public var agreeing: Int
    public var total: Int
    /// 계열 간 차이가 커서 의견이 갈림
    public var split: Bool
    /// 강조 대상 시간
    public var rainy: Bool
    /// 기온(°C, 기상청 우선)
    public var temp: Double?
    /// 계열 이름 → 강수확률
    public var families: [String: Int]
    /// 소스 이름 → 강수확률
    public var providers: [String: Int]

    public var level: RainLevel? {
        consensus.map(RainLevel.init(pop:))
    }
}
