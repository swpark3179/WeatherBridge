import SwiftUI
import WeatherCore

/// 장소 카드의 24시간 막대: 위에 비 구간 괄호, 막대 뒤 구간 음영, 지금·자정·출근 표시, 아래 3시간 눈금.
/// 접근성 문구는 쓰는 쪽이 `.accessibilityLabel`로 붙인다.
struct RainTimelineView: View {
    let model: RainTimelineModel
    /// 강조할 괄호의 `Bracket.window` (없으면 nil)
    let selectedWindow: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let bracketHeight: CGFloat = 24
    private let barHeight: CGFloat = 64
    private let markerHeight: CGFloat = 16
    private let axisHeight: CGFloat = 14
    private let spacing: CGFloat = 4

    private var showsCommuteRow: Bool { !model.commutes.isEmpty }
    /// 지금 바로 비 구간이 있으면 그 괄호 이름과 겹치므로 "지금"은 빼고 선만 둔다
    private var showsNowLabel: Bool { !model.brackets.contains { $0.start < model.now + 3 } }

    private var totalHeight: CGFloat {
        bracketHeight + barHeight + axisHeight + spacing * 2 + (showsCommuteRow ? markerHeight + spacing : 0)
    }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / CGFloat(max(model.bars.count, 1))
            VStack(alignment: .leading, spacing: spacing) {
                bracketRow(unit: unit)
                barRow(unit: unit)
                if showsCommuteRow {
                    commuteRow(unit: unit)
                }
                axisRow(unit: unit)
            }
        }
        .frame(height: totalHeight)
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
    }

    private func bracketRow(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if showsNowLabel {
                Text("지금")
                    .font(.caption2.weight(.semibold))
                    .offset(x: max(0, unit * model.now - 2))
            }
            ForEach(Array(model.brackets.enumerated()), id: \.offset) { _, bracket in
                let color = bracket.window == selectedWindow ? Color.blue : Color.secondary
                VStack(alignment: .leading, spacing: 2) {
                    Text(bracket.label)
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                    BracketShape()
                        .stroke(color, lineWidth: 2)
                        .frame(height: 6)
                }
                .foregroundStyle(color)
                .frame(width: max(unit * (bracket.end - bracket.start) - 2, 6), alignment: .leading)
                .offset(x: unit * bracket.start)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: bracketHeight, alignment: .top)
    }

    private func barRow(unit: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(model.brackets.enumerated()), id: \.offset) { _, bracket in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(bracket.window == selectedWindow ? 0.14 : 0.07))
                    .frame(width: unit * (bracket.end - bracket.start), height: barHeight)
                    .offset(x: unit * bracket.start)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(model.bars.enumerated()), id: \.offset) { index, bar in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(bar.level.color)
                        .frame(height: appeared || reduceMotion ? max(3, barHeight * CGFloat(bar.pop) / 100) : 0)
                        .animation(
                            reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.25).delay(Double(index) * 0.018),
                            value: appeared
                        )
                }
            }
            .frame(height: barHeight, alignment: .bottom)
            if let midnight = model.midnight {
                VerticalRule()
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                    .frame(width: 1, height: barHeight)
                    .offset(x: unit * midnight)
            }
            ForEach(Array(model.commutes.enumerated()), id: \.offset) { _, commute in
                VerticalRule()
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 1.5, height: barHeight)
                    .offset(x: unit * commute - 0.75)
            }
            Rectangle()
                .fill(Color.primary)
                .frame(width: 1.5, height: barHeight + 4)
                .offset(x: unit * model.now - 0.75)
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: barHeight, alignment: .bottom)
    }

    private func commuteRow(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.commutes.enumerated()), id: \.offset) { _, commute in
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(.secondarySystemGroupedBackground))
                    .frame(width: markerHeight, height: markerHeight)
                    .background(Color.primary, in: Circle())
                    .offset(x: unit * commute - markerHeight / 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: markerHeight, alignment: .top)
    }

    private func axisRow(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.ticks.enumerated()), id: \.offset) { _, tick in
                Text(tick.label)
                    .font(.caption2.weight(tick.isDayStart ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(tick.isDayStart ? Color.primary : Color.secondary)
                    .fixedSize()
                    .offset(x: unit * tick.position)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: axisHeight, alignment: .top)
    }
}

/// 위가 막힌 괄호 ⎴ 모양
private struct BracketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// 세로선 (점선은 stroke 스타일로 준다)
private struct VerticalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
