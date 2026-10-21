import Charts
import SwiftUI
import WeatherCore

/// 기온 비교로 가는 경로
struct TemperatureRoute: Hashable {
    let placeID: String
}

/// 기온 비교: 오늘(0–24시) 시간별 기온을 어제·최근 3일·최근 7일의 같은 시각과 견준다.
/// 오늘 카드 맨 아래 "지금 어제보다 3° 낮아요" 줄을 누르면 열린다.
struct TemperatureCompareView: View {
    let route: TemperatureRoute

    @EnvironmentObject private var model: AppModel
    @State private var baseline: TemperatureBaseline = .yesterday
    /// 고른 시간 (`Hour.t`). nil이면 지금 시간
    @State private var selectedHour: Int?

    private var place: TodayPlace? {
        model.today?.places.first { $0.id == route.placeID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("비교 기준", selection: $baseline) {
                    ForEach(TemperatureBaseline.allCases, id: \.self) { baseline in
                        Text(baseline.label).tag(baseline)
                    }
                }
                .pickerStyle(.segmented)
                if let today = model.today, let place {
                    let now = Int(Date().timeIntervalSince1970)
                    if let comparison = TemperatureComparisonModel(place: place, tz: today.tz, now: now, baseline: baseline) {
                        content(comparison, clock: LocalClock(tz: today.tz))
                    } else {
                        ContentUnavailableView(
                            "비교할 지난 기온이 없어요",
                            systemImage: "thermometer.medium",
                            description: Text("서버가 지난 기온을 받아 오면 보여 드려요. 잠시 뒤 오늘 화면에서 당겨서 새로고침해 주세요.")
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "예보가 없습니다",
                        systemImage: "cloud",
                        description: Text("오늘 화면에서 당겨서 새로고침해 주세요.")
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(place.map { "\($0.name) 기온 비교" } ?? "기온 비교")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: baseline)
    }

    @ViewBuilder
    private func content(_ comparison: TemperatureComparisonModel, clock: LocalClock) -> some View {
        let focus = comparison.hours.first { $0.t == selectedHour } ?? comparison.current
        TemperatureHero(comparison: comparison, clock: clock)
        HStack(spacing: 8) {
            ExtremeTile(title: "오늘 최고", extreme: comparison.high, baseline: comparison.baseline)
            ExtremeTile(title: "오늘 최저", extreme: comparison.low, baseline: comparison.baseline)
        }
        TemperatureChart(comparison: comparison, clock: clock, focus: focus, selectedHour: $selectedHour)
        TemperatureHourList(comparison: comparison, focus: focus?.t) { selectedHour = $0 }
        footnote(comparison)
    }

    private func footnote(_ comparison: TemperatureComparisonModel) -> some View {
        let sources = comparison.providers.map(ForecastSourceInfo.label).joined(separator: "·")
        let basis = comparison.providers.count > 1 ? "예보 평균으로" : "예보로"
        var lines = [
            "\(sources) \(basis) 지난 기온과 오늘 기온을 견줬어요. 지난 시간은 모델이 남긴 값, 남은 시간은 예보예요.",
        ]
        if comparison.baselineDays < comparison.baseline.days {
            lines.append("지난 기록이 \(comparison.baselineDays)일치뿐이라 그 날들로만 계산했어요.")
        }
        lines.append("같은 예보끼리 비교한 값이라 오늘 카드의 기온(기상청 우선)과 조금 다를 수 있어요.")
        return Text(lines.joined(separator: " "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

// MARK: 맨 위: 지금 차이

private struct TemperatureHero: View {
    let comparison: TemperatureComparisonModel
    let clock: LocalClock

    var body: some View {
        if let headline = comparison.headline {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(subject, systemImage: headline.delta.symbolName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(headline.delta.tint)
                    Text(headline.text)
                        .font(.title.weight(.semibold))
                    if let feeling = headline.delta.feeling {
                        Text(feeling)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    ValueTile(title: "오늘", value: headline.delta.today, tint: headline.delta.tint)
                    ValueTile(title: comparison.baseline.valueLabel, value: headline.delta.baseline, tint: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }

    /// "지금 14시" 또는 "오늘 최고 기온" (지금 값이 없을 때)
    private var subject: String {
        if let current = comparison.current, current.delta != nil {
            return "지금 \(clock.hour(current.t))시"
        }
        return "오늘 최고 기온"
    }
}

private struct ValueTile: View {
    let title: String
    let value: Double
    /// 강조 색 (없으면 기본 글자색)
    let tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))°")
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint ?? Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 오늘 최고·최저와 기준 날들의 최고·최저(평균)
private struct ExtremeTile: View {
    let title: String
    let extreme: TemperatureComparisonModel.Extreme?
    let baseline: TemperatureBaseline

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let extreme {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(extreme.today.rounded()))°")
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text(extreme.delta.signedText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(extreme.delta.tint)
                }
                Text("\(baseline.valueLabel) \(Int(extreme.baseline.rounded()))°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("–")
                    .font(.title2.weight(.semibold))
                Text("하루치 기록이 모자라요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

// MARK: 오늘 시간별 그래프

/// 오늘 기온(굵은 선)과 기준 날의 같은 시각 기온(점선). 기준이 여러 날이면 그 날들의 최저–최고 띠도 그린다.
/// 밀어서 시간을 고르면 1시간 단위로 붙는다.
private struct TemperatureChart: View {
    let comparison: TemperatureComparisonModel
    let clock: LocalClock
    let focus: TemperatureComparisonModel.Hour?
    @Binding var selectedHour: Int?

    @State private var rawSelection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘 시간별")
                    .font(.headline)
                Spacer()
                if let focus {
                    Text(focusText(focus))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            chart
                .frame(height: 200)
            HStack(spacing: 16) {
                LegendLine(label: "오늘", color: .primary, dash: [])
                LegendLine(label: comparison.baseline.valueLabel, color: .secondary, dash: [4, 3])
                if comparison.baselineDays > 1 {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.25)).frame(width: 14, height: 10)
                        Text("그 날들의 범위")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var chart: some View {
        Chart {
            if comparison.baselineDays > 1 {
                ForEach(comparison.hours, id: \.t) { hour in
                    if let low = hour.low, let high = hour.high {
                        AreaMark(
                            x: .value("시각", date(hour.t)),
                            yStart: .value("최저", low),
                            yEnd: .value("최고", high)
                        )
                        .foregroundStyle(Color.gray.opacity(0.2))
                        .interpolationMethod(.monotone)
                    }
                }
            }
            ForEach(comparison.hours, id: \.t) { hour in
                if let value = hour.baseline {
                    LineMark(
                        x: .value("시각", date(hour.t)),
                        y: .value("기온", value),
                        series: .value("날", "baseline")
                    )
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 3]))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(comparison.hours, id: \.t) { hour in
                if let value = hour.today {
                    LineMark(
                        x: .value("시각", date(hour.t)),
                        y: .value("기온", value),
                        series: .value("날", "today")
                    )
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
            if let focus {
                RuleMark(x: .value("고른 시각", date(focus.t)))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                if let value = focus.baseline {
                    PointMark(
                        x: .value("고른 시각", date(focus.t)),
                        y: .value("기온", value)
                    )
                    .foregroundStyle(Color.secondary)
                    .symbolSize(50)
                }
                if let value = focus.today {
                    PointMark(
                        x: .value("고른 시각", date(focus.t)),
                        y: .value("기온", value)
                    )
                    .foregroundStyle(focus.delta?.tint ?? Color.primary)
                    .symbolSize(90)
                }
            }
        }
        .revealsPlotOnAppear()
        .chartYScale(domain: comparison.valueRange)
        .chartXScale(domain: xDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let temp = value.as(Double.self) {
                        Text("\(Int(temp.rounded()))°")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: tickDates) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text("\(clock.hour(Int(date.timeIntervalSince1970)))시")
                    }
                }
            }
        }
        .chartXSelection(value: $rawSelection)
        .onChange(of: rawSelection) { _, date in
            guard let date else { return }
            // 점은 정시에 찍으므로 가장 가까운 정시에 붙인다
            let hour = (Int(date.timeIntervalSince1970) + 1800) / 3600 * 3600
            if hour != selectedHour, comparison.hours.contains(where: { $0.t == hour }) {
                selectedHour = hour
            }
        }
        .sensoryFeedback(.selection, trigger: selectedHour)
        .accessibilityLabel("오늘과 \(comparison.baseline.valueLabel)의 시간별 기온 그래프")
    }

    /// "8시 12° · 어제 15°"
    private func focusText(_ hour: TemperatureComparisonModel.Hour) -> String {
        let today = hour.today.map { "\(Int($0.rounded()))°" } ?? "–"
        let baseline = hour.baseline.map { "\(Int($0.rounded()))°" } ?? "–"
        return "\(hour.hour)시 \(today) · \(comparison.baseline.label) \(baseline)"
    }

    private var xDomain: ClosedRange<Date> {
        date(comparison.hours.first?.t ?? 0)...date(comparison.hours.last?.t ?? 0)
    }

    private var tickDates: [Date] {
        comparison.hours.filter { $0.hour % 3 == 0 }.map { date($0.t) }
    }

    private func date(_ epoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epoch))
    }
}

private struct LegendLine: View {
    let label: String
    let color: Color
    let dash: [CGFloat]

    var body: some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1.5))
                path.addLine(to: CGPoint(x: 18, y: 1.5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dash))
            .frame(width: 18, height: 3)
            Text(label)
        }
    }
}

// MARK: 시간별 목록

private struct TemperatureHourList: View {
    let comparison: TemperatureComparisonModel
    let focus: Int?
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("시간별")
                    .font(.headline)
                Spacer()
                Text("오늘 · \(comparison.baseline.valueLabel) · 차이")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 8)
            ForEach(comparison.hours, id: \.t) { hour in
                Button {
                    select(hour.t)
                } label: {
                    TemperatureHourRow(
                        hour: hour,
                        baselineLabel: comparison.baseline.valueLabel,
                        isCurrent: hour.t == comparison.current?.t,
                        selected: hour.t == focus
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct TemperatureHourRow: View {
    let hour: TemperatureComparisonModel.Hour
    let baselineLabel: String
    let isCurrent: Bool
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(isCurrent ? "지금" : String(format: "%02d시", hour.hour))
                .font(.subheadline.weight(isCurrent ? .bold : .regular).monospacedDigit())
                .frame(width: 40, alignment: .leading)
            Text(degreesText(hour.today))
                .font(.body.weight(.semibold).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
            Text(degreesText(hour.baseline))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
            Spacer()
            if let delta = hour.delta {
                Text(delta.signedText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(delta.tint)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 52, minHeight: 26)
                    .background(delta.tint.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func degreesText(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "–"
    }

    private var accessibilityText: String {
        let time = isCurrent ? "지금" : "\(hour.hour)시"
        guard let delta = hour.delta else { return "\(time) 오늘 \(degreesText(hour.today)), \(baselineLabel) \(degreesText(hour.baseline))" }
        let difference = delta.isSimilar ? "비슷함" : "\(abs(delta.degrees))도 \(delta.degrees < 0 ? "낮음" : "높음")"
        return "\(time) 오늘 \(degreesText(hour.today)), \(baselineLabel) \(degreesText(hour.baseline)), \(difference)"
    }
}
