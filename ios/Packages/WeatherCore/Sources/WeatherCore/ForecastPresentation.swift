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

    /// 그 시각의 현지 날짜
    public func localDate(_ epoch: Int) -> LocalDate {
        LocalDate(Date(timeIntervalSince1970: TimeInterval(epoch)), calendar: calendar)
    }

    /// 그 날짜의 현지 0시 (epoch 초)
    public func startOfDay(_ date: LocalDate) -> Int {
        Int(date.date(in: calendar).timeIntervalSince1970)
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

    /// "월" … "일"
    public func weekdayText(_ epoch: Int) -> String {
        // Calendar 요일은 1=일요일 … 7=토요일
        let names = ["일", "월", "화", "수", "목", "금", "토"]
        return names[calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval(epoch))) - 1]
    }

    /// "10/23"
    public func monthDayText(_ epoch: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }

    /// 7일 보기의 날짜 이름: "오늘", "내일", 그 뒤로는 요일("목")
    public func weekDayLabel(_ epoch: Int, from now: Int) -> String {
        let offset = dayOffset(epoch, from: now)
        return offset < 2 ? Self.dayName(offset) : weekdayText(epoch)
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

    /// 7일 보기: 오늘부터 최대 7일. 저장해 둔 지난 응답이면 이미 지난 날은 뺀다. 이전 서버의 응답이면 nil
    public func upcomingDays(now: Int, tz: String) -> [TodayDay]? {
        guard let days else { return nil }
        let today = LocalClock(tz: tz).startOfDay(now)
        return Array(days.filter { $0.date >= today }.prefix(7))
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
        return .summary(rainy: rainy, dry: dry, period: "\(hours)시간")
    }

    /// 7일 보기 맨 위 요약. 예: "집 내일·토 비 · 회사 토 비" + "…", "앞으로 7일 비 소식 없음" + "집 최대 25% · 회사 최대 20%"
    public func weekOverview(now: Int) -> TodayOverview {
        let clock = LocalClock(tz: tz)
        var rainy: [String] = []
        var dry: [(name: String, maxPop: Int)] = []
        for place in places {
            guard let days = place.upcomingDays(now: now, tz: tz), !days.isEmpty else { continue }
            let rainyDays = days.filter(\.rainy)
            if rainyDays.isEmpty {
                dry.append((place.name, days.map(\.pop).max() ?? 0))
            } else {
                rainy.append("\(place.name) \(rainyDays.map { clock.weekDayLabel($0.date, from: now) }.joined(separator: "·")) 비")
            }
        }
        if rainy.isEmpty && dry.isEmpty {
            return TodayOverview(headline: "7일 예보를 받는 중이에요", detail: "당겨서 새로고침해 주세요", isRainy: false)
        }
        return .summary(rainy: rainy, dry: dry, period: "7일")
    }
}

public struct TodayOverview: Hashable, Sendable {
    public let headline: String
    public let detail: String?
    public let isRainy: Bool

    /// 비 오는 장소를 모두 나열하고, 나머지는 최대 확률과 함께 덧붙인다
    static func summary(rainy: [String], dry: [(name: String, maxPop: Int)], period: String) -> TodayOverview {
        if rainy.isEmpty {
            let detail = dry.map { "\($0.name) 최대 \($0.maxPop)%" }.joined(separator: " · ")
            return TodayOverview(headline: "앞으로 \(period) 비 소식 없음", detail: detail.isEmpty ? nil : detail, isRainy: false)
        }
        let detail = dry.map { "\($0.name) 비 소식 없음 (최대 \($0.maxPop)%)" }.joined(separator: " · ")
        return TodayOverview(headline: rainy.joined(separator: " · "), detail: detail.isEmpty ? nil : detail, isRainy: true)
    }
}

/// 장소 카드의 7일 보기: 날짜마다 그 날 비가 오는지와 강수확률. 시간대는 보이지 않는다.
public struct WeekRainModel: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: Int { date }
        /// 현지 날짜의 0시 (epoch 초)
        public let date: Int
        /// "오늘", "내일", "목"
        public let label: String
        /// "10/23"
        public let dateText: String
        public let pop: Int
        public let level: RainLevel
        public let rainy: Bool
        /// "예보 4개 중 3개"
        public let agreement: String
    }

    public let rows: [Row]
    /// 비 오는 날이 있으면 "내일 · 토", 없으면 "앞으로 7일 비 소식 없음". 날짜별 값을 받지 못했으면 nil
    public let headline: String?
    /// "가장 높을 때 토 70%"
    public let detail: String?

    public var rainyCount: Int { rows.filter(\.rainy).count }

    public init(place: TodayPlace, tz: String, now: Int) {
        let clock = LocalClock(tz: tz)
        rows = (place.upcomingDays(now: now, tz: tz) ?? []).map { day in
            Row(
                date: day.date,
                label: clock.weekDayLabel(day.date, from: now),
                dateText: clock.monthDayText(day.date),
                pop: day.pop,
                level: day.level,
                rainy: day.rainy,
                agreement: "예보 \(day.total)개 중 \(day.agreeing)개"
            )
        }
        // 같은 확률이면 이른 날
        guard let peak = rows.max(by: { $0.pop < $1.pop }) else {
            headline = nil
            detail = nil
            return
        }
        let rainy = rows.filter(\.rainy)
        headline = rainy.isEmpty ? "앞으로 7일 비 소식 없음" : rainy.map(\.label).joined(separator: " · ")
        detail = "가장 높을 때 \(peak.label) \(peak.pop)%"
    }
}

/// 날씨 탭 카드의 24시간 막대와 기온 선: 막대, 비 구간 괄호, 시각 눈금, 지금·자정·출근 위치, 기온 선과 라벨.
/// 위치는 막대 칸 단위(0 = 첫 막대의 왼쪽 끝, `bars.count` = 오른쪽 끝)다.
public struct RainTimelineModel: Sendable, Equatable {
    public struct Bar: Sendable, Equatable {
        public let t: Int
        public let pop: Int
        public let level: RainLevel
        /// 기온 (기상청 우선, 카드 머리와 같은 값)
        public let temp: Double?
        /// "16시", 내일이면 "내일 3시"
        public let timeText: String
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

    /// 기온 선의 점 하나. 선은 막대 가운데를 지난다
    public struct TempPoint: Sendable, Equatable {
        /// 막대 순번
        public let index: Int
        public let temp: Double
        /// 단조 곡선의 기울기 (°/칸, `MonotoneCurve`)
        public let slope: Double

        public var position: Double { Double(index) + 0.5 }
    }

    /// 기온 라벨: 3시간 눈금 자리와 최고·최저
    public struct TempLabel: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case tick, high, low
        }

        /// 막대 순번
        public let index: Int
        public let temp: Double
        public let kind: Kind

        public var position: Double { Double(index) + 0.5 }
        /// "18°"
        public var text: String { "\(Int(temp.rounded()))°" }
    }

    public let bars: [Bar]
    public let brackets: [Bracket]
    public let ticks: [Tick]
    public let now: Double
    /// 날짜가 바뀌는 위치 (없으면 nil)
    public let midnight: Double?
    public let commutes: [Double]
    /// 기온 선 세로 범위: 위아래 1° 여유, 4° 이상, 정수. 기온이 두 시간 미만이면 nil(선을 그리지 않는다)
    public let tempScale: ClosedRange<Double>?
    /// 기온 선: 값이 이어지는 구간마다 따로 (빈 시간에서 끊는다)
    public let tempSegments: [[TempPoint]]
    /// 기온 숫자를 붙일 자리 (막대 순서)
    public let tempLabels: [TempLabel]

    public init(place: TodayPlace, tz: String, now: Int, hours: Int = 24, commuteTimes: [Int] = []) {
        let clock = LocalClock(tz: tz)
        let slice = place.upcoming(hours: hours, now: now)
        let bars = slice.map {
            Bar(
                t: $0.t,
                pop: $0.consensus ?? 0,
                level: RainLevel(pop: $0.consensus ?? 0),
                temp: $0.temp,
                timeText: clock.compactWindowText(start: $0.t, end: $0.t + 3600, now: now)
            )
        }
        self.bars = bars
        let origin = slice.first?.t ?? now - now % 3600
        let count = Double(slice.count)
        func position(_ epoch: Int) -> Double { Double(epoch - origin) / 3600 }

        brackets = place.upcomingWindows(within: hours, now: now).enumerated().compactMap { index, w in
            let start = max(0, position(w.start))
            let end = min(count, position(w.end))
            guard end > start else { return nil }
            return Bracket(window: index, start: start, end: end, label: clock.spanText(start: w.start, end: w.end))
        }
        let tickIndices = slice.indices.filter { clock.hour(slice[$0].t) % 3 == 0 }
        ticks = tickIndices.map { index in
            let hour = slice[index]
            let h = clock.hour(hour.t)
            let dayStart = h == 0 && index > 0
            return Tick(position: Double(index), label: dayStart ? clock.dayLabel(hour.t, from: now) : "\(h)시", isDayStart: dayStart)
        }
        self.now = min(count, max(0, position(now)))
        midnight = slice.dropFirst().first { clock.hour($0.t) == 0 }.map { position($0.t) }
        commutes = commuteTimes.map(position).filter { $0 >= 0 && $0 < count }

        let temps = bars.compactMap(\.temp)
        if temps.count >= 2, let low = temps.min(), let high = temps.max() {
            var lower = low - 1
            var upper = high + 1
            if upper - lower < 4 {
                let pad = (4 - (upper - lower)) / 2
                lower -= pad
                upper += pad
            }
            tempScale = lower.rounded(.down)...upper.rounded(.up)
            tempSegments = Self.segments(bars)
            tempLabels = Self.labels(bars, tickIndices: tickIndices)
        } else {
            tempScale = nil
            tempSegments = []
            tempLabels = []
        }
    }

    /// 기온 선 높이 (0 = 아래, 1 = 위)
    public func tempFraction(_ temp: Double) -> Double? {
        guard let tempScale, tempScale.upperBound > tempScale.lowerBound else { return nil }
        return (temp - tempScale.lowerBound) / (tempScale.upperBound - tempScale.lowerBound)
    }

    /// 밀어서 고른 위치(막대 칸 단위)의 막대. 양 끝 밖이면 끝 막대
    public func barIndex(at position: Double) -> Int? {
        guard !bars.isEmpty else { return nil }
        return min(max(Int(position.rounded(.down)), 0), bars.count - 1)
    }

    /// 말풍선: "16시 70% · 19°" (기온이 없으면 "16시 70%")
    public func callout(at index: Int) -> String {
        let bar = bars[index]
        return "\(bar.timeText) \(bar.pop)%" + (bar.temp.map { " · \(Int($0.rounded()))°" } ?? "")
    }

    /// VoiceOver: "16시, 강수확률 70%, 기온 19도"
    public func accessibilityText(at index: Int) -> String {
        let bar = bars[index]
        return "\(bar.timeText), 강수확률 \(bar.pop)%" + (bar.temp.map { ", 기온 \(Int($0.rounded()))도" } ?? "")
    }

    /// 기온이 이어지는 구간마다 점과 단조 곡선 기울기
    private static func segments(_ bars: [Bar]) -> [[TempPoint]] {
        var runs: [[(index: Int, temp: Double)]] = []
        for (index, bar) in bars.enumerated() {
            guard let temp = bar.temp else { continue }
            if let last = runs.last?.last, last.index == index - 1 {
                runs[runs.count - 1].append((index, temp))
            } else {
                runs.append([(index, temp)])
            }
        }
        return runs.map { run in
            let slopes = MonotoneCurve.tangents(run.map { $0.temp })
            return zip(run, slopes).map { TempPoint(index: $0.0.index, temp: $0.0.temp, slope: $0.1) }
        }
    }

    /// 최고·최저(반올림해 같으면 빼고), 그리고 그와 2칸 안에 붙지 않은 3시간 눈금 자리.
    /// 한 칸이 약 14pt라 "19°"(약 20pt)끼리 겹치지 않으려면 2칸은 떨어져야 한다.
    private static func labels(_ bars: [Bar], tickIndices: [Int]) -> [TempLabel] {
        let known = bars.indices.compactMap { index in bars[index].temp.map { (index: index, temp: $0) } }
        // 같은 값이면 이른 시간
        guard let highest = known.max(by: { $0.temp < $1.temp }),
              let lowest = known.min(by: { $0.temp < $1.temp }) else { return [] }
        var extremes: [TempLabel] = []
        if Int(highest.temp.rounded()) != Int(lowest.temp.rounded()) {
            extremes.append(TempLabel(index: highest.index, temp: highest.temp, kind: .high))
            if abs(lowest.index - highest.index) >= 2 {
                extremes.append(TempLabel(index: lowest.index, temp: lowest.temp, kind: .low))
            }
        }
        let tickLabels = tickIndices.compactMap { index -> TempLabel? in
            guard let temp = bars[index].temp,
                  !extremes.contains(where: { abs($0.index - index) < 2 }) else { return nil }
            return TempLabel(index: index, temp: temp, kind: .tick)
        }
        return (extremes + tickLabels).sorted { $0.index < $1.index }
    }
}

/// 단조 3차 곡선(Fritsch–Carlson): 점마다 기울기를 정해, 점 사이 곡선이 두 값 밖으로 튀어나가지 않게 한다.
/// 점 사이 간격은 1이다. 그리는 쪽은 점 i와 i+1 사이에 (1/3, m_i/3), (−1/3, −m_{i+1}/3) 조절점을 둔다.
public enum MonotoneCurve {
    public static func tangents(_ values: [Double]) -> [Double] {
        let count = values.count
        guard count > 1 else { return Array(repeating: 0, count: count) }
        let steps = (0..<(count - 1)).map { values[$0 + 1] - values[$0] }
        var slopes = Array(repeating: 0.0, count: count)
        slopes[0] = steps[0]
        slopes[count - 1] = steps[count - 2]
        for index in 1..<(count - 1) {
            // 오르다 내리는 꼭짓점은 평평하게
            slopes[index] = steps[index - 1] * steps[index] <= 0 ? 0 : (steps[index - 1] + steps[index]) / 2
        }
        for index in 0..<(count - 1) {
            let step = steps[index]
            if step == 0 {
                slopes[index] = 0
                slopes[index + 1] = 0
                continue
            }
            let a = slopes[index] / step
            let b = slopes[index + 1] / step
            let sum = a * a + b * b
            if sum > 9 {
                let scale = 3 / sum.squareRoot()
                slopes[index] = scale * a * step
                slopes[index + 1] = scale * b * step
            }
        }
        return slopes
    }
}

/// 날씨 탭 맨 위 장소 요약 칸: 지금 기온, 다음 비(7일 보기면 비 오는 날), 최대 강수확률
public struct PlaceGlance: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: PlaceKind
    public let name: String
    /// 지금 기온 (기상청 우선, 카드 머리와 같은 값)
    public let temp: Double?
    /// "8–10시 비", "지금 비 · 10시까지", "비 소식 없음". 7일 보기면 "오늘·목 비", "7일 비 소식 없음"
    public let rainText: String
    public let isRainy: Bool
    /// 보기 범위(24시간 또는 7일) 안 가장 높은 종합 강수확률
    public let maxPop: Int

    public var level: RainLevel { RainLevel(pop: maxPop) }

    public init(place: TodayPlace, tz: String, now: Int, week: Bool = false) {
        let clock = LocalClock(tz: tz)
        id = place.id
        kind = place.kind
        name = place.name
        temp = place.upcoming(hours: 1, now: now).first?.temp
        if week {
            let days = place.upcomingDays(now: now, tz: tz) ?? []
            let rainy = days.filter(\.rainy)
            maxPop = days.map(\.pop).max() ?? 0
            isRainy = !rainy.isEmpty
            if rainy.isEmpty {
                rainText = days.isEmpty ? "7일 예보를 받는 중" : "7일 비 소식 없음"
            } else {
                rainText = rainy.map { clock.weekDayLabel($0.date, from: now) }.joined(separator: "·") + " 비"
            }
            return
        }
        maxPop = place.upcoming(hours: 24, now: now).compactMap(\.consensus).max() ?? 0
        guard let next = place.upcomingWindows(now: now).first else {
            isRainy = false
            rainText = "비 소식 없음"
            return
        }
        isRainy = true
        if next.start <= now {
            // 자정에 그치면 "24시", 내일 그치면 "내일 2시"
            let endHour = clock.hour(next.end)
            let shown = endHour == 0 && clock.minute(next.end) == 0 ? 24 : endHour
            let prefix = clock.dayOffset(next.end - 1, from: now) >= 1 ? "내일 " : ""
            rainText = "지금 비 · \(prefix)\(shown)시까지"
        } else {
            rainText = "\(clock.compactWindowText(start: next.start, end: next.end, now: now)) 비"
        }
    }
}

extension TodayResponse {
    /// 날씨 탭 맨 위 장소 요약 (집, 회사 순서)
    public func glances(now: Int, week: Bool = false) -> [PlaceGlance] {
        places.map { PlaceGlance(place: $0, tz: tz, now: now, week: week) }
    }
}

/// 비 상세의 예보 그래프: 종합·예보별 선, 예보 범위 띠, 비 구간, 의견이 갈리는 시간과 그 설명
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

/// 비 상세의 표(히트맵): 행 = 종합 + 소스, 열 = 시간
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
