import Foundation

/// 그 날(지금) 기온 − 기준 기온. 차이는 화면에 보이는 정수 기온끼리 빼서 숫자와 문장이 어긋나지 않게 한다.
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

    /// "최근 3일보다 3° 낮아요", "지금과 비슷해요". 와/과는 `label`의 끝소리로 고른다.
    public func sentence(comparedTo label: String) -> String {
        if isSimilar {
            return "\(Hangul.withAnd(label)) 비슷해요"
        }
        return "\(label)보다 \(abs(degrees))° \(degrees < 0 ? "낮아요" : "높아요")"
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

/// 하루 시간별 기온에서 최고·최저 구하기 (기온 탭·여행이 함께 쓴다)
enum DayTemperature {
    /// 하루 최고·최저는 그 날 시간의 3/4 이상 값이 있을 때만 구한다
    static let coverage = 0.75

    /// 값이 있는 시간이 `hours`의 `coverage` 이상이면 `pick`(최고 또는 최저), 아니면 nil
    static func extreme(_ values: [Double?], hours: Int, _ pick: ([Double]) -> Double?) -> Double? {
        let known = values.compactMap { $0 }
        let needed = Int((Double(hours) * coverage).rounded(.up))
        return known.count >= needed ? pick(known) : nil
    }

    /// [start, end)의 정시들. 현지 자정이 정시가 아닌 곳(+5:30 등)은 다음 정시부터.
    static func hours(from start: Int, to end: Int) -> [Int] {
        Array(stride(from: (start + 3599) / 3600 * 3600, to: end, by: 3600))
    }
}

/// 한글 조사 고르기
enum Hangul {
    /// "지금과", "어제와"
    static func withAnd(_ word: String) -> String {
        word + (hasFinalConsonant(word) ? "과" : "와")
    }

    /// 마지막 글자에 받침이 있는지. 숫자는 읽는 소리로 본다(1 "일", 3 "삼"). 그 밖의 글자는 받침 없음으로 본다.
    static func hasFinalConsonant(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).unicodeScalars.last else { return false }
        switch last.value {
        case 0xAC00...0xD7A3:
            return (last.value - 0xAC00) % 28 != 0
        case 0x30...0x39:
            // 0 영, 1 일, 3 삼, 6 육, 7 칠, 8 팔
            return [0, 1, 3, 6, 7, 8].contains(Int(last.value - 0x30))
        default:
            return false
        }
    }
}
