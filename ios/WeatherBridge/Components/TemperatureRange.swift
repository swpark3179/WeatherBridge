import SwiftUI
import WeatherCore

extension TemperatureDelta {
    /// 낮으면 파랑, 높으면 주황, 비슷하면 회색
    var tint: Color {
        if isSimilar { return .secondary }
        return degrees < 0 ? .blue : .orange
    }

    var symbolName: String {
        if isSimilar { return "thermometer.medium" }
        return degrees < 0 ? "thermometer.low" : "thermometer.high"
    }
}

extension TemperatureOutlook {
    /// 추워지면 파랑, 더워지면 주황, 일교차가 바뀌면 보라, 비슷하면 회색
    var tint: Color {
        guard let trend else { return .secondary }
        switch trend {
        case .colder: return .blue
        case .warmer: return .orange
        case .widerSwing, .narrowerSwing: return .purple
        case .similar: return .secondary
        }
    }

    var symbolName: String {
        guard let trend else { return "thermometer.medium" }
        switch trend {
        case .colder: return "thermometer.low"
        case .warmer: return "thermometer.high"
        case .widerSwing, .narrowerSwing: return "arrow.up.and.down"
        case .similar: return "thermometer.medium"
        }
    }
}

/// "16°", 값이 없으면 "–"
func degreesText(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))°" } ?? "–"
}

/// "최고 −4°" (추워지면 파랑, 더워지면 주황)
struct DeltaChip: View {
    let title: String
    let delta: TemperatureDelta?

    var body: some View {
        if let delta {
            Label("\(title) \(delta.signedText)", systemImage: delta.symbolName)
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(delta.tint)
                .background(delta.tint.opacity(0.15), in: Capsule())
        }
    }
}

/// 하루 최저~최고 막대(파랑 → 주황)와 기준 눈금(회색 세로선). 여행 날짜별 막대와 오늘 탭 7일 기온이 함께 쓴다.
struct RangeBar: View {
    let low: Double?
    let high: Double?
    /// 막대 가로축 범위
    let scale: ClosedRange<Double>
    /// 기준 눈금 (예: 최근 3일 평균 최저·최고)
    var ticks: [Double] = []
    /// false면 막대가 가운데에서 0 너비로 시작한다 (나타날 때 자라는 애니메이션)
    var shown = true

    var body: some View {
        GeometryReader { geo in
            let x = { (v: Double) -> CGFloat in
                geo.size.width * CGFloat((v - scale.lowerBound) / (scale.upperBound - scale.lowerBound))
            }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 6)
                if let low, let high {
                    Capsule()
                        .fill(LinearGradient(colors: [.blue, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, x(high) - x(low)), height: 6)
                        .scaleEffect(x: shown ? 1 : 0.01, anchor: .center)
                        .offset(x: x(low))
                }
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, value in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 2, height: 14)
                        .offset(x: x(value) - 1)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
    }
}
