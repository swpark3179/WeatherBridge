import SwiftUI
import WeatherCore

// 비 상세의 "예보별" 섹션 부품: 예보별 값, 의견이 갈리는 시간, 표(히트맵).

/// 고른 시간의 종합·예보별 값. "예보별 선"을 켜면 그래프에 예보마다 선이 보이고, 예보 줄을 누르면 그 선을 끄고 켠다.
struct SourceValues: View {
    let providers: [String]
    let focus: TodayHour?
    let when: String
    @Binding var showsSources: Bool
    @Binding var hidden: Set<String>

    var body: some View {
        let consensus = focus?.consensus
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("\(when) 예보별")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle(isOn: $showsSources) {
                    Label("예보별 선", systemImage: "chart.xyaxis.line")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.button)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ValueRow(label: "종합", color: showsSources ? .primary : .blue, lineWidth: 4, value: consensus, delta: nil, bold: true)
            ForEach(providers, id: \.self) { provider in
                let drawn = showsSources && !hidden.contains(provider)
                let value = focus?.providers[provider]
                Divider().padding(.leading)
                Button {
                    toggle(provider)
                } label: {
                    ValueRow(
                        label: ForecastSourceInfo.label(provider),
                        color: ForecastSourceInfo.color(provider),
                        lineWidth: 3,
                        value: value,
                        delta: value.flatMap { v in consensus.map { v - $0 } },
                        bold: false
                    )
                    .opacity(showsSources && !drawn ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(drawn ? .isSelected : [])
                .accessibilityHint(drawn ? "누르면 그래프에서 숨깁니다" : "누르면 그래프에 이 예보 선을 보입니다")
            }
            if showsSources {
                Divider()
                HStack(spacing: 16) {
                    LegendSwatch(label: "예보 범위") {
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.2)).frame(width: 14, height: 10)
                    }
                    LegendSwatch(label: "비 구간") {
                        RoundedRectangle(cornerRadius: 2).fill(Color.blue.opacity(0.12)).frame(width: 14, height: 10)
                    }
                    LegendSwatch(label: "맨 위 띠: 차이 40%p↑") {
                        RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.35)).frame(width: 14, height: 4)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .transition(.opacity)
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// 예보별 선이 꺼져 있으면 켜고 그 예보를 보이게, 켜져 있으면 그 선만 끄고 켠다
    private func toggle(_ provider: String) {
        if !showsSources {
            showsSources = true
            hidden.remove(provider)
        } else if hidden.contains(provider) {
            hidden.remove(provider)
        } else {
            hidden.insert(provider)
        }
    }
}

private struct ValueRow: View {
    let label: String
    let color: Color
    let lineWidth: CGFloat
    let value: Int?
    /// 종합과의 차이 (%p)
    let delta: Int?
    let bold: Bool

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(color)
                .frame(width: 22, height: lineWidth)
            Text(label)
                .font(.subheadline.weight(bold ? .bold : .regular))
            Spacer()
            Text(value.map { "\($0)%" } ?? "–")
                .font(.body.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText(value: Double(value ?? 0)))
            Text(deltaText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value.map { "\($0)%" } ?? "꺼짐")")
    }

    private var deltaText: String {
        guard let delta else { return "" }
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "−\(-delta)" }
        return "±0"
    }
}

/// 의견이 갈리는 시간. 누르면 그 시간과 예보를 고른다.
struct DisagreementList: View {
    let disagreements: [CompareChartModel.Disagreement]
    let select: (CompareChartModel.Disagreement) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("의견이 갈리는 시간")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            if disagreements.isEmpty {
                Divider()
                Text("이 기간에는 예보들이 대체로 같은 의견이에요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(Array(disagreements.enumerated()), id: \.offset) { _, item in
                    Divider()
                    Button {
                        select(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.left.and.right")
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.when)
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                Text(item.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 표: 예보 × 시간 강수확률(색은 등급). 왼쪽 행 이름은 고정하고 시간만 가로로 넘긴다
struct HeatmapView: View {
    let model: HeatmapModel

    private let cellWidth: CGFloat = 34
    private let cellHeight: CGFloat = 30
    private let labelWidth: CGFloat = 86

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // 왼쪽 행 이름은 고정하고 시간 축만 가로로 스크롤한다
            VStack(alignment: .leading, spacing: 2) {
                Color.clear.frame(height: cellHeight)
                ForEach(model.rows) { row in
                    Text(row.label)
                        .font(row.isConsensus ? .caption.bold() : .caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth, height: cellHeight, alignment: .leading)
                }
                Text("합의").font(.caption2).foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: cellHeight, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        ForEach(model.columns) { column in
                            VStack(spacing: 0) {
                                Text(column.dayLabel ?? " ").font(.system(size: 9)).foregroundStyle(.blue)
                                Text("\(column.hour)").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                    ForEach(model.rows) { row in
                        GridRow {
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, value in
                                HeatCell(value: value, emphasized: row.isConsensus)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                    GridRow {
                        ForEach(model.columns) { column in
                            VStack(spacing: 0) {
                                Text(column.agreement ?? "–").font(.system(size: 9))
                                if column.split {
                                    Image(systemName: "arrow.left.and.right").font(.system(size: 8))
                                }
                            }
                            .foregroundStyle(column.split ? .orange : .secondary)
                            .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("소스별 시간대 강수확률 표")
    }
}

private struct HeatCell: View {
    let value: Int?
    let emphasized: Bool

    var body: some View {
        if let value {
            let level = RainLevel(pop: value)
            Text("\(value)")
                .font(.system(size: 11, weight: emphasized ? .bold : .regular).monospacedDigit())
                .foregroundStyle(level >= .moderate ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(level.color.opacity(level == .clear ? 1 : 0.85), in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    if emphasized {
                        RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.4), lineWidth: 1)
                    }
                }
        } else {
            Text("–")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

/// 표 범례: 등급 색과 종합·합의·↔ 설명
struct HeatmapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ForEach(RainLevel.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(level.color).frame(width: 12, height: 12)
                        Text(level.label).font(.caption2)
                    }
                }
            }
            Text("맨 위 '종합'은 기상청에 가중치를 더 준 평균입니다. '합의'는 강조 기준 이상인 예보 수 / 참여 예보 수, ↔는 예보끼리 40%p 이상 차이 나는 시간입니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
