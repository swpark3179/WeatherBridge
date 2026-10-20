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

    /// 0 = 오늘, 1 = 내일 …
    public func dayOffset(_ epoch: Int, from now: Int) -> Int {
        let a = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(now)))
        let b = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(epoch)))
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// "오늘 15–18시", "내일 3시", "모레 9–12시"
    public func windowText(start: Int, end: Int, now: Int) -> String {
        let day = Self.dayName(dayOffset(start, from: now))
        let startHour = hour(start)
        let endHour = hour(end)
        let shownEnd = endHour == 0 ? 24 : endHour
        let span = end - start <= 3600 || (shownEnd - startHour) == 1 ? "\(startHour)시" : "\(startHour)–\(shownEnd)시"
        return "\(day) \(span)"
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
    /// 앞으로 `hours`시간 안에 시작하는 비 구간 중 가장 이른 것
    public func nextWindow(within hours: Int = 24, now: Int) -> RainWindow? {
        windows.filter { $0.end > now && $0.start < now + hours * 3600 }.min { $0.start < $1.start }
    }

    /// 장소 카드 머리말. 예: "☔ 오늘 15–18시 최대 70% · 4개 중 3개", "앞으로 24시간 비 소식 없음 (최대 12%)"
    public func bannerText(now: Int, tz: String, hours: Int = 24) -> String {
        if let w = nextWindow(within: hours, now: now) {
            let text = LocalClock(tz: tz).windowText(start: w.start, end: w.end, now: now)
            let agreement = w.total > 0 ? " · \(w.total)개 중 \(w.agreeing)개" : ""
            return "☔ \(text) 최대 \(w.maxPop)%\(agreement)"
        }
        let maxPop = upcoming(hours: hours, now: now).compactMap(\.consensus).max() ?? 0
        return "앞으로 \(hours)시간 비 소식 없음 (최대 \(maxPop)%)"
    }

    /// 지금 시각이 속한 시간부터 `hours`개
    public func upcoming(hours: Int, now: Int) -> [TodayHour] {
        let currentHour = now - now % 3600
        return Array(self.hours.filter { $0.t >= currentHour }.prefix(hours))
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
