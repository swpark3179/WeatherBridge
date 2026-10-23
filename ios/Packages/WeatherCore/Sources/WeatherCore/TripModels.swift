/// 앱 "여행" 화면의 데이터 계약 (서버 `trips` 함수 응답).
///
/// 서버(`server/supabase/functions/_shared/trips.ts`)가 같은 키로 만든다. 시각은 epoch 초(Int), 여행 날짜는 "YYYY-MM-DD".
/// 계약 샘플: Tests/WeatherCoreTests/Fixtures/trips_response.json (서버 테스트가 생성 결과와 비교한다)
public struct TripsResponse: Codable, Hashable, Sendable {
    public var generatedAt: Int
    /// 강조 기준 강수확률(%)
    public var threshold: Int
    /// 집. 등록하지 않았으면 nil
    public var home: TripHome?
    /// 진행 중, 다가오는 여행(출발 순), 끝난 여행(최근 순)
    public var trips: [Trip]
}

public struct TripHome: Codable, Hashable, Sendable {
    public var name: String
    /// 집 IANA 시간대
    public var tz: String
    /// 지난 7일 ~ 오늘의 시간별 기온, Open-Meteo 모델마다 하나씩(`providers`에 그 모델 하나).
    /// 감시 중인 여행이 없으면 비어 있다.
    public var recent: [TemperatureHistory]
}

public struct Trip: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// 목적지 이름
    public var name: String
    /// 목적지 IANA 시간대
    public var tz: String
    /// 목적지 달력 날짜 (그 날 포함)
    public var startDate: LocalDate
    public var endDate: LocalDate
    /// 예보를 받는 중인지. 끝났거나 출발이 아직 멀면 false이고 날씨가 비어 있다.
    public var watched: Bool
    /// 아직 지나지 않은 여행 날짜
    public var days: [TripDay]
}

/// 여행 날짜 하루: 목적지와 집의 같은 달력 날짜. 하루 경계는 각 장소의 시간대다.
public struct TripDay: Codable, Hashable, Sendable {
    public var date: LocalDate
    public var destination: TripDayWeather?
    public var home: TripDayWeather?
}

/// 한 장소의 하루 날씨
public struct TripDayWeather: Codable, Hashable, Sendable {
    /// 그 장소 현지 날짜의 0시 (epoch 초)
    public var start: Int
    /// 남은 시간의 비 소식. 이미 지난 날이거나 예보가 닿지 않으면 nil
    public var rain: TripRain?
    /// 낮(8–20시) 평균 운량(%)
    public var cloud: Int?
    /// 하루 적설(cm)
    public var snowCm: Double?
    /// 0–24시 시간별 기온. 그 날 끝까지 닿는 Open-Meteo 모델의 평균(`providers`)
    public var temps: TemperatureHistory?
    /// 하루 강수량(mm), 모델 평균. 비 소식이 없는 지난 날의 하늘에 쓴다. 이전 서버의 응답이면 nil
    public var precipMm: Double?
}

/// 하루 비 소식 (오늘 탭 7일 보기와 같은 계산)
public struct TripRain: Codable, Hashable, Sendable {
    public var pop: Int
    public var agreeing: Int
    public var total: Int
    public var rainy: Bool

    public var level: RainLevel { RainLevel(pop: pop) }
}
