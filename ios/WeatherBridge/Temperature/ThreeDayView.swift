import Charts
import SwiftUI
import WeatherCore

/// 기온 탭 3일 보기: 맨 위 지금과 어제·내일 같은 시각, 어제·오늘·내일 날짜 카드(가로로 넘김, 날씨 장면 위에
/// 최고·최저가 전날 값에서 그 날 값으로 굴러감), 어제 0시–내일 24시 기온 그래프. 그래프와 카드는 서로 따라간다.
struct ThreeDayView: View {
    let place: TodayPlace
    let tz: String
    let now: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 보이는 날 (`Day.offset`: -1 어제, 0 오늘, 1 내일)
    @State private var selected: Int?

    var body: some View {
        if let model = ThreeDayTemperatureModel(place: place, tz: tz, now: now) {
            VStack(spacing: 16) {
                ThreeDayHero(model: model) { offset in
                    withMotion(Motion.standard, reduceMotion: reduceMotion) { selected = offset }
                }
                DayPager(items: model.days, selected: $selected) { day, isActive in
                    ThreeDayCard(day: day, isActive: isActive)
                }
                .padding(.horizontal, -16)
                if let chart = model.chart {
                    ThreeDayChart(chart: chart, days: model.days, clock: LocalClock(tz: tz), selected: $selected)
                }
                Footnote(text: footnote(model))
            }
            .onAppear {
                // 처음엔 오늘 카드
                if selected == nil { selected = 0 }
            }
        } else {
            ContentUnavailableView(
                "어제·오늘·내일 기온을 받는 중이에요",
                systemImage: "thermometer.medium",
                description: Text("새 예보를 받으면 보여 드려요. 당겨서 새로고침해 주세요.")
            )
        }
    }

    private func footnote(_ model: ThreeDayTemperatureModel) -> String {
        let sources = model.providers.map(ForecastSourceInfo.label).joined(separator: "·")
        return [
            "기온은 그 날 끝까지 닿는 예보 모델\(sources.isEmpty ? "" : "(\(sources))")의 평균이고, 날마다 전날과 같은 모델끼리 견줘요. 지난 시간은 모델이 남긴 값이에요.",
            "어제 하늘은 하루 강수량과 낮 구름 양으로 정해요.",
            "같은 예보끼리 비교한 값이라 날씨 탭 카드의 기온(기상청 우선)과 조금 다를 수 있어요.",
        ].joined(separator: " ")
    }
}

// MARK: 맨 위: 지금과 어제·내일 같은 시각

private struct ThreeDayHero: View {
    let model: ThreeDayTemperatureModel
    /// 그 날 카드로 간다 (-1 어제, 1 내일)
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let headline = model.headline {
                let tint = headline.delta?.tint
                VStack(alignment: .leading, spacing: 2) {
                    Label("지금 \(headline.hour)시", systemImage: headline.delta?.symbolName ?? "thermometer.medium")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint ?? .secondary)
                    Text(headline.text ?? "어제 같은 시각 기록이 없어요")
                        .font(.title.weight(.semibold))
                    if let feeling = headline.delta?.feeling {
                        Text(feeling)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    ValueTile(title: "지금", value: headline.now, tint: tint ?? .primary)
                    Button {
                        select(-1)
                    } label: {
                        ValueTile(title: "어제 이맘때", value: headline.yesterday, tint: nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("어제 카드로 갑니다")
                    Button {
                        select(1)
                    } label: {
                        ValueTile(title: "내일 이맘때", value: headline.tomorrow, tint: nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("내일 카드로 갑니다")
                }
            } else {
                Label("지금 기온을 받는 중이에요", systemImage: "thermometer.medium")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: 날짜 카드

/// 하루 카드: 날씨 장면 위에 날짜와 하늘, 최고·최저(전날 값에서 굴러감)와 전날 비교, 강수확률(어제는 없음)
private struct ThreeDayCard: View {
    let day: ThreeDayTemperatureModel.Day
    let isActive: Bool

    var body: some View {
        SceneCard(sky: day.sky, isActive: isActive, height: 300, sceneSpace: 32) { bounce in
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.label)
                        .font(.headline)
                    Text(day.dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sky = day.sky {
                    Label(sky.label, systemImage: sky.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.bounce, value: bounce)
                }
            }
        } panel: { revealed in
            VStack(alignment: .leading, spacing: 10) {
                if day.high != nil || day.low != nil {
                    HStack(alignment: .bottom, spacing: 16) {
                        TempValue(title: "최고", value: day.high, from: day.outlook.high?.baseline, revealed: revealed)
                        TempValue(title: "최저", value: day.low, from: day.outlook.low?.baseline, revealed: revealed)
                        Spacer()
                        if let rain = day.rain {
                            RainValue(rain: rain)
                        }
                    }
                    if let headline = day.outlook.headline {
                        Label(headline, systemImage: day.outlook.symbolName)
                            .font(.headline)
                            .foregroundStyle(day.outlook.tint)
                    }
                    if day.outlook.high != nil || day.outlook.low != nil {
                        HStack(spacing: 6) {
                            DeltaChip(title: "최고", delta: day.outlook.high)
                            DeltaChip(title: "최저", delta: day.outlook.low)
                            Spacer()
                            if day.modelCount > 0 {
                                Text("예보 \(day.modelCount)개")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Label("이 날 기온을 받는 중이에요", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("하루 시간의 3/4 이상 값이 모이면 최고·최저를 보여 드려요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: 3일 기온 그래프

/// 어제 0시부터 내일 24시까지 시간별 기온. 지난 시간은 옅게, 앞으로는 진하게, "지금" 세로선.
/// 고른 날은 바탕을 칠하고, 그래프를 밀면 그 시각 값이 보이며 날짜 카드가 따라온다.
private struct ThreeDayChart: View {
    let chart: ThreeDayChartModel
    let days: [ThreeDayTemperatureModel.Day]
    /// 장소 시간대 (시각 글)
    let clock: LocalClock
    @Binding var selected: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rawX: Double?
    @State private var focus: ThreeDayChartModel.Point?

    private var selectedIndex: Int? {
        days.firstIndex { $0.offset == selected }
    }

    private var pastPoints: [ThreeDayChartModel.Point] {
        guard let nowHour = chart.nowHour else { return [] }
        return chart.points.filter { $0.t <= nowHour }
    }

    private var futurePoints: [ThreeDayChartModel.Point] {
        guard let nowHour = chart.nowHour else { return chart.points }
        return chart.points.filter { $0.t >= nowHour }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("시간별 기온")
                    .font(.headline)
                Spacer()
                if let focus {
                    Text(focusText(focus))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
            }
            plot
                .frame(height: 200)
            HStack(spacing: 12) {
                LegendLine(color: .secondary, dashed: false, text: "지난 시간", lineWidth: 1.5)
                LegendLine(color: .orange, dashed: false, text: "앞으로", lineWidth: 2.5)
                LegendSwatch(label: "고른 날") {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.15)).frame(width: 14, height: 10)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .motion(value: selected)
    }

    private var plot: some View {
        Chart {
            if let index = selectedIndex, chart.dayBounds.indices.contains(index + 1) {
                RectangleMark(
                    xStart: .value("시작", chart.dayBounds[index]),
                    xEnd: .value("끝", chart.dayBounds[index + 1]),
                    yStart: .value("아래", chart.valueRange.lowerBound),
                    yEnd: .value("위", chart.valueRange.upperBound)
                )
                .foregroundStyle(Color.accentColor.opacity(0.08))
            }
            ForEach(pastPoints) { point in
                LineMark(
                    x: .value("시각", point.x),
                    y: .value("기온", point.temp),
                    series: .value("선", "past-\(point.segment)")
                )
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            ForEach(futurePoints) { point in
                LineMark(
                    x: .value("시각", point.x),
                    y: .value("기온", point.temp),
                    series: .value("선", "future-\(point.segment)")
                )
                .foregroundStyle(Color.orange)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            if let nowX = chart.nowX {
                RuleMark(x: .value("지금", nowX))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("지금")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }
            if let focus {
                RuleMark(x: .value("고른 시각", focus.x))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("고른 시각", focus.x),
                    y: .value("기온", focus.temp)
                )
                .foregroundStyle(Color.orange)
                .symbolSize(70)
            }
        }
        .chartXScale(domain: 0...(chart.dayBounds.last ?? 72))
        .chartYScale(domain: chart.valueRange)
        .chartXAxis {
            AxisMarks(values: chart.dayBounds) { _ in
                AxisGridLine()
            }
            AxisMarks(values: dayCenters) { value in
                AxisValueLabel(centered: true) {
                    if let x = value.as(Double.self), days.indices.contains(chart.day(at: x)) {
                        Text(days[chart.day(at: x)].label)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))°")
                    }
                }
            }
        }
        .chartXSelection(value: $rawX)
        .onChange(of: rawX) { _, x in
            guard let x else { return }
            // 점은 정시에 있으니 가장 가까운 점에 붙인다
            let nearest = chart.points.min { abs($0.x - x) < abs($1.x - x) }
            if nearest != focus { focus = nearest }
            let offset = chart.day(at: x) - 1
            if selected != offset {
                withMotion(Motion.standard, reduceMotion: reduceMotion) { selected = offset }
            }
        }
        .sensoryFeedback(.selection, trigger: focus?.t)
        .revealsPlotOnAppear()
        .accessibilityLabel("어제부터 내일까지 시간별 기온 그래프")
    }

    private var dayCenters: [Double] {
        zip(chart.dayBounds, chart.dayBounds.dropFirst()).map { ($0 + $1) / 2 }
    }

    /// "오늘 16시 18°"
    private func focusText(_ point: ThreeDayChartModel.Point) -> String {
        let day = days.indices.contains(chart.day(at: point.x)) ? days[chart.day(at: point.x)].label : ""
        return "\(day) \(clock.hour(point.t))시 \(degreesText(point.temp))"
    }
}
