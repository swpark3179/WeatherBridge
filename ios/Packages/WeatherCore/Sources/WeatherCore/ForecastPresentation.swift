import Foundation

/// 화면에 보여줄 소스 이름과 순서
public enum ForecastSourceInfo {
    /// 소스(provider) 표시 이름. 모르는 소스는 ID를 그대로 쓴다.
    public static func label(_ provider: String) -> String {
        switch provider {
        case "kma_short": "기상청"
        case "om_ecmwf": "ECMWF(유럽)"
        case "om_gfs": "GFS(미국)"
        case "om_icon": "ICON(독일)"
        default: provider
        }
    }

    /// 기상청을 맨 앞에, 나머지는 이름순
    public static func sorted(_ providers: some Sequence<String>) -> [String] {
        let order = ["kma_short", "om_ecmwf", "om_gfs", "om_icon"]
        return Set(providers).sorted { a, b in
            let ia = order.firstIndex(of: a) ?? order.count
            let ib = order.firstIndex(of: b) ?? order.count
            return ia == ib ? a < b : ia < ib
        }
    }
}

/// 장소 시간대 기준의 시각 계산
public struct LocalClock: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(tz: String) {
        timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "Asia/Seoul")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    public func hour(_ epoch: Int) -> Int {
        calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    /// 그 날 현지 0시 (epoch 초)
    public func startOfDay(_ epoch: Int) -> Int {
        Int(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(epoch))).timeIntervalSince1970)
    }

    /// `days`일 뒤(음수면 앞)의 같은 현지 시각. 서머타임이 바뀌는 날도 시계 시각을 맞춘다.
    public func addingDays(_ days: Int, to epoch: Int) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        guard let moved = calendar.date(byAdding: .day, value: days, to: date) else { return epoch + days * 86400 }
        return Int(moved.timeIntervalSince1970)
    }

    /// 0 = 오늘, 1 = 내일 …
    public func dayOffset(_ epoch: Int, from now: Int) -> Int {
        let a = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now)))
        let b = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(epoch)))
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// "오늘 15–18시", "내일 3시", "모레 9–12시"
    public func windowText(start: Int, end: Int, now: Int) -> String {
        "\(dayLabel(start, from: now)) \(spanText(start: start, end: end))"
    }

    /// 오늘이면 날짜를 뺀다: "15–18시", "내일 3시"
    public func compactWindowText(start: Int, end: Int, now: Int) -> String {
        dayOffset(start, from: now) < 1 ? spanText(start: start, end: end) : windowText(start: start, end: end, now: now)
    }

    /// 날짜 없이 시만: "15–18시", "3시"
    public func spanText(start: Int, end: Int) -> String {
        let startHour = hour(start)
        let endHour = hour(end)
        let shownEnd = endHour == 0 ? 24 : endHour
        return end - start <= 3600 || (shownEnd - startHour) == 1 ? "\(startHour)시" : "\(startHour)–\(shownEnd)시"
    }

    /// 시:분 범위: "08:00 – 10:00". 자정에 끝나면 "24:00"
    public func rangeText(start: Int, end: Int) -> String {
        let endHour = hour(end)
        let shownEnd = endHour == 0 && minute(end) == 0 ? 24 : endHour
        return String(format: "%02d:%02d – %02d:%02d", hour(start), minute(start), shownEnd, minute(end))
    }

    public func minute(_ epoch: Int) -> Int {
        calendar.component(.minute, from: Date(timeIntervalSince1970: TimeInterval(epoch)))
    }

    /// "08:30"
    public func timeText(_ epoch: Int) -> String {
        String(format: "%02d:%02d", hour(epoch), minute(epoch))
    }

    /// "오늘", "내일", "모레", "3일 뒤"
    public func dayLabel(_ epoch: Int, from now: Int) -> String {
        Self.dayName(dayOffset(epoch, from: now))
    }

    /// [from, to) 안에서 `days`(ISO 요일, 1=월 … 7=일) 날짜의 `time` 시각들
    public func occurrences(of time: ClockTime, days: [Int], from: Int, to: Int) -> [Int] {
        var result: [Int] = []
        var day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(from)))
        while Int(day.timeIntervalSince1970) < to {
            if let date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) {
                let epoch = Int(date.timeIntervalSince1970)
                // Calendar 요일은 1=일요일 … 7=토요일
                let weekday = calendar.component(.weekday, from: date)
                let iso = weekday == 1 ? 7 : weekday - 1
                if epoch >= from, epoch < to, days.contains(iso) {
                    result.append(epoch)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static func dayName(_ offset: Int) -> String {
        switch offset {
        case ..<1: "오늘"
        case 1: "내일"
        case 2: "모레"
        default: "\(offset)일 뒤"
        }
    }
}

extension TodayPlace {
    /// 지금 시각이 속한 시간부터 `hours`개
    public func upcoming(hours: Int, now: Int) -> [TodayHour] {
        let currentHour = now - now % 3600
        return Array(self.hours.filter { $0.t >= currentHour }.prefix(hours))
    }

    /// 앞으로 `hours`시간 안에 걸친 비 구간 전부, 이른 순
    public func upcomingWindows(within hours: Int = 24, now: Int) -> [RainWindow] {
        windows.filter { $0.end > now && $0.start < now + hours * 3600 }.sorted { $0.start < $1.start }
    }

    /// 구간 안에서 종합 강수확률이 가장 높은 시간 (같으면 이른 시간)
    public func peakHour(of window: RainWindow) -> TodayHour? {
        var peak: TodayHour?
        for hour in hours where window.contains(hour.t) {
            if (hour.consensus ?? 0) > (peak?.consensus ?? -1) { peak = hour }
        }
        return peak
    }

    /// 구간이 끝난 뒤: "10시부터 그쳐요 · 18시에 다시 와요", "21시부터 그쳐요 · 이후 비 소식 없음"
    public func clearingText(after window: RainWindow, now: Int, tz: String) -> String {
        let clock = LocalClock(tz: tz)
        let stop = "\(dayPrefix(window.end, now: now, clock: clock))\(clock.hour(window.end))시부터 그쳐요"
        guard let next = windows.filter({ $0.start >= window.end }).min(by: { $0.start < $1.start }) else {
            return "\(stop) · 이후 비 소식 없음"
        }
        return "\(stop) · \(dayPrefix(next.start, now: now, clock: clock))\(clock.hour(next.start))시에 다시 와요"
    }

    /// 앞으로 `hours`시간 중 예보끼리 의견이 갈리는 연속 시간
    public func splitSpans(within hours: Int = 24, now: Int) -> [TimeSpan] {
        var spans: [TimeSpan] = []
        for hour in upcoming(hours: hours, now: now) where hour.split {
            if let last = spans.last, last.end == hour.t {
                spans[spans.count - 1].end = hour.t + 3600
            } else {
                spans.append(TimeSpan(start: hour.t, end: hour.t + 3600))
            }
        }
        return spans
    }

    /// 앞으로 `hours`시간의 최저·최고 기온
    public func temperatureRange(hours: Int = 24, now: Int) -> (low: Double, high: Double)? {
        let temps = upcoming(hours: hours, now: now).compactMap(\.temp)
        guard let low = temps.min(), let high = temps.max() else { return nil }
        return (low, high)
    }

    private func dayPrefix(_ epoch: Int, now: Int, clock: LocalClock) -> String {
        clock.dayOffset(epoch, from: now) < 1 ? "" : "\(clock.dayLabel(epoch, from: now)) "
    }
}

extension RainWindow {
    public func contains(_ epoch: Int) -> Bool {
        start <= epoch && epoch < end
    }

    /// 시간 단위 길이
    public var hourCount: Int { (end - start) / 3600 }
}

/// [start, end) 시각 구간 (epoch 초)
public struct TimeSpan: Hashable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

extension TodayResponse {
    /// 오늘 화면 맨 위 요약. 예: "집 8–10시, 18–21시 비" + "회사 비 소식 없음 (최대 13%)"
    public func overview(now: Int, hours: Int = 24) -> TodayOverview {
        let clock = LocalClock(tz: tz)
        var rainy: [String] = []
        var dry: [(name: String, maxPop: Int)] = []
        for place in places {
            let windows = place.upcomingWindows(within: hours, now: now)
            if windows.isEmpty {
                dry.append((place.name, place.upcoming(hours: hours, now: now).compactMap(\.consensus).max() ?? 0))
            } else {
                let spans = windows.map { clock.compactWindowText(start: $0.start, end: $0.end, now: now) }
                rainy.append("\(place.name) \(spans.joined(separator: ", ")) 비")
            }
        }
        if rainy.isEmpty {
            let detail = dry.map { "\($0.name) 최대 \($0.maxPop)%" }.joined(separator: " · ")
            return TodayOverview(headline: "앞으로 \(hours)시간 비 소식 없음", detail: detail.isEmpty ? nil : detail, isRainy: false)
        }
        let detail = dry.map { "\($0.name) 비 소식 없음 (최대 \($0.maxPop)%)" }.joined(separator: " · ")
        return TodayOverview(headline: rainy.joined(separator: " · "), detail: detail.isEmpty ? nil : detail, isRainy: true)
    }
}

public struct TodayOverview: Hashable, Sendable {
    public let headline: String
    public let detail: String?
    public let isRainy: Bool
}

/// 오늘 카드의 24시간 막대: 막대, 비 구간 괄호, 시각 눈금, 지금·자정·출근 위치.
/// 위치는 막대 칸 단위(0 = 첫 막대의 왼쪽 끝, `bars.count` = 오른쪽 끝)다.
public struct RainTimelineModel: Sendable, Equatable {
    public struct Bar: Sendable, Equatable {
        public let t: Int
        public let pop: Int
        public let level: RainLevel
    }

    public struct Bracket: Sendable, Equatable {
        /// 이 괄호가 가리키는 `upcomingWindows`의 순번
        public let window: Int
        public let start: Double
        public let end: Double
        /// "8–10시"
        public let label: String
    }

    public struct Tick: Sendable, Equatable {
        public let position: Double
        /// "9시". 날짜가 바뀌는 0시는 "내일"
        public let label: String
        public let isDayStart: Bool
    }

    public let bars: [Bar]
    public let brackets: [Bracket]
    public let ticks: [Tick]
    public let now: Double
    /// 날짜가 바뀌는 위치 (없으면 nil)
    public let midnight: Double?
    public let commutes: [Double]

    public init(place: TodayPlace, tz: String, now: Int, hours: Int = 24, commuteTimes: [Int] = []) {
        let clock = LocalClock(tz: tz)
        let slice = place.upcoming(hours: hours, now: now)
        bars = slice.map { Bar(t: $0.t, pop: $0.consensus ?? 0, level: RainLevel(pop: $0.consensus ?? 0)) }
        let origin = slice.first?.t ?? now - now % 3600
        let count = Double(slice.count)
        func position(_ epoch: Int) -> Double { Double(epoch - origin) / 3600 }

        brackets = place.upcomingWindows(within: hours, now: now).enumerated().compactMap { index, w in
            let start = max(0, position(w.start))
            let end = min(count, position(w.end))
            guard end > start else { return nil }
            return Bracket(window: index, start: start, end: end, label: clock.spanText(start: w.start, end: w.end))
        }
        ticks = slice.enumerated().compactMap { index, hour in
            let h = clock.hour(hour.t)
            guard h % 3 == 0 else { return nil }
            let dayStart = h == 0 && index > 0
            return Tick(position: Double(index), label: dayStart ? clock.dayLabel(hour.t, from: now) : "\(h)시", isDayStart: dayStart)
        }
        self.now = min(count, max(0, position(now)))
        midnight = slice.dropFirst().first { clock.hour($0.t) == 0 }.map { position($0.t) }
        commutes = commuteTimes.map(position).filter { $0 >= 0 && $0 < count }
    }
}

/// 비교 화면 그래프: 종합·예보별 선, 예보 범위 띠, 비 구간, 의견이 갈리는 시간과 그 설명
public struct CompareChartModel: Sendable, Equatable {
    public struct Disagreement: Sendable, Equatable {
        public let span: TimeSpan
        /// 종합에서 평균적으로 가장 멀리 떨어진 예보
        public let provider: String
        /// 종합보다 높게 봤으면 true
        public let isHigh: Bool
        /// 그 예보가 구간 안에서 가장 높게(낮게) 본 값
        public let value: Int
        /// 구간 안 예보끼리 최대 차이 (최고 − 최저)
        public let spread: Int
        /// "내일 13–16시 · 차이 50%p"
        public let when: String
        /// "가장 높게 본 예보 GFS(미국) 70%"
        public let detail: String
    }

    public struct Tick: Sendable, Equatable {
        public let t: Int
        /// "9시". 날짜가 바뀌는 0시는 "내일"
        public let label: String
        public let isDayStart: Bool
    }

    public let hours: [TodayHour]
    /// 기상청 먼저, 나머지는 이름순 (`HeatmapModel`과 같다)
    public let providers: [String]
    public let windows: [RainWindow]
    public let splits: [TimeSpan]
    public let disagreements: [Disagreement]
    /// 24시간 이하면 3시간, 더 길면 6시간 간격
    public let ticks: [Tick]

    public init(place: TodayPlace, tz: String, now: Int, hours: Int = 24) {
        let clock = LocalClock(tz: tz)
        let slice = place.upcoming(hours: hours, now: now)
        self.hours = slice
        providers = ForecastSourceInfo.sorted(place.sources.map(\.provider) + slice.flatMap { $0.providers.keys })
        windows = place.upcomingWindows(within: hours, now: now)
        splits = place.splitSpans(within: hours, now: now)

        let step = hours <= 24 ? 3 : 6
        ticks = slice.enumerated().compactMap { index, hour in
            let h = clock.hour(hour.t)
            guard h % step == 0 else { return nil }
            let dayStart = h == 0 && index > 0
            return Tick(t: hour.t, label: dayStart ? clock.dayLabel(hour.t, from: now) : "\(h)시", isDayStart: dayStart)
        }

        let providers = self.providers
        disagreements = splits.compactMap { span in
            let inSpan = slice.filter { span.start <= $0.t && $0.t < span.end }
            var best: (provider: String, deviation: Double)?
            for provider in providers {
                let deviations = inSpan.compactMap { hour -> Double? in
                    guard let value = hour.providers[provider], let consensus = hour.consensus else { return nil }
                    return Double(value - consensus)
                }
                guard !deviations.isEmpty else { continue }
                let mean = deviations.reduce(0, +) / Double(deviations.count)
                if best == nil || abs(mean) > abs(best?.deviation ?? 0) {
                    best = (provider, mean)
                }
            }
            guard let best else { return nil }
            let isHigh = best.deviation > 0
            let values = inSpan.compactMap { $0.providers[best.provider] }
            let value = (isHigh ? values.max() : values.min()) ?? 0
            let spread = inSpan.compactMap { hour -> Int? in
                guard let low = hour.min, let high = hour.max else { return nil }
                return high - low
            }.max() ?? 0
            return Disagreement(
                span: span,
                provider: best.provider,
                isHigh: isHigh,
                value: value,
                spread: spread,
                when: "\(clock.compactWindowText(start: span.start, end: span.end, now: now)) · 차이 \(spread)%p",
                detail: "\(isHigh ? "가장 높게" : "가장 낮게") 본 예보 \(ForecastSourceInfo.label(best.provider)) \(value)%"
            )
        }
    }
}

/// 비교 화면 히트맵: 행 = 종합 + 소스, 열 = 시간
public struct HeatmapModel: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        /// "consensus" 또는 소스 ID
        public let id: String
        public let label: String
        public let cells: [Int?]
        public let isConsensus: Bool
    }

    public struct Column: Sendable, Equatable, Identifiable {
        public var id: Int { t }
        public let t: Int
        public let hour: Int
        /// 날짜가 바뀌는 첫 열이면 "내일" 같은 표시
        public let dayLabel: String?
        public let split: Bool
        /// "3/4" (참여 계열이 없으면 nil)
        public let agreement: String?
    }

    public let columns: [Column]
    public let rows: [Row]

    public init(place: TodayPlace, tz: String, now: Int, hours: Int = 48) {
        let clock = LocalClock(tz: tz)
        let slice = place.upcoming(hours: hours, now: now)
        var previousDay: Int?
        columns = slice.map { h in
            let day = clock.dayOffset(h.t, from: now)
            defer { previousDay = day }
            return Column(
                t: h.t,
                hour: clock.hour(h.t),
                dayLabel: day != previousDay && previousDay != nil ? LocalClock.dayName(day) : nil,
                split: h.split,
                agreement: h.total > 0 ? "\(h.agreeing)/\(h.total)" : nil
            )
        }
        let providers = ForecastSourceInfo.sorted(
            place.sources.map(\.provider) + slice.flatMap { $0.providers.keys }
        )
        rows = [Row(id: "consensus", label: "종합", cells: slice.map(\.consensus), isConsensus: true)]
            + providers.map { p in
                Row(id: p, label: ForecastSourceInfo.label(p), cells: slice.map { $0.providers[p] }, isConsensus: false)
            }
    }
}
