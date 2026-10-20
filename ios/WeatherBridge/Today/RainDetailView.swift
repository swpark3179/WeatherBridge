import Charts
import SwiftUI
import WeatherCore

/// 비 상세: 장소 카드를 누르면 열린다. 몇 시부터 몇 시까지 비가 오는지, 24시간 그래프, 시간별 목록, 예보별 값.
struct RainDetailView: View {
    let route: RainDetailRoute

    @EnvironmentObject private var model: AppModel
    @State private var windowIndex: Int
    /// 고른 시간 (`TodayHour.t`). nil이면 고른 비 구간의 가장 높은 시간
    @State private var selectedHour: Int?

    init(route: RainDetailRoute) {
        self.route = route
        _windowIndex = State(initialValue: route.window)
    }

    private var place: TodayPlace? {
        model.today?.places.first { $0.id == route.placeID }
    }

    var body: some View {
        Group {
            if let today = model.today, let place {
                content(today: today, place: place, now: Int(Date().timeIntervalSince1970))
            } else {
                ContentUnavailableView(
                    "예보가 없습니다",
                    systemImage: "cloud",
                    description: Text("오늘 화면에서 당겨서 새로고침해 주세요.")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(place.map { "\($0.name) 비 상세" } ?? "비 상세")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: windowIndex) { selectedHour = nil }
    }

    private func content(today: TodayResponse, place: TodayPlace, now: Int) -> some View {
        let clock = LocalClock(tz: today.tz)
        let windows = place.upcomingWindows(now: now)
        let hours = place.upcoming(hours: 24, now: now)
        let window = windows.isEmpty ? nil : windows[min(windowIndex, windows.count - 1)]
        let focus = selectedHour ?? window.flatMap { place.peakHour(of: $0)?.t } ?? hours.first?.t
        let focusHour = hours.first { $0.t == focus }
        return ScrollView {
            VStack(spacing: 16) {
                if windows.count > 1 {
                    Picker("비 구간", selection: $windowIndex) {
                        ForEach(Array(windows.enumerated()), id: \.offset) { index, w in
                            Text(clock.windowText(start: w.start, end: w.end, now: now)).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                RainHero(
                    place: place,
                    window: window,
                    hours: hours,
                    clock: clock,
                    now: now,
                    tz: today.tz,
                    commuteTimes: model.commuteTimes(tz: today.tz, now: now)
                )
                if !hours.isEmpty {
                    DetailChart(
                        hours: hours,
                        windows: windows,
                        selectedWindow: window,
                        threshold: today.threshold,
                        clock: clock,
                        focusHour: focusHour,
                        selectedHour: $selectedHour
                    )
                    HourList(
                        hours: hours,
                        windows: windows,
                        selectedWindow: window,
                        threshold: today.threshold,
                        clock: clock,
                        focus: focus
                    ) { selectedHour = $0 }
                }
                if let focusHour {
                    SourceBreakdown(place: place, hour: focusHour, clock: clock) {
                        model.openCompare(place.kind)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: 맨 위: 비 구간

private struct RainHero: View {
    let place: TodayPlace
    let window: RainWindow?
    let hours: [TodayHour]
    let clock: LocalClock
    let now: Int
    let tz: String
    let commuteTimes: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let window {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.start <= now ? "지금 비 예상 시간" : "\(clock.dayLabel(window.start, from: now)) 비 예상")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(clock.rangeText(start: window.start, end: window.end))
                        .font(.system(size: 44, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let peak = place.peakHour(of: window) {
                        Text("\(window.hourCount)시간 · \(clock.hour(peak.t))시에 가장 높아요")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    StatTile(title: "가장 높을 때", value: "\(window.maxPop)%", highlighted: true)
                    StatTile(title: "비 본다는 예보", value: "\(window.agreeing) / \(window.total)", highlighted: false)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let commute = commuteTimes.first(where: window.contains) {
                        Label("출근 \(clock.timeText(commute))이 이 시간 안에 있어요", systemImage: "briefcase.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    Label(place.clearingText(after: window, now: now, tz: tz), systemImage: "sun.max")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                let peak = hours.max { ($0.consensus ?? 0) < ($1.consensus ?? 0) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("앞으로 24시간 비 소식 없음")
                        .font(.title2.weight(.semibold))
                    if let peak {
                        Text("가장 높을 때 \(clock.hour(peak.t))시 \(peak.consensus ?? 0)%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(highlighted ? Color.blue : Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(highlighted ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: 24시간 그래프

/// 종합 강수확률 선 + 예보들의 최저–최고 띠 + 비 구간 음영. 밀어서 시간을 고르면 1시간 단위로 붙는다.
private struct DetailChart: View {
    let hours: [TodayHour]
    let windows: [RainWindow]
    let selectedWindow: RainWindow?
    let threshold: Int
    let clock: LocalClock
    let focusHour: TodayHour?
    @Binding var selectedHour: Int?

    @State private var rawSelection: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("앞으로 24시간")
                    .font(.headline)
                Spacer()
                if let focusHour {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(clock.hour(focusHour.t))시 \(focusHour.consensus ?? 0)%")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        if let temp = focusHour.temp {
                            Text("· \(Int(temp.rounded()))°")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            chart
                .frame(height: 180)
            Text("진한 선은 종합, 옅은 띠는 예보들의 최저–최고 범위예요. 그래프를 밀어 시간을 고르세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var chart: some View {
        Chart {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                RectangleMark(
                    xStart: .value("시작", date(window.start)),
                    xEnd: .value("끝", date(window.end)),
                    yStart: .value("아래", 0),
                    yEnd: .value("위", 100)
                )
                .foregroundStyle(Color.blue.opacity(window == selectedWindow ? 0.16 : 0.07))
            }
            RuleMark(y: .value("기준", threshold))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(Color.secondary)
            ForEach(hours, id: \.t) { hour in
                if let low = hour.min, let high = hour.max {
                    AreaMark(
                        x: .value("시각", middle(hour)),
                        yStart: .value("최저", low),
                        yEnd: .value("최고", high)
                    )
                    .foregroundStyle(Color.gray.opacity(0.22))
                    .interpolationMethod(.monotone)
                }
            }
            ForEach(hours, id: \.t) { hour in
                if let pop = hour.consensus {
                    LineMark(
                        x: .value("시각", middle(hour)),
                        y: .value("강수확률", pop)
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
            }
            if let focusHour, let pop = focusHour.consensus {
                RuleMark(x: .value("고른 시각", middle(focusHour)))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(
                    x: .value("고른 시각", middle(focusHour)),
                    y: .value("강수확률", pop)
                )
                .foregroundStyle(Color.blue)
                .symbolSize(90)
            }
        }
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
            let t = Int(date.timeIntervalSince1970)
            let hourStart = t - t % 3600
            if hourStart != selectedHour, hours.contains(where: { $0.t == hourStart }) {
                selectedHour = hourStart
            }
        }
        .sensoryFeedback(.selection, trigger: selectedHour)
        .accessibilityLabel("앞으로 24시간 종합 강수확률 그래프")
    }

    private var xDomain: ClosedRange<Date> {
        date(hours.first?.t ?? 0)...date((hours.last?.t ?? 0) + 3600)
    }

    private var tickDates: [Date] {
        hours.filter { clock.hour($0.t) % 3 == 0 }.map { date($0.t) }
    }

    private func date(_ epoch: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(epoch))
    }

    /// 막대·음영과 맞추려고 점은 그 시간의 가운데에 찍는다
    private func middle(_ hour: TodayHour) -> Date {
        date(hour.t + 1800)
    }
}

// MARK: 시간별 목록

private struct HourList: View {
    let hours: [TodayHour]
    let windows: [RainWindow]
    let selectedWindow: RainWindow?
    let threshold: Int
    let clock: LocalClock
    let focus: Int?
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("시간별")
                    .font(.headline)
                Spacer()
                Text("강수확률 · 기온 · 비 본다는 예보")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 14)
            .padding(.bottom, 8)
            ForEach(hours, id: \.t) { hour in
                let window = windows.first(where: { $0.contains(hour.t) })
                VStack(alignment: .leading, spacing: 0) {
                    if let window, window.start == hour.t || hour.t == hours.first?.t {
                        Label("비 \(clock.rangeText(start: window.start, end: window.end))", systemImage: "umbrella.fill")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(.blue)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    Button {
                        select(hour.t)
                    } label: {
                        HourRow(hour: hour, clock: clock, threshold: threshold, inWindow: window != nil, selected: hour.t == focus)
                    }
                    .buttonStyle(.plain)
                }
                .background(rowBackground(window))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func rowBackground(_ window: RainWindow?) -> Color {
        guard let window else { return .clear }
        return Color.blue.opacity(window == selectedWindow ? 0.14 : 0.07)
    }
}

private struct HourRow: View {
    let hour: TodayHour
    let clock: LocalClock
    let threshold: Int
    let inWindow: Bool
    let selected: Bool

    var body: some View {
        let pop = hour.consensus ?? 0
        let level = RainLevel(pop: pop)
        HStack(spacing: 10) {
            Text(String(format: "%02d시", clock.hour(hour.t)))
                .font(.subheadline.weight(inWindow ? .semibold : .regular).monospacedDigit())
                .frame(width: 40, alignment: .leading)
            Image(systemName: level.symbolName)
                .symbolRenderingMode(.multicolor)
                .frame(width: 24)
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(level.color)
                            .frame(width: max(4, geo.size.width * CGFloat(pop) / 100))
                    }
                }
            Text("\(pop)%")
                .font(.subheadline.weight(inWindow ? .semibold : .regular).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
            Text(hour.temp.map { "\(Int($0.rounded()))°" } ?? "–")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            AgreementDots(agreeing: hour.agreeing, total: hour.total)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            if selected {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(clock.hour(hour.t))시 강수확률 \(pop)%, 예보 \(hour.total)개 중 \(hour.agreeing)개가 \(threshold)% 이상")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 비 본다는(강조 기준 이상) 예보 수 / 참여 예보 수
private struct AgreementDots: View {
    let agreeing: Int
    let total: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Circle()
                    .fill(index < agreeing ? Color.blue : Color(.systemFill))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: 예보별 값

private struct SourceBreakdown: View {
    let place: TodayPlace
    let hour: TodayHour
    let clock: LocalClock
    let openCompare: () -> Void

    var body: some View {
        let providers = ForecastSourceInfo.sorted(place.sources.map(\.provider) + Array(hour.providers.keys))
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(clock.hour(hour.t))시 예보별")
                    .font(.headline)
                SourceRow(label: "종합", value: hour.consensus, color: .primary, bold: true)
                ForEach(providers, id: \.self) { provider in
                    SourceRow(
                        label: ForecastSourceInfo.label(provider),
                        value: hour.providers[provider],
                        color: ForecastSourceInfo.color(provider),
                        bold: false
                    )
                }
            }
            .padding()
            Divider()
            Button(action: openCompare) {
                HStack {
                    Text("비교 탭에서 자세히 보기")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SourceRow: View {
    let label: String
    let value: Int?
    let color: Color
    let bold: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(bold ? .bold : .regular))
                .frame(width: 96, alignment: .leading)
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(color)
                            .frame(width: max(4, geo.size.width * CGFloat(value ?? 0) / 100))
                    }
                }
            Text(value.map { "\($0)%" } ?? "–")
                .font(.subheadline.weight(bold ? .bold : .regular).monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value.map { "\($0)%" } ?? "값 없음")")
    }
}
