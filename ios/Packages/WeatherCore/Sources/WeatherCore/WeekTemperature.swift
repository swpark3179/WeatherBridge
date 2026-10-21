import Foundation

/// 기온 비교 화면의 7일 보기: 오늘부터 날짜마다 하루 최고·최저를 최근 3일(어제·그제·3일 전) 평균 최고·최저와 견준다.
/// 최고는 최고끼리, 최저는 최저끼리. 그 날 기온은 그 날 끝까지 닿는 예보 모델의 평균이고, 기준도 같은 모델 묶음으로
/// 만든다(여행 탭과 같은 규칙). 오늘 보기와 같은 모델 묶음인 날은 오늘 보기의 기준을 그대로 써서 두 보기의 숫자가 같다.
public struct WeekTemperatureModel: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public var id: Int { date }
        /// 현지 날짜의 0시 (epoch 초)
        public let date: Int
        /// "오늘", "내일", "목"
        public let label: String
        /// "10/23"
        public let dateText: String
        /// 그 날 최고·최저 (시간의 3/4 이상 값이 있을 때)
        public let high: Double?
        public let low: Double?
        /// 그 날과 같은 모델 묶음으로 만든 최근 3일 기준
        public let baseline: HomeBaseline?
        public let outlook: TemperatureOutlook
        /// 기온 평균에 쓴 예보 모델 수 (먼 날일수록 적다)
        public let modelCount: Int
    }

    /// 문장에 쓰는 기준 이름
    public static let label = TemperatureComparisonModel.label

    public let days: [Day]
    /// 대표 기준: 오늘 보기와 같은 기준. 없으면 처음으로 기준이 있는 날의 기준
    public let baseline: HomeBaseline?
    /// 기준이 있는 날들의 평균 최고·최저와 기준의 비교. 견줄 날이 없으면 nil
    public let outlook: TemperatureOutlook?
    /// "최근 3일보다 조금 추워요", "최근 3일보다 일교차가 커요"
    public var headline: String? { outlook?.headline }
    /// 눈에 띄는 날: "가장 추운 날 토 최저 3° (−6°)", "가장 더운 날 목 최고 24° (+5°)". 모두 비슷하면 nil
    public let detail: String?
    /// 막대 가로축: 모든 최고·최저와 기준에 1° 여유를 두고 정수로 넓힌다
    public let scale: ClosedRange<Double>

    /// 날짜별 기온이 하나도 없으면(이전 서버의 응답이거나 예보가 닿지 않으면) nil
    public init?(place: TodayPlace, tz: String, now: Int) {
        let upcoming = place.upcomingDays(now: now, tz: tz) ?? []
        guard upcoming.contains(where: { $0.temps != nil }) else { return nil }
        let clock = LocalClock(tz: tz)
        let todayStart = clock.startOfDay(now)
        let today = TemperatureComparisonModel(place: place, tz: tz, now: now)

        // 모델 묶음마다 기준은 한 번만 만든다. 오늘 보기와 같은 묶음이면 오늘 보기와 같은 기록(모델 평균)으로 만든다.
        let mixed = place.tempHistory.map { Set($0.providers) }
        var baselines: [Set<String>: HomeBaseline?] = [:]
        func baselineFor(_ providers: [String]) -> HomeBaseline? {
            let key = Set(providers)
            if let cached = baselines[key] { return cached }
            let made: HomeBaseline?
            if key == mixed, let history = place.tempHistory {
                made = HomeBaseline(history: history, tz: tz, now: now)
            } else {
                made = HomeBaseline(recent: place.recentTemps ?? [], providers: providers, tz: tz, now: now)
            }
            baselines[key] = made
            return made
        }

        var days: [Day] = []
        for day in upcoming {
            var high: Double?
            var low: Double?
            var providers = day.temps?.providers ?? []
            if day.date == todayStart, let today, today.high != nil, today.low != nil {
                // 오늘은 오늘 보기의 최고·최저와 같은 값
                high = today.high?.today
                low = today.low?.today
                providers = today.providers
            } else if let temps = day.temps {
                let hours = DayTemperature.hours(from: day.date, to: clock.addingDays(1, to: day.date))
                let values = hours.map { temps.temp(at: $0) }
                high = DayTemperature.extreme(values, hours: hours.count) { $0.max() }
                low = DayTemperature.extreme(values, hours: hours.count) { $0.min() }
            }
            guard high != nil || low != nil else { continue }
            let base = providers.isEmpty ? nil : baselineFor(providers)
            days.append(Day(
                date: day.date,
                label: clock.weekDayLabel(day.date, from: now),
                dateText: clock.monthDayText(day.date),
                high: high,
                low: low,
                baseline: base,
                outlook: TemperatureOutlook(
                    high: high.flatMap { h in base.map { TemperatureDelta(today: h, baseline: $0.high) } },
                    low: low.flatMap { l in base.map { TemperatureDelta(today: l, baseline: $0.low) } },
                    label: Self.label
                ),
                modelCount: providers.count
            ))
        }
        guard !days.isEmpty else { return nil }
        self.days = days
        baseline = today?.daily ?? days.lazy.compactMap(\.baseline).first

        // 기준이 있는 날들의 평균 최고·최저 (여행 전체 비교와 같은 방식)
        let compared = days.filter { $0.baseline != nil }
        func average(_ pick: (Day) -> (Double, Double)?) -> TemperatureDelta? {
            let pairs = compared.compactMap(pick)
            guard !pairs.isEmpty else { return nil }
            let count = Double(pairs.count)
            return TemperatureDelta(
                today: pairs.map(\.0).reduce(0, +) / count,
                baseline: pairs.map(\.1).reduce(0, +) / count
            )
        }
        let high = average { d in d.high.flatMap { h in d.baseline.map { (h, $0.high) } } }
        let low = average { d in d.low.flatMap { l in d.baseline.map { (l, $0.low) } } }
        let outlook = high == nil && low == nil ? nil : TemperatureOutlook(high: high, low: low, label: Self.label)
        self.outlook = outlook
        detail = Self.standout(compared, trend: outlook?.trend)

        let values = days.flatMap { [$0.high, $0.low, $0.baseline?.high, $0.baseline?.low].compactMap { $0 } }
        scale = ((values.min() ?? 0) - 1).rounded(.down)...((values.max() ?? 0) + 1).rounded(.up)
    }

    /// 추워지면 가장 추운 날(최저), 더워지면 가장 더운 날(최고), 그 밖이면 둘 중 차이가 큰 쪽. 그 날도 비슷하면 nil
    private static func standout(_ days: [Day], trend: TemperatureOutlook.Trend?) -> String? {
        // 같은 값이면 이른 날
        let cold = days.compactMap { d in d.outlook.low.map { (day: d, delta: $0) } }
            .min { $0.delta.today < $1.delta.today }
        let hot = days.compactMap { d in d.outlook.high.map { (day: d, delta: $0) } }
            .max { $0.delta.today < $1.delta.today }
        let useCold: Bool
        switch (trend, cold, hot) {
        case (.colder?, _?, _): useCold = true
        case (.warmer?, _, _?): useCold = false
        case let (_, cold?, hot?): useCold = abs(cold.delta.degrees) >= abs(hot.delta.degrees)
        default: useCold = cold != nil
        }
        guard let pick = useCold ? cold : hot, !pick.delta.isSimilar else { return nil }
        let value = Int(pick.delta.today.rounded())
        return useCold
            ? "가장 추운 날 \(pick.day.label) 최저 \(value)° (\(pick.delta.signedText))"
            : "가장 더운 날 \(pick.day.label) 최고 \(value)° (\(pick.delta.signedText))"
    }
}
