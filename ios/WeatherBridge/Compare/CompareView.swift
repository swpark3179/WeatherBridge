import SwiftUI
import WeatherCore

/// 비교 화면: 장소별로 종합·예보별 강수확률 그래프(앞으로 24/48시간), 고른 시간의 예보별 값,
/// 의견이 갈리는 시간. "표로 보기"는 예보 × 시간 숫자 표(히트맵, 48시간).
struct CompareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var range = 24
    @State private var showsTable = false
    @State private var hidden: Set<String> = []
    /// 고른 시간 (`TodayHour.t`). nil이면 기간 안에서 종합이 가장 높은 시간
    @State private var selectedHour: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let today = model.today, !today.places.isEmpty {
                        Picker("장소", selection: $model.comparePlace) {
                            ForEach(today.places) { place in
                                Text(place.name).tag(place.kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        if let place = today.places.first(where: { $0.kind == model.comparePlace }) ?? today.places.first {
                            let now = Int(Date().timeIntervalSince1970)
                            if showsTable {
                                HeatmapView(model: HeatmapModel(place: place, tz: today.tz, now: now))
                                Legend()
                            } else {
                                charts(place: place, today: today, now: now)
                            }
                            if !place.errors.isEmpty {
                                Label("받지 못한 소스: \(place.errors.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else if let error = model.todayError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else {
                        ProgressView("예보를 불러오는 중…").frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }
                .padding()
                .motion(reduced: Motion.fade, value: showsTable)
                .motion(reduced: Motion.fade, value: model.today == nil)
                .motion(Motion.gentle, value: model.today?.generatedAt)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("예보 비교")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showsTable ? "그래프로 보기" : "표로 보기") { showsTable.toggle() }
                }
            }
            .refreshable { await model.refreshToday() }
        }
    }

    private func charts(place: TodayPlace, today: TodayResponse, now: Int) -> some View {
        let chart = CompareChartModel(place: place, tz: today.tz, now: now, hours: range)
        let clock = LocalClock(tz: today.tz)
        let focus = chart.hours.first { $0.t == selectedHour }
            ?? chart.hours.max { ($0.consensus ?? 0) < ($1.consensus ?? 0) }
        let when = focus.map { "\(clock.dayLabel($0.t, from: now)) \(clock.hour($0.t))시" } ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(when)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("종합 \(focus?.consensus ?? 0)%")
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText(value: Double(focus?.consensus ?? 0)))
                    }
                    Spacer()
                    Picker("기간", selection: $range) {
                        Text("24시간").tag(24)
                        Text("48시간").tag(48)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                CompareChart(model: chart, threshold: today.threshold, hidden: hidden, focus: focus, selectedHour: $selectedHour)
                    .frame(height: 220)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            SourceValues(providers: chart.providers, focus: focus, when: when, hidden: $hidden)
            DisagreementList(disagreements: chart.disagreements) { selectedHour = $0 }
        }
        .motion(Motion.gentle, value: model.comparePlace)
        .motion(Motion.gentle, value: range)
        .motion(value: hidden)
    }
}

/// 고른 시간의 종합·예보별 값. 예보 행을 누르면 그래프에서 끄고 켠다.
private struct SourceValues: View {
    let providers: [String]
    let focus: TodayHour?
    let when: String
    @Binding var hidden: Set<String>

    var body: some View {
        let consensus = focus?.consensus
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(when) 예보별")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("눌러서 끄고 켜기")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ValueRow(label: "종합", color: .primary, lineWidth: 4, value: consensus, delta: nil, bold: true)
            ForEach(providers, id: \.self) { provider in
                let shown = !hidden.contains(provider)
                let value = focus?.providers[provider]
                Divider().padding(.leading)
                Button {
                    if shown { hidden.insert(provider) } else { hidden.remove(provider) }
                } label: {
                    ValueRow(
                        label: ForecastSourceInfo.label(provider),
                        color: ForecastSourceInfo.color(provider),
                        lineWidth: 3,
                        value: shown ? value : nil,
                        delta: shown ? value.flatMap { v in consensus.map { v - $0 } } : nil,
                        bold: false
                    )
                    .opacity(shown ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(shown ? .isSelected : [])
                .accessibilityHint(shown ? "누르면 그래프에서 숨깁니다" : "누르면 그래프에 다시 보입니다")
            }
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
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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

private struct LegendSwatch<Swatch: View>: View {
    let label: String
    @ViewBuilder let swatch: () -> Swatch

    var body: some View {
        HStack(spacing: 6) {
            swatch()
            Text(label)
        }
    }
}

/// 의견이 갈리는 시간. 누르면 그 시간을 고른다.
private struct DisagreementList: View {
    let disagreements: [CompareChartModel.Disagreement]
    let select: (Int) -> Void

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
                        select(item.span.start)
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

private struct HeatmapView: View {
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

private struct Legend: View {
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
