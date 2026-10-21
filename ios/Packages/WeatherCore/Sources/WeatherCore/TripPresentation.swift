import Foundation

/// 여행 날 하늘 (장면·아이콘). 비·눈은 그 날 비 소식으로, 나머지는 낮 운량으로 정한다.
public enum TripSky: String, Hashable, Sendable, CaseIterable {
    case clear, partlyCloudy, cloudy, rain, snow

    /// 비 오는 날 하루 적설이 이 이상(cm)이면 눈
    public static let snowCm = 0.5

    /// 비 소식도 운량도 없으면 nil
    public init?(_ weather: TripDayWeather) {
        if let rain = weather.rain, rain.rainy {
            self = (weather.snowCm ?? 0) >= Self.snowCm ? .snow : .rain
            return
        }
        guard let cloud = weather.cloud else { return nil }
        self = cloud < 30 ? .clear : cloud < 70 ? .partlyCloudy : .cloudy
    }

    /// "맑음", "구름 조금", "흐림", "비", "눈"
    public var label: String {
        switch self {
        case .clear: "맑음"
        case .partlyCloudy: "구름 조금"
        case .cloudy: "흐림"
        case .rain: "비"
        case .snow: "눈"
        }
    }
}

/// "지금" 기준: 집의 최근 3일(어제·그제·3일 전) 하루 최고·최저의 평균.
/// 비교할 날과 같은 예보 모델 묶음으로 만들어, 모델마다 다른 치우침이 차이에서 빠진다.
public struct HomeBaseline: Hashable, Sendable {
    /// 견줄 지난 날 수
    public static let days = 3

    public let high: Double
    public let low: Double
    /// 값이 있는 날 수. 지난 기록이 모자라면 `days`보다 적다
    public let dayCount: Int
    /// 평균에 쓴 모델
    public let providers: [String]

    /// `providers`가 nil이면 `recent`의 모든 모델. 원하는 모델의 기록이 하나라도 없거나, 하루 최고·최저를
    /// 구할 만큼 값이 있는 날이 없으면 nil
    public init?(recent: [TemperatureHistory], providers wanted: [String]? = nil, tz: String, now: Int) {
        let models = wanted ?? recent.compactMap(\.providers.first)
        let series = models.compactMap { model in recent.first { $0.providers == [model] } }
        guard !series.isEmpty, series.count == models.count else { return nil }

        let clock = LocalClock(tz: tz)
        let today = clock.startOfDay(now)
        var highs: [Double] = []
        var lows: [Double] = []
        for back in 1...Self.days {
            let start = clock.addingDays(-back, to: today)
            let hours = DayTemperature.hours(from: start, to: clock.addingDays(1, to: start))
            // 모든 모델에 값이 있는 시간만 평균한다 (서버 tempHistory와 같은 규칙)
            let values = hours.map { t -> Double? in
                let temps = series.compactMap { $0.temp(at: t) }
                return temps.count == series.count ? temps.reduce(0, +) / Double(temps.count) : nil
            }
            if let high = DayTemperature.extreme(values, hours: hours.count, { $0.max() }) { highs.append(high) }
            if let low = DayTemperature.extreme(values, hours: hours.count, { $0.min() }) { lows.append(low) }
        }
        guard !highs.isEmpty, !lows.isEmpty else { return nil }
        high = highs.reduce(0, +) / Double(highs.count)
        low = lows.reduce(0, +) / Double(lows.count)
        dayCount = highs.count
        providers = models
    }
}

/// 그 날(또는 여행 전체) 기온과 "지금"(집 최근 3일)의 비교: 최고는 최고끼리, 최저는 최저끼리.
public struct TemperatureOutlook: Hashable, Sendable {
    /// 기준을 부르는 말
    public static let nowLabel = "지금"

    public let high: TemperatureDelta?
    public let low: TemperatureDelta?
    /// "지금보다 조금 추워요", "지금보다 일교차가 커요", "지금과 비슷해요". 비교할 값이 없으면 nil
    public let headline: String?

    public init(high: TemperatureDelta?, low: TemperatureDelta?) {
        self.high = high
        self.low = low
        headline = Self.headline(high: high, low: low)
    }

    /// 최고·최저가 반대로 움직이면 일교차로 말하고, 아니면 하루 가운데 값(최고·최저 평균)의 체감으로 말한다.
    static func headline(high: TemperatureDelta?, low: TemperatureDelta?) -> String? {
        let label = nowLabel
        let similar = "\(Hangul.withAnd(label)) 비슷해요"
        switch (high, low) {
        case (nil, nil):
            return nil
        case (let one?, nil), (nil, let one?):
            return one.feeling.map { "\(label)보다 \($0)" } ?? similar
        case let (high?, low?):
            if !high.isSimilar, !low.isSimilar, (high.degrees > 0) != (low.degrees > 0) {
                return "\(label)보다 일교차가 \(high.degrees > 0 ? "커요" : "작아요")"
            }
            let middle = TemperatureDelta(
                today: (high.today + low.today) / 2,
                baseline: (high.baseline + low.baseline) / 2
            )
            let feeling = middle.feeling ?? (high.isSimilar ? low : high).feeling
            return feeling.map { "\(label)보다 \($0)" } ?? similar
        }
    }
}

/// 한 장소의 여행 날 하루
public struct TripDaySummary: Hashable, Sendable {
    public let weather: TripDayWeather?
    /// 그 날 최고·최저 (시간의 3/4 이상 값이 있을 때)
    public let high: Double?
    public let low: Double?
    /// 그 날과 같은 모델 묶음으로 만든 집 기준
    public let baseline: HomeBaseline?
    public let outlook: TemperatureOutlook
    public let sky: TripSky?

    public var rain: TripRain? { weather?.rain }
    /// 기온 평균에 쓴 예보 모델 수 (먼 날일수록 적다)
    public var modelCount: Int { weather?.temps?.providers.count ?? 0 }
    /// 보여줄 예보가 하나라도 있는지
    public var hasForecast: Bool { high != nil || low != nil || rain != nil || sky != nil }

    /// - Parameter baseline: 모델 묶음 → 집 기준 (TripModel이 묶음마다 한 번만 만든다)
    init(weather: TripDayWeather?, clock: LocalClock, baseline: ([String]) -> HomeBaseline?) {
        self.weather = weather
        var high: Double?
        var low: Double?
        if let weather, let temps = weather.temps {
            let hours = DayTemperature.hours(from: weather.start, to: clock.addingDays(1, to: weather.start))
            let values = hours.map { temps.temp(at: $0) }
            high = DayTemperature.extreme(values, hours: hours.count) { $0.max() }
            low = DayTemperature.extreme(values, hours: hours.count) { $0.min() }
        }
        self.high = high
        self.low = low
        let base = weather?.temps.flatMap { baseline($0.providers) }
        self.baseline = base
        outlook = TemperatureOutlook(
            high: high.flatMap { h in base.map { TemperatureDelta(today: h, baseline: $0.high) } },
            low: low.flatMap { l in base.map { TemperatureDelta(today: l, baseline: $0.low) } }
        )
        sky = weather.flatMap(TripSky.init)
    }
}

/// 여행 화면: 상태, 기간, 날짜별 목적지·집 요약
public struct TripModel: Sendable, Identifiable {
    /// 출발 이만큼 전부터 서버가 예보를 받는다 (서버 TRIP_LEAD_DAYS)
    public static let leadDays = 15

    public enum Status: Hashable, Sendable {
        /// 출발까지 남은 날 (집 날짜 기준, 0이면 오늘 출발)
        case upcoming(daysLeft: Int)
        /// 여행 n일째 / 전체 날 수 (목적지 날짜 기준)
        case ongoing(day: Int, of: Int)
        case ended
    }

    public struct Day: Hashable, Sendable, Identifiable {
        public var id: LocalDate { date }
        public let date: LocalDate
        /// 여행 n일째 (1부터)
        public let ordinal: Int
        /// "10/25 토"
        public let label: String
        /// 목적지 기준 "오늘", "내일", "모레". 그 밖이면 nil
        public let relative: String?
        public let destination: TripDaySummary
        public let home: TripDaySummary
    }

    public var id: String { trip.id }
    public let trip: Trip
    public let homeName: String?
    public let status: Status
    /// "10/25 토 – 10/28 화 · 3박 4일"
    public let periodText: String
    /// "D-3", "오늘 출발", "여행 중 2/4일", "지난 여행"
    public let badge: String
    public let days: [Day]
    /// 기준 띠: 집 최근 3일 (받은 모든 모델의 평균)
    public let baseline: HomeBaseline?
    /// 아직 먼 여행: 예보를 받기 시작하는 날 (목적지 날짜)
    public let forecastFrom: LocalDate?
    /// 여행 전체: 예보가 있는 날들의 평균 최고·최저와 지금 비교
    public let outlook: TemperatureOutlook?
    /// 비(눈 포함) 예상 날 수
    public let rainyDays: Int
    /// 목록 카드 한 줄: "지금보다 조금 추워요 · 비 2일", "예보는 11/1부터"
    public let summaryLine: String?

    public init(trip: Trip, home: TripHome?, now: Int) {
        self.trip = trip
        homeName = home?.name
        let destClock = LocalClock(tz: trip.tz)
        let homeClock = LocalClock(tz: home?.tz ?? trip.tz)
        let destToday = destClock.localDate(now)
        let homeToday = homeClock.localDate(now)
        let total = trip.startDate.days(to: trip.endDate) + 1

        let status: Status
        if trip.endDate < destToday {
            status = .ended
        } else if trip.startDate <= destToday {
            status = .ongoing(day: trip.startDate.days(to: destToday) + 1, of: total)
        } else {
            status = .upcoming(daysLeft: max(0, homeToday.days(to: trip.startDate)))
        }
        self.status = status
        badge = switch status {
        case .upcoming(daysLeft: 0): "오늘 출발"
        case let .upcoming(daysLeft): "D-\(daysLeft)"
        case let .ongoing(day, of): "여행 중 \(day)/\(of)일"
        case .ended: "지난 여행"
        }
        let dayLabel = { (d: LocalDate) in "\(d.monthDayText) \(d.weekdayText)" }
        periodText = total == 1
            ? "\(dayLabel(trip.startDate)) · 당일"
            : "\(dayLabel(trip.startDate)) – \(dayLabel(trip.endDate)) · \(total - 1)박 \(total)일"

        // 모델 묶음마다 집 기준은 한 번만 만든다
        var baselines: [[String]: HomeBaseline?] = [:]
        let baselineFor = { (providers: [String]) -> HomeBaseline? in
            guard let home else { return nil }
            if let cached = baselines[providers] { return cached }
            let made = HomeBaseline(recent: home.recent, providers: providers, tz: home.tz, now: now)
            baselines[providers] = made
            return made
        }
        let days = trip.days.map { day in
            let offset = destToday.days(to: day.date)
            return Day(
                date: day.date,
                ordinal: trip.startDate.days(to: day.date) + 1,
                label: dayLabel(day.date),
                relative: (0...2).contains(offset) ? LocalClock.dayName(offset) : nil,
                destination: TripDaySummary(weather: day.destination, clock: destClock, baseline: baselineFor),
                home: TripDaySummary(weather: day.home, clock: homeClock, baseline: baselineFor)
            )
        }
        self.days = days
        baseline = home.flatMap { HomeBaseline(recent: $0.recent, tz: $0.tz, now: now) }

        let forecastFrom = !trip.watched && status != .ended ? trip.startDate.adding(days: -Self.leadDays) : nil
        self.forecastFrom = forecastFrom
        let compared = days.map(\.destination).filter { $0.baseline != nil }
        func average(_ pick: (TripDaySummary) -> (Double, Double)?) -> TemperatureDelta? {
            let pairs = compared.compactMap(pick)
            guard !pairs.isEmpty else { return nil }
            let count = Double(pairs.count)
            return TemperatureDelta(
                today: pairs.map(\.0).reduce(0, +) / count,
                baseline: pairs.map(\.1).reduce(0, +) / count
            )
        }
        let high = average { s in s.high.flatMap { h in s.baseline.map { (h, $0.high) } } }
        let low = average { s in s.low.flatMap { l in s.baseline.map { (l, $0.low) } } }
        let outlook = high == nil && low == nil ? nil : TemperatureOutlook(high: high, low: low)
        self.outlook = outlook
        let rainyDays = days.filter { $0.destination.rain?.rainy == true }.count
        self.rainyDays = rainyDays
        let snowyDays = days.filter { $0.destination.sky == .snow }.count

        if status == .ended {
            summaryLine = nil
        } else if let forecastFrom {
            summaryLine = "예보는 \(forecastFrom.monthDayText)부터"
        } else {
            let rainText = snowyDays > 0
                ? (rainyDays > snowyDays ? "비·눈 \(rainyDays)일" : "눈 \(snowyDays)일")
                : rainyDays > 0 ? "비 \(rainyDays)일" : nil
            let parts = [outlook?.headline, rainText].compactMap { $0 }
            summaryLine = parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}

extension TripsResponse {
    public func models(now: Int) -> [TripModel] {
        trips.map { TripModel(trip: $0, home: home, now: now) }
    }
}

/// 여행 기온 그래프: 목적지·집의 시간별 기온을 첫날 현지 0시부터의 시간(x)으로 나란히 놓는다.
/// 시간대가 달라도(+5:30처럼 현지 자정이 정시가 아니어도) 같은 축의 같은 시계 시각에 놓인다.
public struct TripChartModel: Sendable, Equatable {
    public enum Series: String, Hashable, Sendable {
        case destination, home
    }

    public struct Point: Hashable, Sendable, Identifiable {
        public var id: String { "\(series.rawValue)-\(x)" }
        public let series: Series
        /// 날짜 순서 (0부터). 날짜마다 선을 따로 그려 빈 날을 잇지 않는다
        public let day: Int
        /// 첫날 현지 0시부터 시간
        public let x: Double
        public let temp: Double

        /// 선 묶음 이름: "destination-0"
        public var line: String { "\(series.rawValue)-\(day)" }
    }

    public let points: [Point]
    public let dayCount: Int
    /// 기준 띠 (집 최근 3일 평균 최저 ~ 최고)
    public let baseline: HomeBaseline?
    /// 세로축: 모든 값과 기준에 1° 여유를 두고 정수로 넓힌다
    public let valueRange: ClosedRange<Double>

    /// 기온이 하나도 없으면 nil
    public init?(model: TripModel) {
        var points: [Point] = []
        for (index, day) in model.days.enumerated() {
            for (series, summary) in [(Series.destination, day.destination), (.home, day.home)] {
                guard let weather = summary.weather, let temps = weather.temps else { continue }
                for (i, temp) in temps.temps.enumerated() {
                    guard let temp else { continue }
                    let t = temps.start + i * 3600
                    points.append(Point(
                        series: series,
                        day: index,
                        x: Double(index * 24) + Double(t - weather.start) / 3600,
                        temp: temp
                    ))
                }
            }
        }
        guard !points.isEmpty else { return nil }
        self.points = points
        dayCount = model.days.count
        baseline = model.baseline
        let values = points.map(\.temp) + [model.baseline?.high, model.baseline?.low].compactMap { $0 }
        valueRange = ((values.min() ?? 0) - 1).rounded(.down)...((values.max() ?? 0) + 1).rounded(.up)
    }

    /// x가 속한 날짜 순서
    public func day(at x: Double) -> Int {
        min(max(Int(x / 24), 0), max(dayCount - 1, 0))
    }
}
