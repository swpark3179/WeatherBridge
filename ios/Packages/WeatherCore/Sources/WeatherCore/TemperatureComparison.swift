import Foundation

/// 기온 비교 기준: 어제, 최근 3일, 최근 7일의 같은 시각
public enum TemperatureBaseline: Int, CaseIterable, Hashable, Sendable {
    case yesterday = 1
    case threeDays = 3
    case week = 7

    /// 견줄 지난 날 수
    public var days: Int { rawValue }

    /// "어제", "최근 3일", "최근 7일"
    public var label: String {
        switch self {
        case .yesterday: "어제"
        case .threeDays: "최근 3일"
        case .week: "최근 7일"
        }
    }

    /// 값 옆에 붙이는 이름: "어제", "최근 3일 평균"
    public var valueLabel: String {
        self == .yesterday ? label : "\(label) 평균"
    }
}

/// 오늘 기온 − 기준 기온. 차이는 화면에 보이는 정수 기온끼리 빼서 숫자와 문장이 어긋나지 않게 한다.
public struct TemperatureDelta: Hashable, Sendable {
    public let today: Double
    public let baseline: Double

    public init(today: Double, baseline: Double) {
        self.today = today
        self.baseline = baseline
    }

    /// 반올림한 기온끼리의 차이 (°C)
    public var degrees: Int { Int(today.rounded()) - Int(baseline.rounded()) }

    /// 1° 이하 차이는 비슷하다고 본다
    public var isSimilar: Bool { abs(degrees) <= 1 }

    /// "−3°", "+2°", "0°"
    public var signedText: String {
        switch degrees {
        case ..<0: "−\(-degrees)°"
        case 0: "0°"
        default: "+\(degrees)°"
        }
    }

    /// "어제보다 3° 낮아요", "최근 7일 평균보다 2° 높아요", "어제와 비슷해요"
    public func sentence(_ baseline: TemperatureBaseline) -> String {
        if isSimilar {
            return baseline == .yesterday ? "어제와 비슷해요" : "\(baseline.valueLabel)과 비슷해요"
        }
        return "\(baseline.valueLabel)보다 \(abs(degrees))° \(degrees < 0 ? "낮아요" : "높아요")"
    }

    /// 체감 표현. 비슷하면 nil. 오늘 기온에 따라 말을 바꾼다: 25° 이상은 더위("조금 덜 더워요"),
    /// 15° 미만은 추위("많이 추워요", "조금 포근해요"), 그 사이는 "선선해요"·"따뜻해요". 5° 이상 차이는 "많이"("훨씬").
    public var feeling: String? {
        guard !isSimilar else { return nil }
        let colder = degrees < 0
        let strong = abs(degrees) >= 5
        let temp = Int(today.rounded())
        if temp >= 25 {
            return "\(strong ? "훨씬" : "조금") \(colder ? "덜" : "더") 더워요"
        }
        let word = temp < 15 ? (colder ? "추워요" : "포근해요") : (colder ? "선선해요" : "따뜻해요")
        return "\(strong ? "많이" : "조금") \(word)"
    }
}

/// 기온 비교 화면: 오늘(현지 0–24시) 시간별 기온과 기준 날들의 같은 시각 기온.
/// 지난 시간은 예보 모델의 지난 값, 남은 시간은 예보다.
public struct TemperatureComparisonModel: Sendable, Equatable {
    public struct Hour: Sendable, Equatable {
        public let t: Int
        /// 현지 시(0–23)
        public let hour: Int
        public let today: Double?
        /// 기준 날들의 같은 시각 평균
        public let baseline: Double?
        /// 기준 날들의 같은 시각 최저·최고 (기준이 하루면 평균과 같다)
        public let low: Double?
        public let high: Double?

        public var delta: TemperatureDelta? {
            guard let today, let baseline else { return nil }
            return TemperatureDelta(today: today, baseline: baseline)
        }
    }

    /// 하루 최고 또는 최저 기온 비교
    public struct Extreme: Sendable, Equatable {
        public let today: Double
        /// 기준 날마다 구한 최고(최저)의 평균
        public let baseline: Double

        public var delta: TemperatureDelta { TemperatureDelta(today: today, baseline: baseline) }
    }

    /// 맨 위 한 줄: 지금 시간 기준, 지금 값이 없으면 하루 최고 기온 기준
    public struct Headline: Sendable, Equatable {
        /// "지금" 또는 "최고 기온"
        public let subject: String
        public let delta: TemperatureDelta
        /// "어제보다 3° 낮아요"
        public let text: String
    }

    public let baseline: TemperatureBaseline
    /// 오늘 현지 0시부터 1시간 간격
    public let hours: [Hour]
    /// 지금 시각이 속한 시간
    public let current: Hour?
    public let high: Extreme?
    public let low: Extreme?
    /// 값이 있는 기준 날 수. 지난 기록이 모자라면 `baseline.days`보다 적다
    public let baselineDays: Int
    /// 평균에 쓴 소스
    public let providers: [String]
    /// 그래프 세로축: 모든 값에 1° 여유를 두고 정수로 넓힌다
    public let valueRange: ClosedRange<Double>
    public let headline: Headline?

    /// 하루 최고·최저는 그 날 시간의 3/4 이상 값이 있을 때만 구한다
    static let extremeCoverage = 0.75

    /// 지난 기온이 없거나, 오늘과 기준 날을 견줄 수 있는 시간이 하나도 없으면 nil
    public init?(place: TodayPlace, tz: String, now: Int, baseline: TemperatureBaseline) {
        guard let history = place.tempHistory else { return nil }
        let clock = LocalClock(tz: tz)
        let dayStart = clock.startOfDay(now)
        let dayEnd = clock.addingDays(1, to: dayStart)
        let times = Array(stride(from: (dayStart + 3599) / 3600 * 3600, to: dayEnd, by: 3600))
        // 기준 날마다, 오늘 각 시간과 같은 시계 시각의 기온
        let past = (1...baseline.days).map { day in
            times.map { history.temp(at: clock.addingDays(-day, to: $0)) }
        }
        let hours = times.enumerated().map { index, t in
            let values = past.compactMap { $0[index] }
            return Hour(
                t: t,
                hour: clock.hour(t),
                today: history.temp(at: t),
                baseline: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                low: values.min(),
                high: values.max()
            )
        }
        guard hours.contains(where: { $0.delta != nil }) else { return nil }

        let needed = Int((Double(times.count) * Self.extremeCoverage).rounded(.up))
        func extreme(_ pick: ([Double]) -> Double?) -> Extreme? {
            let todayValues = hours.compactMap(\.today)
            guard todayValues.count >= needed, let value = pick(todayValues) else { return nil }
            let perDay = past.compactMap { day -> Double? in
                let values = day.compactMap { $0 }
                return values.count >= needed ? pick(values) : nil
            }
            guard !perDay.isEmpty else { return nil }
            return Extreme(today: value, baseline: perDay.reduce(0, +) / Double(perDay.count))
        }
        let current = hours.first { $0.t <= now && now < $0.t + 3600 }
        let high = extreme { $0.max() }
        let values = hours.flatMap { [$0.today, $0.low, $0.high].compactMap { $0 } }

        self.baseline = baseline
        self.hours = hours
        self.current = current
        self.high = high
        low = extreme { $0.min() }
        baselineDays = past.filter { day in day.contains { $0 != nil } }.count
        providers = history.providers
        valueRange = ((values.min() ?? 0) - 1).rounded(.down)...((values.max() ?? 0) + 1).rounded(.up)
        if let delta = current?.delta {
            headline = Headline(subject: "지금", delta: delta, text: delta.sentence(baseline))
        } else if let high {
            headline = Headline(subject: "최고 기온", delta: high.delta, text: high.delta.sentence(baseline))
        } else {
            headline = nil
        }
    }
}
