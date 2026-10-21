import SwiftUI
import WeatherCore

/// 장소 카드의 7일 보기: 날짜마다 한 줄(날짜, 비 여부 아이콘, 강수확률 막대와 %).
/// 시간대는 보이지 않고 그 날 비가 오는지만 본다. 비 오는 날은 파란색으로 강조한다.
struct WeekRainView: View {
    let model: WeekRainModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                DayRow(row: row, shown: appeared || reduceMotion)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.2).delay(Double(index) * 0.04),
                        value: appeared
                    )
            }
        }
        .onAppear { appeared = true }
    }
}

private struct DayRow: View {
    let row: WeekRainModel.Row
    /// false면 막대를 0에서 시작한다 (나타날 때 자라는 애니메이션)
    let shown: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.label)
                    .font(.subheadline.weight(.semibold))
                Text(row.dateText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, alignment: .leading)
            Image(systemName: row.rainy ? "umbrella.fill" : row.level.symbolName)
                .font(.subheadline)
                .foregroundStyle(row.rainy ? Color.blue : Color.secondary)
                .frame(width: 24)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(row.level.color)
                        .frame(width: shown ? max(6, geo.size.width * CGFloat(row.pop) / 100) : 0)
                }
            }
            .frame(height: 8)
            Text("\(row.pop)%")
                .font(.subheadline.weight(row.rainy ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(row.rainy ? Color.blue : Color.primary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .background(row.rainy ? Color.blue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label) \(row.dateText), \(row.rainy ? "비 예상" : "비 소식 없음"), 강수확률 \(row.pop)%, \(row.agreement)")
    }
}
