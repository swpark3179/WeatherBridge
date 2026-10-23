import SwiftUI

/// 범례의 선 모양 (실선·점선)
struct LegendLine: View {
    let color: Color
    let dashed: Bool
    let text: String
    var lineWidth: CGFloat = 2

    var body: some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 16, y: 5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dashed ? [3, 2] : []))
            .frame(width: 16, height: 10)
            Text(text)
                .lineLimit(1)
        }
    }
}

/// 범례의 칸 모양 (띠·음영)
struct LegendSwatch<Swatch: View>: View {
    let label: String
    @ViewBuilder let swatch: () -> Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatch()
            Text(label)
        }
    }
}

/// 작은 값 칸: 제목과 기온. 강조 색이 있으면 그 색으로
struct ValueTile: View {
    let title: String
    let value: Double?
    /// 강조 색 (없으면 기본 글자색)
    let tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(degreesText(value))
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint ?? Color.primary)
                .contentTransition(.numericText(value: value?.rounded() ?? 0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// 화면 맨 아래 설명
struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
