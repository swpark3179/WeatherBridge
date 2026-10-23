import SwiftUI
import WeatherCore

/// 비 상세 화면의 섹션 (예보별로 바로 열 때 그 자리로 스크롤한다)
enum RainDetailSection: Hashable {
    case summary, sources
}

/// 비 상세로 가는 경로
struct RainDetailRoute: Hashable {
    let placeID: String
    /// 처음 보여줄 비 구간 (`upcomingWindows` 순번)
    let window: Int
    /// 처음 보여줄 섹션. `.sources`면 예보별 선을 켜고 예보 카드에서 연다
    var section: RainDetailSection = .summary
}

/// 예보 카드 보기: 그래프 또는 표
private enum ForecastStyle: Hashable {
    case chart, table
}

/// 비 상세: 장소 카드를 누르면 열린다. 몇 시부터 몇 시까지 비가 오는지, 예보 그래프(종합, 켜면 예보별 선 · 24/48시간 · 표),
/// 고른 시간의 예보별 값, 의견이 갈리는 시간, 시간별 목록.
struct RainDetailView: View {
    let route: RainDetailRoute

    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var windowIndex: Int
    /// 고른 시간 (`TodayHour.t`). nil이면 고른 비 구간의 가장 높은 시간
    @State private var selectedHour: Int?
    /// 예보 카드 기간 (시간)
    @State private var range = 24
    @State private var style = ForecastStyle.chart
    /// 예보마다 선을 그린다
    @State private var showsSources: Bool
    /// 그리지 않을 예보
    @State private var hidden: Set<String> = []

    init(route: RainDetailRoute) {
        self.route = route
        _windowIndex = State(initialValue: route.window)
        _showsSources = State(initialValue: route.section == .sources)
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
                    description: Text("날씨 탭에서 당겨서 새로고침해 주세요.")
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(place.map { "\($0.name) 비 상세" } ?? "비 상세")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: windowIndex) { selectedHour = nil }
        .sensoryFeedback(.selection, trigger: style)
    }

    private func content(today: TodayResponse, place: TodayPlace, now: Int) -> some View {
        let clock = LocalClock(tz: today.tz)
        let windows = place.upcomingWindows(now: now)
        let hours = place.upcoming(hours: 24, now: now)
        let window = windows.isEmpty ? nil : windows[min(windowIndex, windows.count - 1)]
        let chart = CompareChartModel(place: place, tz: today.tz, now: now, hours: range)
        // 예보별로 열었으면 처음엔 의견이 갈리는 첫 시간을 고른다
        let opening = route.section == .sources ? chart.splits.first?.start : nil
        let focusTime = selectedHour ?? opening ?? window.flatMap { place.peakHour(of: $0)?.t } ?? hours.first?.t
        let focus = chart.hours.first { $0.t == focusTime }
        let when = focus.map { "\(clock.dayLabel($0.t, from: now)) \(clock.hour($0.t))시" } ?? ""
        return ScrollViewReader { proxy in
            ScrollView {
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
                    forecastCard(place: place, tz: today.tz, chart: chart, threshold: today.threshold, window: window, focus: focus, now: now)
                        .id(RainDetailSection.sources)
                    SourceValues(providers: chart.providers, focus: focus, when: when, showsSources: $showsSources, hidden: $hidden)
                    DisagreementList(disagreements: chart.disagreements) { item in
                        selectedHour = item.span.start
                        showsSources = true
                        hidden.remove(item.provider)
                        style = .chart
                        withMotion(Motion.gentle, reduceMotion: reduceMotion) {
                            proxy.scrollTo(RainDetailSection.sources, anchor: .top)
                        }
                    }
                    if !hours.isEmpty {
                        HourList(
                            hours: hours,
                            windows: windows,
                            selectedWindow: window,
                            threshold: today.threshold,
                            clock: clock,
                            focus: focusTime
                        ) { selectedHour = $0 }
                    }
                    if !place.errors.isEmpty {
                        Label("받지 못한 예보: \(place.errors.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                // 비 구간·기간·보기를 바꾸면 숫자·그래프 강조·목록이 새 값으로 옮겨 간다
                .motion(value: windowIndex)
                .motion(Motion.gentle, value: range)
                .motion(value: showsSources)
                .motion(value: hidden)
                .motion(reduced: Motion.fade, value: style)
                .motion(Motion.gentle, value: model.today?.generatedAt)
            }
            .onAppear {
                if route.section == .sources {
                    proxy.scrollTo(RainDetailSection.sources, anchor: .top)
                }
            }
        }
    }

    /// 예보 카드: 기간, 고른 시각 값, [그래프 | 표]
    private func forecastCard(
        place: TodayPlace,
        tz: String,
        chart: CompareChartModel,
        threshold: Int,
        window: RainWindow?,
        focus: TodayHour?,
        now: Int
    ) -> some View {
        let clock = LocalClock(tz: tz)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("앞으로 \(range)시간")
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Picker("기간", selection: $range) {
                    Text("24시간").tag(24)
                    Text("48시간").tag(48)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            if let focus {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(clock.dayLabel(focus.t, from: now)) \(clock.hour(focus.t))시 종합 \(focus.consensus ?? 0)%")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(focus.consensus ?? 0)))
                    if let temp = focus.temp {
                        Text("· \(Int(temp.rounded()))°")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Picker("보기", selection: $style) {
                Text("그래프").tag(ForecastStyle.chart)
                Text("표").tag(ForecastStyle.table)
            }
            .pickerStyle(.segmented)
            // 그래프는 왼쪽에서, 표는 오른쪽에서 들어온다
            ZStack(alignment: .top) {
                switch style {
                case .chart:
                    VStack(alignment: .leading, spacing: 8) {
                        ForecastChart(
                            model: chart,
                            threshold: threshold,
                            selectedWindowStart: window?.start,
                            showsSources: showsSources,
                            hidden: hidden,
                            focus: focus,
                            selectedHour: $selectedHour
                        )
                        .frame(height: 200)
                        Text(showsSources
                            ? "굵은 선은 종합, 색 선은 예보별, 옅은 띠는 예보들의 범위예요. 그래프를 밀어 시간을 고르세요."
                            : "선은 종합, 옅은 띠는 예보들의 최저–최고 범위예요. 그래프를 밀어 시간을 고르세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .motionTransition(Motion.slide(.leading))
                case .table:
                    VStack(alignment: .leading, spacing: 8) {
                        HeatmapView(model: HeatmapModel(place: place, tz: tz, now: now, hours: range))
                        HeatmapLegend()
                    }
                    .motionTransition(Motion.slide(.trailing))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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
        .background {
            if window != nil {
                RainStreaks()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

