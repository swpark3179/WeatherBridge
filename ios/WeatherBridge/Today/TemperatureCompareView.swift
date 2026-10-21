import Charts
import SwiftUI
import WeatherCore

/// 기온 비교 보기: 오늘 시간별, 앞으로 7일 날짜별
enum TemperatureMode: Hashable {
    case today, week
}

/// 기온 비교로 가는 경로
struct TemperatureRoute: Hashable {
    let placeID: String
    /// 처음 보여줄 보기 (오늘 화면의 24시간·7일 보기를 따른다)
    var mode: TemperatureMode = .today
}

/// 기온 비교: 늘 최근 3일(어제·그제·3일 전)과 견준다.
/// 오늘 보기는 오늘(0–24시) 시간별 기온을 같은 시각과, 7일 보기는 날짜별 최고·최저를 최근 3일 평균 최고·최저와 견준다.
/// 오늘 카드 맨 아래 "지금 최근 3일보다 3° 낮아요" 줄을 누르면 열린다.
struct TemperatureCompareView: View {
    let route: TemperatureRoute

    @EnvironmentObject private var model: AppModel
    @State private var mode: TemperatureMode
    /// 고른 시간 (`Hour.t`). nil이면 지금 시간
    @State private var selectedHour: Int?

    init(route: TemperatureRoute) {
        self.route = route
        _mode = State(initialValue: route.mode)
    }

    private var place: TodayPlace? {
        model.today?.places.first { $0.id == route.placeID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("보기", selection: $mode) {
                    Text("오늘").tag(TemperatureMode.today)
                    Text("7일").tag(TemperatureMode.week)
                }
                .pickerStyle(.segmented)
                if let today = model.today, let place {
                    let now = Int(Date().timeIntervalSince1970)
                    switch mode {
                    case .today:
                        todayView(place: place, today: today, now: now)
                            .motionTransition(Self.modeTransition)
                    case .week:
                        weekView(place: place, today: today, now: now)
                            .motionTransition(Self.modeTransition)
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
            .motion(reduced: Motion.fade, value: mode)
            .motion(Motion.gentle, value: model.today?.generatedAt)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(place.map { "\($0.name) 기온 비교" } ?? "기온 비교")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: mode)
    }

    /// 보기를 바꾸면 새 보기가 살짝 떠오르며 나타난다 (동작 줄이기면 흐려지기만)
    private static var modeTransition: AnyTransition {
        .opacity.combined(with: .offset(y: 12))
    }

    @ViewBuilder
    private func todayView(place: TodayPlace, today: TodayResponse, now: Int) -> some View {
        if let comparison = TemperatureComparisonModel(place: place, tz: today.tz, now: now) {
            VStack(spacing: 16) {
                todayContent(comparison, clock: LocalClock(tz: today.tz))
            }
        } else {
            ContentUnavailableView(
                "비교할 지난 기온이 없어요",
                systemImage: "thermometer.medium",
                description: Text("서버가 지난 기온을 받아 오면 보여 드려요. 잠시 뒤 오늘 화면에서 당겨서 새로고침해 주세요.")
            )
        }
    }

    @ViewBuilder
    private func todayContent(_ comparison: TemperatureComparisonModel, clock: LocalClock) -> some View {
        let focus = comparison.hours.first { $0.t == selectedHour } ?? comparison.current
        TemperatureHero(comparison: comparison, clock: clock)
        HStack(spacing: 8) {
            ExtremeTile(title: "오늘 최고", extreme: comparison.high)
            ExtremeTile(title: "오늘 최저", extreme: comparison.low)
        }
        TemperatureChart(comparison: comparison, clock: clock, focus: focus, selectedHour: $selectedHour)
        TemperatureHourList(comparison: comparison, focus: focus?.t) { selectedHour = $0 }
        footnote(comparison)
    }

    @ViewBuilder
    private func weekView(place: TodayPlace, today: TodayResponse, now: Int) -> some View {
        if let week = WeekTemperatureModel(place: place, tz: today.tz, now: now) {
            VStack(spacing: 16) {
                WeekHero(week: week)
                WeekRangeList(week: week)
                weekFootnote(week)
            }
        } else {
            ContentUnavailableView(
                "7일 기온을 받는 중이에요",
                systemImage: "calendar",
                description: Text("서버가 날짜별 기온을 보내면 보여 드려요. 오늘 화면에서 당겨서 새로고침해 주세요.")
            )
        }
    }

    private func footnote(_ comparison: TemperatureComparisonModel) -> some View {
        let sources = comparison.providers.map(ForecastSourceInfo.label).joined(separator: "·")
        let basis = comparison.providers.count > 1 ? "예보 평균으로" : "예보로"
        var lines = [
            "\(sources) \(basis) 지난 기온과 오늘 기온을 견줬어요. 지난 시간은 모델이 남긴 값, 남은 시간은 예보예요.",
        ]
        if comparison.baselineDays < TemperatureComparisonModel.days {
            lines.append("지난 기록이 \(comparison.baselineDays)일치뿐이라 그 날들로만 계산했어요.")
        }
        lines.append("같은 예보끼리 비교한 값이라 오늘 카드의 기온(기상청 우선)과 조금 다를 수 있어요.")
        return Footnote(text: lines.joined(separator: " "))
    }

    private func weekFootnote(_ week: WeekTemperatureModel) -> some View {
        var lines = [
            "날마다 그 날 끝까지 닿는 예보 모델의 평균이고, 최근 3일 기준도 그 날과 같은 모델로 만들어 모델마다 다른 치우침을 뺐어요. 먼 날일수록 쓸 수 있는 모델이 적어요.",
        ]
        if let days = week.baseline?.dayCount, days < TemperatureComparisonModel.days {
            lines.append("지난 기록이 \(days)일치뿐이라 그 날들로만 계산했어요.")
        }
        lines.append("같은 예보끼리 비교한 값이라 오늘 카드의 기온(기상청 우선)과 조금 다를 수 있어요.")
        return Footnote(text: lines.joined(separator: " "))
    }
}

private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    ValueTile(title: TemperatureComparisonModel.valueLabel, value: headline.delta.baseline, tint: nil)
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
                .contentTransition(.numericText(value: value.rounded()))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 오늘 최고·최저와 최근 3일 최고·최저(평균)
private struct ExtremeTile: View {
    let title: String
    let extreme: TemperatureComparisonModel.Extreme?

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
                Text("\(TemperatureComparisonModel.valueLabel) \(Int(extreme.baseline.rounded()))°")
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

/// 오늘 기온(굵은 선)과 최근 3일 같은 시각 평균(점선). 값이 있는 날이 여럿이면 그 날들의 최저–최고 띠도 그린다.
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
                LegendLine(label: TemperatureComparisonModel.valueLabel, color: .secondary, dash: [4, 3])
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
        .accessibilityLabel("오늘과 \(TemperatureComparisonModel.valueLabel)의 시간별 기온 그래프")
    }

    /// "8시 12° · 최근 3일 15°"
    private func focusText(_ hour: TemperatureComparisonModel.Hour) -> String {
        "\(hour.hour)시 \(degreesText(hour.today)) · \(TemperatureComparisonModel.label) \(degreesText(hour.baseline))"
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
                Text("오늘 · \(TemperatureComparisonModel.valueLabel) · 차이")
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
                        baselineLabel: TemperatureComparisonModel.valueLabel,
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
                .contentTransition(.numericText())
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

    private var accessibilityText: String {
        let time = isCurrent ? "지금" : "\(hour.hour)시"
        guard let delta = hour.delta else { return "\(time) 오늘 \(degreesText(hour.today)), \(baselineLabel) \(degreesText(hour.baseline))" }
        let difference = delta.isSimilar ? "비슷함" : "\(abs(delta.degrees))도 \(delta.degrees < 0 ? "낮음" : "높음")"
        return "\(time) 오늘 \(degreesText(hour.today)), \(baselineLabel) \(degreesText(hour.baseline)), \(difference)"
    }
}

// MARK: 7일 보기

/// 맨 위: 앞으로 7일이 최근 3일보다 어떤지와 눈에 띄는 날, 최근 3일 평균 최고·최저
private struct WeekHero: View {
    let week: WeekTemperatureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label("앞으로 \(week.days.count)일 최고·최저", systemImage: week.outlook?.symbolName ?? "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(week.outlook?.tint ?? Color.secondary)
                Text(week.headline ?? "최근 3일과 견줄 기록이 아직 없어요")
                    .font(.title.weight(.semibold))
                if let detail = week.detail {
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            if let baseline = week.baseline {
                HStack(spacing: 8) {
                    ValueTile(title: "\(TemperatureComparisonModel.valueLabel) 최고", value: baseline.high, tint: nil)
                    ValueTile(title: "\(TemperatureComparisonModel.valueLabel) 최저", value: baseline.low, tint: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// 날짜마다 최저~최고 막대와 최근 3일과의 차이. 회색 눈금은 그 날과 같은 예보로 만든 최근 3일 평균 최저·최고.
/// 막대는 차례로 자란다.
private struct WeekRangeList: View {
    let week: WeekTemperatureModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("날짜별 최고·최저")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 2, height: 10)
                    Text(TemperatureComparisonModel.valueLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
            ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                WeekRangeRow(day: day, scale: week.scale, shown: appeared || reduceMotion)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.2).delay(Double(index) * 0.05),
                        value: appeared
                    )
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear { appeared = true }
    }
}

private struct WeekRangeRow: View {
    let day: WeekTemperatureModel.Day
    let scale: ClosedRange<Double>
    let shown: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.label)
                    .font(.subheadline.weight(.semibold))
                Text(day.dateText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, alignment: .leading)
            ValueWithDelta(value: day.low, delta: day.outlook.low, emphasized: false)
                .frame(width: 40, alignment: .trailing)
            RangeBar(
                low: day.low,
                high: day.high,
                scale: scale,
                ticks: day.baseline.map { [$0.low, $0.high] } ?? [],
                shown: shown
            )
            ValueWithDelta(value: day.high, delta: day.outlook.high, emphasized: true)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(day.label) \(day.dateText)", "최고 \(degreesText(day.high)), 최저 \(degreesText(day.low))"]
        if let headline = day.outlook.headline { parts.append(headline) }
        return parts.joined(separator: ", ")
    }
}

/// 기온과 그 아래 최근 3일과의 차이("−3°")
private struct ValueWithDelta: View {
    let value: Double?
    let delta: TemperatureDelta?
    /// 최고는 진하게, 최저는 옅게
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(degreesText(value))
                .font(.subheadline.weight(emphasized ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(emphasized ? Color.primary : Color.secondary)
                .contentTransition(.numericText())
            if let delta {
                Text(delta.signedText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(delta.tint)
                    .contentTransition(.numericText())
            }
        }
    }
}
