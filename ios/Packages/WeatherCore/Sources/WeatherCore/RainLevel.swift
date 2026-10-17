/// 강수확률(%) 등급. 경계는 docs/IMPLEMENTATION_PLAN.md의 종합 알고리즘과 동일하다.
public enum RainLevel: Int, Codable, Comparable, Sendable, CaseIterable {
    case clear = 0     // < 20
    case low = 1       // 20–39
    case moderate = 2  // 40–59
    case high = 3      // >= 60

    public init(pop: Int) {
        switch pop {
        case ..<20: self = .clear
        case 20..<40: self = .low
        case 40..<60: self = .moderate
        default: self = .high
        }
    }

    public static func < (lhs: RainLevel, rhs: RainLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .clear: "없음"
        case .low: "낮음"
        case .moderate: "보통"
        case .high: "높음"
        }
    }
}
