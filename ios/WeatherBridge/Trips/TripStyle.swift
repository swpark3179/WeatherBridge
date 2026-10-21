import SwiftUI
import WeatherCore

extension TripSky {
    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .snow: "cloud.snow.fill"
        }
    }
}

extension TripModel {
    /// 배지 색: 여행 중 초록, 곧 출발(3일 안) 주황, 그 밖 회색
    var badgeTint: Color {
        switch status {
        case .ongoing: .green
        case let .upcoming(daysLeft) where daysLeft <= 3: .orange
        case .upcoming, .ended: .secondary
        }
    }

    /// 목록 카드 배경에 깔 하늘: 예보가 있는 첫날
    var leadSky: TripSky? {
        days.lazy.compactMap(\.destination.sky).first
    }
}

/// "일본 표준시" 같은 시간대 이름. 모르면 IANA 이름 그대로
func timeZoneName(_ identifier: String) -> String {
    TimeZone(identifier: identifier)?.localizedName(for: .generic, locale: Locale(identifier: "ko_KR")) ?? identifier
}

/// 작은 배지: "D-3", "여행 중 2/4일"
struct TripBadge: View {
    let model: TripModel

    var body: some View {
        Text(model.badge)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(model.badgeTint)
            .background(model.badgeTint.opacity(0.15), in: Capsule())
    }
}
