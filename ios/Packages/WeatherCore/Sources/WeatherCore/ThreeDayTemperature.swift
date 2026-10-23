import Foundation

/// 기온 탭 3일 보기: 어제·오늘·내일 카드, 어제 0시부터 내일 24시까지의 시간별 기온, 지금과 어제 같은 시각.
/// 값은 서버 `around`(그 날 끝까지 닿는 예보 모델의 평균)이고, 두 날의 모델 묶음이 같을 때만 차이를 말한다
/// (모델마다 다른 치우침이 차이에 섞이지 않게, D21·D24). 날마다 전날과 견준다: 오늘은 어제와, 내일은 오늘과.
public struct ThreeDayTemperatureModel: Sendable, Equatable {
    /// 날 이름
    public static let labels = ["어제", "오늘", "내일"]
    /// 같은 시각을 부르는 말: "어제 이맘때보다 3° 낮아요"
    public static let sameHourLabel = "어제 이맘때"

    public struct Day: Sendable, Equatable, Identifiable {
        public var id: Int { offset }
        /// -1 어제, 0 오늘, 1 내일
        public let offset: Int
        public let label: String
        /// "10/22 수"
        public let dateText: String
        /// 현지 0시 (epoch 초)
        public let start: Int
        /// 그 날 하루 날씨. 저장해 둔 지난 응답이라 그 날이 없으면 nil
        public let weather: TripDayWeather?
        /// 그 날 최고·최저 (시간의 3/4 이상 값이 있을 때)
        public let high: Double?
        public let low: Double?
        public let sky: TripSky?
        /// 전날과 비교: "어제보다 조금 선선해요", "오늘과 비슷해요". 어제이거나 전날과 모델 묶음이 다르면 비교하지 않는다.
        /// 화면은 `outlook.high?.baseline`(전날 값)에서 그 날 값으로 숫자를 굴린다
        public let outlook: TemperatureOutlook

        public var rain: TripRain? { weather?.rain }
        /// 기온 평균에 쓴 예보 모델 수
        public var modelCount: Int { weather?.temps?.providers.count ?? 0 }
        /// 보여줄 값이 하나라도 있는지
        public var hasForecast: Bool { high != nil || low != nil || rain != nil || sky != nil }
    }

    /// 맨 위: 지금 기온과 어제·내일 같은 시각
    public struct Headline: Sendable, Equatable {
        /// 지금 현지 시 (0–23)
        public let hour: Int
        /// 지금 기온. 예보 모델 평균이라 날씨 탭 카드의 기온(기상청 우선)과 조금 다를 수 있다
        public let now: Double
        /// 어제 같은 시각 기온
        public let yesterday: Double?
        /// 내일 같은 시각 기온
        public let tomorrow: Double?
        /// 어제 같은 시각과 비교. 어제 값이 없거나 모델 묶음이 다르면 nil
        public let delta: TemperatureDelta?

        /// "어제 이맘때보다 3° 낮아요". 비교할 값이 없으면 nil
        public var text: String? {
            delta?.sentence(comparedTo: ThreeDayTemperatureModel.sameHourLabel)
        }

        /// 날씨 탭 카드 한 줄: "지금 어제보다 3° 낮아요", "지금 어제와 비슷해요". 비교할 값이 없으면 nil
        public var cardText: String? {
            delta.map { "지금 \($0.sentence(comparedTo: ThreeDayTemperatureModel.labels[0]))" }
        }
    }

    /// 늘 3개: 어제, 오늘, 내일
    public let days: [Day]
    /// 지금 기온이 없으면 nil
    public let headline: Headline?
    /// 기온이 하나도 없으면 nil
    public let chart: ThreeDayChartModel?
    /// 오늘 기온 평균에 쓴 모델 (각주)
    public let providers: [String]

    /// 하루 날씨(`around`)가 없으면(이전 서버·저장해 둔 응답) nil
    public init?(place: TodayPlace, tz: String, now: Int) {
        guard let around = place.around else { return nil }
        let clock = LocalClock(tz: tz)
        let today = clock.startOfDay(now)
        let starts = (-1...1).map { clock.addingDays($0, to: today) }
        // 순번이 아니라 날짜로 맞춘다: 저장해 둔 어제 응답이면 하루씩 밀려 있다
        let weathers = starts.map { start in around.first { $0.start == start } }
        let extremes = weathers.map { $0?.extremes(clock: clock) }

        days = (0..<3).map { index in
            let high = extremes[index]?.high
            let low = extremes[index]?.low
            var outlook = TemperatureOutlook(high: nil, low: nil)
            if index > 0, Self.sameModels(weathers[index - 1], weathers[index]) {
                let previous = extremes[index - 1]
                outlook = TemperatureOutlook(
                    high: high.flatMap { h in previous?.high.map { TemperatureDelta(today: h, baseline: $0) } },
                    low: low.flatMap { l in previous?.low.map { TemperatureDelta(today: l, baseline: $0) } },
                    label: Self.labels[index - 1]
                )
            }
            return Day(
                offset: index - 1,
                label: Self.labels[index],
                dateText: "\(clock.monthDayText(starts[index])) \(clock.weekdayText(starts[index]))",
                start: starts[index],
                weather: weathers[index],
                high: high,
                low: low,
                sky: weathers[index].flatMap(TripSky.init),
                outlook: outlook
            )
        }

        if let nowTemp = weathers[1]?.temps?.temp(at: now) {
            // 서머타임이 바뀌는 날도 같은 시계 시각으로 찾는다
            let yesterday = weathers[0]?.temps?.temp(at: clock.addingDays(-1, to: now))
            headline = Headline(
                hour: clock.hour(now),
                now: nowTemp,
                yesterday: yesterday,
                tomorrow: weathers[2]?.temps?.temp(at: clock.addingDays(1, to: now)),
                delta: Self.sameModels(weathers[0], weathers[1])
                    ? yesterday.map { TemperatureDelta(today: nowTemp, baseline: $0) }
                    : nil
            )
        } else {
            headline = nil
        }
        chart = ThreeDayChartModel(weathers: weathers, bounds: starts + [clock.addingDays(2, to: today)], now: now)
        providers = weathers[1]?.temps?.providers ?? []
    }

    /// 두 날 모두 기온이 있고 같은 모델 묶음인지
    static func sameModels(_ a: TripDayWeather?, _ b: TripDayWeather?) -> Bool {
        guard let a = a?.temps, let b = b?.temps else { return false }
        return Set(a.providers) == Set(b.providers)
    }
}

/// 3일 기온 그래프: 어제 0시부터 흐른 시간(x)에 시간별 기온을 놓는다. 서머타임 날도 실제 흐른 시간이다.
public struct ThreeDayChartModel: Sendable, Equatable {
    public struct Point: Sendable, Hashable, Identifiable {
        public var id: Int { t }
        /// 시각 (epoch 초)
        public let t: Int
        /// 어제 0시부터 흐른 시간
        public let x: Double
        public let temp: Double
        /// 빈 시간에서 선을 끊는다 (선 묶음 번호)
        public let segment: Int
    }

    public let points: [Point]
    /// 날 경계 [어제 0시, 오늘 0시, 내일 0시, 모레 0시]의 x. 서머타임 날은 23·25시간이다
    public let dayBounds: [Double]
    /// 지금의 x. 3일 밖이면 nil
    public let nowX: Double?
    /// 지금이 속한 시간 (이 점까지 지난 시간, 이 점부터 앞으로)
    public let nowHour: Int?
    /// 세로축: 모든 값에 1° 여유를 두고 정수로 넓힌다
    public let valueRange: ClosedRange<Double>

    /// - Parameter bounds: 날 경계 4개 (어제·오늘·내일·모레 0시)
    init?(weathers: [TripDayWeather?], bounds: [Int], now: Int) {
        guard let origin = bounds.first, let end = bounds.last else { return nil }
        var points: [Point] = []
        var segment = 0
        var previous: Int?
        for (index, weather) in weathers.enumerated() {
            guard let temps = weather?.temps, bounds.indices.contains(index + 1) else { continue }
            for (offset, value) in temps.temps.enumerated() {
                let t = temps.start + offset * 3600
                guard let value, bounds[index] <= t, t < bounds[index + 1] else { continue }
                if let previous, t - previous > 3600 { segment += 1 }
                previous = t
                points.append(Point(t: t, x: Double(t - origin) / 3600, temp: value, segment: segment))
            }
        }
        guard let low = points.map(\.temp).min(), let high = points.map(\.temp).max() else { return nil }
        self.points = points
        dayBounds = bounds.map { Double($0 - origin) / 3600 }
        let inRange = origin <= now && now < end
        nowX = inRange ? Double(now - origin) / 3600 : nil
        nowHour = inRange ? now - now % 3600 : nil
        valueRange = (low - 1).rounded(.down)...(high + 1).rounded(.up)
    }

    /// x가 속한 날 (0 어제, 1 오늘, 2 내일)
    public func day(at x: Double) -> Int {
        let lastDay = max(dayBounds.count - 2, 0)
        return (0...lastDay).last { dayBounds[$0] <= x } ?? 0
    }
}
