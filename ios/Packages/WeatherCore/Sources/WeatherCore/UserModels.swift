import Foundation

/// 하루 중 시각 (현지). 서버에는 Postgres `time` 형식 "HH:MM"으로 보내고, "HH:MM:SS"도 읽는다.
public struct ClockTime: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init?(string: String) {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = ClockTime(string: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "시각 형식이 아닙니다: \(value)")
            )
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    /// "07:05"
    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (a: ClockTime, b: ClockTime) -> Bool {
        (a.hour, a.minute) < (b.hour, b.minute)
    }
}

/// 사용자 설정 (`public.user_settings` 한 행)
public struct UserSettings: Codable, Hashable, Sendable {
    /// IANA 시간대
    public var tz: String
    public var summaryEnabled: Bool
    public var summaryTime: ClockTime
    /// Phase 3 출근 브리핑용
    public var commuteTime: ClockTime
    /// ISO 요일 1=월 … 7=일
    public var commuteDays: [Int]
    public var skipHolidays: Bool
    /// 강수 강조 임계값(%)
    public var threshold: Int

    public init(
        tz: String,
        summaryEnabled: Bool = false,
        summaryTime: ClockTime = ClockTime(hour: 7, minute: 0),
        commuteTime: ClockTime = ClockTime(hour: 8, minute: 30),
        commuteDays: [Int] = [1, 2, 3, 4, 5],
        skipHolidays: Bool = true,
        threshold: Int = 30
    ) {
        self.tz = tz
        self.summaryEnabled = summaryEnabled
        self.summaryTime = summaryTime
        self.commuteTime = commuteTime
        self.commuteDays = commuteDays
        self.skipHolidays = skipHolidays
        self.threshold = threshold
    }

    /// 서버가 허용하는 범위(임계값 10–90, 요일 1–7)로 맞춘다.
    public var normalized: UserSettings {
        var s = self
        s.threshold = min(max(threshold, 10), 90)
        s.commuteDays = Array(Set(commuteDays.filter { (1...7).contains($0) })).sorted()
        return s
    }

    enum CodingKeys: String, CodingKey {
        case tz
        case summaryEnabled = "summary_enabled"
        case summaryTime = "summary_time"
        case commuteTime = "commute_time"
        case commuteDays = "commute_days"
        case skipHolidays = "skip_holidays"
        case threshold
    }
}

/// 위도·경도. 서버에는 소수 둘째 자리(약 1km)까지만 보낸다.
public struct Coordinate: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    public var rounded2: Coordinate {
        Coordinate(lat: (lat * 100).rounded() / 100, lon: (lon * 100).rounded() / 100)
    }

    public var isValid: Bool {
        (-90...90).contains(lat) && (-180...180).contains(lon)
    }
}

/// 등록된 장소 (좌표는 받지 않는다)
public struct PlaceSummary: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: PlaceKind
    public var name: String
    public var tz: String

    public init(id: String, kind: PlaceKind, name: String, tz: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.tz = tz
    }
}

public enum ApnsEnvironment: String, Codable, Sendable {
    case sandbox, production
}
