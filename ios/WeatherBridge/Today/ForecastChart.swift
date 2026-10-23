import Charts
import SwiftUI
import WeatherCore

/// 비 상세의 예보 그래프: 종합 강수확률 선, 예보들의 최저–최고 띠, 비 구간 음영.
/// "예보별 선"을 켜면 예보마다 선과 의견이 갈리는 시간(맨 위 띠)도 그린다. 밀어서 시간을 고르면 1시간 단위로 붙는다.
struct ForecastChart: View {
    let model: CompareChartModel
    let threshold: Int
    /// 진하게 칠할 비 구간의 시작 시각 (24·48시간 구간은 끝이 다를 수 있어 시작으로 맞춘다)
    let selectedWindowStart: Int?
    /// 예보마다 선을 그린다
    let showsSources: Bool
    /// 그리지 않을 예보
    let hidden: Set<String>
    let focus: TodayHour?
    @Binding var selectedHour: Int?

    @State private var rawSelection: Date?

    private var visibleProviders: [String] {
        showsSources ? model.providers.filter { !hidden.contains($0) } : []
    }

    /// 예보별 선을 켜면 종합은 굵은 기본색, 끄면 파랑
    private var consensusColor: Color { showsSources ? .primary : .blue }

    var body: some View {
        Chart {
            ForEach(Array(model.windows.enumerated()), id: \.offset) { _, window in
                RectangleMark(
                    xStart: .value("시작", date(window.start)),
                    xEnd: .value("끝", date(window.end)),
                    yStart: .value("아래", 0),
                    yEnd: .value("위", 100)
                )
                .foregroundStyle(Color.blue.opacity(window.start == selectedWindowStart ? 0.16 : 0.07))
            }
            if showsSources {
                ForEach(Array(model.splits.enumerated()), id: \.offset) { _, span in
                    RectangleMark(
                        xStart: .value("시작", date(span.start)),
                        xEnd: .value("끝", date(span.end)),
                        yStart: .value("아래", 96),
                        yEnd: .value("위", 100)
                    )
                    .foregroundStyle(Color.primary.opacity(0.35))
                }
            }
            RuleMark(y: .value("기준", threshold))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(Color.secondary)
            ForEach(model.hours, id: \.t) { hour in
                if let low = hour.min, let high = hour.max {
                    AreaMark(
                        x: .value("시각", middle(hour)),
                        yStart: .value("최저", low),
                        yEnd: .value("최고", high)
                    )
                    .foregroundStyle(Color.gray.opacity(0.2))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(visibleProviders, id: \.self) { provider in
                ForEach(model.hours, id: \.t) { hour in
                    if let value = hour.providers[provider] {
                        LineMark(
                            x: .value("시각", middle(hour)),
                            y: .value("강수확률", value),
                            series: .value("예보", provider)
                        )
                        .foregroundStyle(ForecastSourceInfo.color(provider))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            ForEach(model.hours, id: \.t) { hour in
                if let value = hour.consensus {
                    LineMark(
                        x: .value("시각", middle(hour)),
                        y: .value("강수확률", value),
                        series: .value("예보", "consensus")
                    )
                    .foregroundStyle(consensusColor)
                    .lineStyle(StrokeStyle(lineWidth: showsSources ? 3.5 : 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
            if let focus {
                RuleMark(x: .value("고른 시각", middle(focus)))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(visibleProviders, id: \.self) { provider in
                    if let value = focus.providers[provider] {
                        PointMark(
                            x: .value("고른 시각", middle(focus)),
                            y: .value("강수확률", value)
                        )
                        .foregroundStyle(ForecastSourceInfo.color(provider))
                        .symbolSize(50)
                    }
                }
                if let value = focus.consensus {
                    PointMark(
                        x: .value("고른 시각", middle(focus)),
                        y: .value("강수확률", value)
                    )
                    .foregroundStyle(consensusColor)
                    .symbolSize(90)
                }
            }
        }
        .chartLegend(.hidden)
        .revealsPlotOnAppear()
        .chartYScale(domain: 0...100)
        .chartXScale(domain: xDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let pop = value.as(Int.self) {
                        Text("\(pop)%")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: model.ticks.map { date($0.t) }) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self), let tick = model.ticks.first(where: { $0.t == Int(date.timeIntervalSince1970) }) {
                        Text(tick.label)
                            .fontWeight(tick.isDayStart ? .semibold : .regular)
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, date in
            guard let date else { return }
            let t = Int(date.timeIntervalSince1970)
            let hourStart = t - t % 3600
            if hourStart != selectedHour, model.hours.contains(where: { $0.t == hourStart }) {
                selectedHour = hourStart
            }
        }
        .sensoryFeedback(.selection, trigger: selectedHour)
        .accessibilityLabel(showsSources ? "종합과 예보별 시간대 강수확률 그래프" : "종합 강수확률 그래프")
    }

    private var xDomain: ClosedRange<Date> {
        date(model.hours.first?.t ?? 0)...date((model.hours.last?.t ?? 0) + 3600)
    }

    private func date(_ epoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epoch))
    }

    /// 비 구간 음영과 맞추려고 점은 그 시간의 가운데에 찍는다
    private func middle(_ hour: TodayHour) -> Date {
        date(hour.t + 1800)
    }
}
