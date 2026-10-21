import Foundation

/// 달력 날짜 (시간대 없음). 서버와는 Postgres `date` 형식 "YYYY-MM-DD"로 주고받는다.
/// 여행 기간은 목적지의 달력 날짜이고, 하루의 시작 시각은 장소마다 `LocalClock.startOfDay(_:)`로 구한다.
public struct LocalDate: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// 날짜가 맞지 않으면(2월 30일 등) 다음 달로 넘긴다
    public init(year: Int, month: Int, day: Int) {
        self.init(dayNumber: Self.daysFromCivil(year, month, day))
    }

    /// "2026-10-25". 형식이 다르거나 없는 날짜면 nil
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let date = LocalDate(year: y, month: m, day: d)
        guard date.year == y, date.month == m, date.day == d else { return nil }
        self = date
    }

    /// `calendar`(보통 DatePicker의 `Calendar.current`)에서 본 그 순간의 날짜
    public init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// 1970-01-01부터 센 날 수
    public var dayNumber: Int { Self.daysFromCivil(year, month, day) }

    public init(dayNumber: Int) {
        (year, month, day) = Self.civilFromDays(dayNumber)
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    /// `other`까지 날 수 (other가 뒤면 양수)
    public func days(to other: LocalDate) -> Int {
        other.dayNumber - dayNumber
    }

    /// "월" … "일"
    public var weekdayText: String {
        // 1970-01-01은 목요일
        ["일", "월", "화", "수", "목", "금", "토"][((dayNumber % 7) + 7 + 4) % 7]
    }

    /// "10/25"
    public var monthDayText: String { "\(month)/\(day)" }

    /// `calendar` 시간대의 그 날 0시. DatePicker에 다시 넣을 때 쓴다.
    public func date(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// "2026-10-25"
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = LocalDate(string: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "날짜 형식이 아닙니다: \(value)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: LocalDate, b: LocalDate) -> Bool {
        a.dayNumber < b.dayNumber
    }

    // 그레고리력 날짜 ↔ 날 수 (Howard Hinnant, days_from_civil / civil_from_days)
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        // 범위를 벗어난 달은 해로 넘긴다
        let shifted = year * 12 + (month - 1)
        let y0 = Int((Double(shifted) / 12).rounded(.down))
        let m = shifted - y0 * 12 + 1
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468 + (day - 1)
    }

    private static func civilFromDays(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
