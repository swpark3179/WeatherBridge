import SwiftUI
import WeatherCore

extension RainLevel {
    var color: Color {
        switch self {
        case .clear: .gray.opacity(0.35)
        case .low: .teal
        case .moderate: .blue
        case .high: .indigo
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .low: "cloud.sun.fill"
        case .moderate: "cloud.drizzle.fill"
        case .high: "cloud.heavyrain.fill"
        }
    }
}

/// 시간별 강수확률 미니 막대
struct HourlyPopBars: View {
    let pops: [Int]
    var maxHeight: CGFloat = 18

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(pops.enumerated()), id: \.offset) { _, pop in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(RainLevel(pop: pop).color)
                    .frame(height: max(2, maxHeight * CGFloat(pop) / 100))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
        .accessibilityLabel("시간별 강수확률 최대 \(pops.max() ?? 0)%")
    }
}

extension CommuteActivityAttributes {
    var windowEndDate: Date {
        Date(timeIntervalSince1970: TimeInterval(windowEnd))
    }
}

extension CommuteState {
    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }
}
