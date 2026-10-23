import SwiftUI
import WeatherCore

/// 비 소식 범위: 앞으로 24시간(시간별) 또는 7일(날짜별)
enum RainRange: String {
    case day, week
}

/// 날씨 탭: 맨 위 한 줄 요약, 범위 선택(24시간·7일), 집·회사 요약 칸, 고른 장소 카드(좌우로 넘김).
/// 카드를 누르면 비 상세로, 맨 아래 기온 줄을 누르면 기온 탭으로 간다.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cardTransition
    /// 장면 상태로만 기억한다 (UserDefaults는 쓰지 않는다 — FileCache 참고)
    @SceneStorage("rainRange") private var range: RainRange = .day
    /// 장소 카드를 넘기는 정도 (타일 테두리만 읽는다)
    @State private var pagerProgress = PagerProgress()
    /// 막대를 꾹 눌러 미는 중이면 스크롤을 막는다
    @State private var scrubbing = false
    /// 당겨서 새로 받은 횟수 ("방금 갱신")
    @State private var refreshes = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let today = model.today {
                        let now = Int(Date().timeIntervalSince1970)
                        OverviewHeader(today: today, now: now, isCached: model.todayIsCached, range: range, refreshes: refreshes)
                        Picker("보기 범위", selection: $range) {
                            Text("24시간").tag(RainRange.day)
                            Text("7일").tag(RainRange.week)
                        }
                        .pickerStyle(.segmented)
                        PlaceTileRow(
                            tiles: today.glances(now: now, week: range == .week).map(PlaceTile.init),
                            selection: model.focusedPlace,
                            progress: pagerProgress
                        ) { kind in
                            withMotion(Motion.standard, reduceMotion: reduceMotion) { model.focusedPlace = kind }
                        }
                        PlacePager(kinds: today.places.map(\.kind), selection: $model.focusedPlace, progress: pagerProgress) { kind, isActive in
                            if let place = today.places.first(where: { $0.kind == kind }) {
                                PlaceCard(
                                    place: place,
                                    tz: today.tz,
                                    now: now,
                                    commuteTimes: model.commuteTimes(tz: today.tz, now: now),
                                    range: range,
                                    isActive: isActive,
                                    zoomNamespace: cardTransition,
                                    scrubbing: $scrubbing
                                )
                            }
                        }
                        .scrollDisabled(scrubbing)
                        .padding(.horizontal, -16)
                        SourcesFooter(today: today)
                    } else if model.todayError == nil {
                        ProgressView("예보를 불러오는 중…")
                            .padding(.top, 80)
                    }
                    if let error = model.todayError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .motion(value: range)
                // 처음 받은 예보는 흐려지며 나타나고(안쪽이 먼저), 새로 받으면 숫자·막대가 새 값으로 옮겨 간다
                .motion(reduced: Motion.fade, value: model.today == nil)
                .motion(reduced: Motion.fade, value: model.todayError)
                .motion(Motion.gentle, value: model.today?.generatedAt)
            }
            .scrollDisabled(scrubbing)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("날씨")
            .refreshable {
                await model.refreshToday()
                if model.todayError == nil { refreshes += 1 }
            }
            .sensoryFeedback(.selection, trigger: range)
            .navigationDestination(for: RainDetailRoute.self) { route in
                RainDetailView(route: route)
                    .navigationTransition(.zoom(sourceID: route.placeID, in: cardTransition))
            }
        }
    }
}

private extension PlaceTile {
    /// 날씨 탭 요약 칸: 지금 기온, 다음 비, 최대 강수확률
    init(_ glance: PlaceGlance) {
        self.init(
            kind: glance.kind,
            name: glance.name,
            value: degreesText(glance.temp),
            detail: glance.rainText,
            symbolName: glance.isRainy ? "umbrella.fill" : glance.level.symbolName,
            tint: glance.isRainy ? .blue : .secondary,
            badge: "최대 \(glance.maxPop)%"
        )
    }
}

/// 맨 위 요약: 비 오는 장소와 시간(7일 보기면 날짜)을 모두 나열한다.
/// 새로 받은 예보에서 비 소식이 바뀌면 아이콘이 바뀌며 한 번 튀고, 당겨서 새로 받으면 "방금 갱신"이 잠깐 보인다.
private struct OverviewHeader: View {
    let today: TodayResponse
    let now: Int
    let isCached: Bool
    let range: RainRange
    let refreshes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 직전 예보의 24시간 비 소식 (바뀌었을 때만 튕긴다)
    @State private var lastRainy: Bool?
    @State private var bounce = 0
    @State private var showsRefreshed = false

    var body: some View {
        let overview = range == .week ? today.weekOverview(now: now) : today.overview(now: now)
        let tint = overview.isRainy ? Color.blue : Color.orange
        HStack(spacing: 12) {
            Image(systemName: overview.isRainy ? "umbrella.fill" : "sun.max.fill")
                .font(.title3)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: bounce)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(overview.headline)
                    .font(.headline)
                if let detail = overview.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if showsRefreshed {
                    Label("방금 갱신", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity)
                } else {
                    Text(updatedText)
                        .font(.caption)
                        .foregroundStyle(isCached ? Color.orange : Color.secondary)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .motion(value: showsRefreshed)
        .onChange(of: today.generatedAt, initial: true) {
            let rainy = today.overview(now: now).isRainy
            if let lastRainy, lastRainy != rainy, !reduceMotion { bounce += 1 }
            lastRainy = rainy
        }
        .task(id: refreshes) {
            guard refreshes > 0 else { return }
            showsRefreshed = true
            try? await Task.sleep(for: .seconds(2))
            showsRefreshed = false
        }
    }

    private var updatedText: String {
        let time = Date(timeIntervalSince1970: TimeInterval(today.generatedAt)).formatted(date: .omitted, time: .shortened)
        return isCached ? "저장된 예보 (\(time) 기준) · 당겨서 새로고침" : "\(time) 갱신 · 강조 기준 \(today.threshold)%"
    }
}

/// 장소 카드: 다음 비 시각(크게), 비 구간 칩, 24시간 막대와 기온 선. 누르면 비 상세.
/// 7일 보기에서는 그 대신 비 오는 날과 날짜별 강수확률을 보여 준다.
/// 맨 아래 줄은 기온(24시간 보기는 어제 이맘때와, 7일 보기는 최근 3일과)이고, 누르면 기온 탭으로 간다.
private struct PlaceCard: View {
    let place: TodayPlace
    let tz: String
    let now: Int
    let commuteTimes: [Int]
    let range: RainRange
    let isActive: Bool
    let zoomNamespace: Namespace.ID
    @Binding var scrubbing: Bool

    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var chipNamespace
    @State private var selected = 0

    private var clock: LocalClock { LocalClock(tz: tz) }

    var body: some View {
        let windows = place.upcomingWindows(now: now)
        let index = min(selected, max(0, windows.count - 1))
        let route = RainDetailRoute(placeID: place.id, window: index)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                // 24시간은 왼쪽에서, 7일은 오른쪽에서 들어온다
                ZStack(alignment: .topLeading) {
                    switch range {
                    case .day:
                        dayContent(windows: windows, index: index, route: route)
                            .motionTransition(Motion.slide(.leading))
                    case .week:
                        weekSection(WeekRainModel(place: place, tz: tz, now: now))
                            .motionTransition(Motion.slide(.trailing))
                    }
                }
                if !place.errors.isEmpty {
                    Label("일부 예보를 받지 못해 나머지로 계산했어요.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            Spacer(minLength: 0)
            Divider()
            NavigationLink(value: route) {
                HStack {
                    Text("시간별 자세히 보기")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            Divider()
            // 지난 기록이 아직 없어도 줄은 늘 보여서 기능을 찾을 수 있게 한다
            Button {
                model.openTemperature(place.kind, mode: range == .week ? .week : .threeDay)
            } label: {
                temperatureLink
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityHint("기온 탭으로 갑니다")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .matchedTransitionSource(id: place.id, in: zoomNamespace)
    }

    @ViewBuilder
    private func dayContent(windows: [RainWindow], index: Int, route: RainDetailRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: route) {
                headline(windows: windows, index: index)
            }
            .buttonStyle(.plain)
            if windows.count > 1 {
                chips(windows: windows, index: index)
            }
            RainTimelineView(
                model: RainTimelineModel(place: place, tz: tz, now: now, commuteTimes: commuteTimes),
                selectedWindow: windows.isEmpty ? nil : index,
                isActive: isActive,
                isScrubbing: $scrubbing
            )
            .accessibilityLabel(timelineDescription(windows))
            splitNote
        }
    }

    /// 24시간 보기: "지금 어제보다 3° 낮아요 / 조금 선선해요",
    /// 7일 보기: "최근 3일보다 조금 추워요 / 앞으로 7일 · 가장 추운 날 토 최저 3° (−6°)"
    private var temperatureLink: TemperatureLinkRow {
        switch range {
        case .day:
            if let headline = ThreeDayTemperatureModel(place: place, tz: tz, now: now)?.headline {
                if let delta = headline.delta, let text = headline.cardText {
                    return TemperatureLinkRow(
                        symbolName: delta.symbolName,
                        tint: delta.tint,
                        title: text,
                        caption: delta.feeling ?? "어제·오늘·내일 기온 보기"
                    )
                }
                return TemperatureLinkRow(title: "지금 \(degreesText(headline.now))", caption: "어제·오늘·내일 기온 보기")
            }
            return TemperatureLinkRow(caption: "어제·오늘·내일 기온을 받는 중이에요")
        case .week:
            if let week = WeekTemperatureModel(place: place, tz: tz, now: now), let headline = week.headline {
                return TemperatureLinkRow(
                    symbolName: week.outlook?.symbolName ?? "thermometer.medium",
                    tint: week.outlook?.tint ?? .secondary,
                    title: headline,
                    caption: ["앞으로 \(week.days.count)일", week.detail].compactMap { $0 }.joined(separator: " · ")
                )
            }
            return TemperatureLinkRow(title: "최근 3일과 기온 비교", caption: "7일 기온을 받는 중이에요")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(place.name, systemImage: place.kind.symbolName)
                .font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let temp = place.upcoming(hours: 1, now: now).first?.temp {
                    Text("\(Int(temp.rounded()))°")
                        .font(.title2.weight(.semibold))
                        .contentTransition(.numericText(value: temp.rounded()))
                }
                if let range = place.temperatureRange(now: now) {
                    Text("최고 \(Int(range.high.rounded()))° · 최저 \(Int(range.low.rounded()))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    @ViewBuilder
    private func headline(windows: [RainWindow], index: Int) -> some View {
        if windows.indices.contains(index) {
            let window = windows[index]
            VStack(alignment: .leading, spacing: 2) {
                Text(window.start <= now ? "지금 비 예상 시간" : "\(clock.dayLabel(window.start, from: now)) 비 예상")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(clock.rangeText(start: window.start, end: window.end))
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("\(window.hourCount)시간 · 최대 \(window.maxPop)% · 예보 \(window.total)개 중 \(window.agreeing)개")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                if let commute = commuteTimes.first(where: window.contains) {
                    Label("출근 \(clock.timeText(commute))이 비 시간에 걸려요", systemImage: "briefcase.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .id(index)
            .transition(.opacity.combined(with: .offset(y: 6)))
        } else {
            let hours = place.upcoming(hours: 24, now: now)
            let peak = hours.max { ($0.consensus ?? 0) < ($1.consensus ?? 0) }
            VStack(alignment: .leading, spacing: 2) {
                Text("앞으로 24시간 비 소식 없음")
                    .font(.title3.weight(.semibold))
                if let peak {
                    Text("가장 높을 때 \(clock.hour(peak.t))시 \(peak.consensus ?? 0)%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    /// 7일 보기: 비 오는 날(크게)과 날짜별 줄. 날짜별 값을 아직 받지 못했으면(이전 서버·저장된 예보) 안내
    @ViewBuilder
    private func weekSection(_ week: WeekRainModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let headline = week.headline {
                VStack(alignment: .leading, spacing: 2) {
                    if week.rainyCount > 0 {
                        Text("7일 중 비 오는 날 \(week.rainyCount)일")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.blue)
                        Text(headline)
                            .font(.title2.weight(.semibold))
                    } else {
                        Text(headline)
                            .font(.title3.weight(.semibold))
                    }
                    if let detail = week.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                WeekRainView(model: week)
            } else {
                Label("7일 예보를 받는 중이에요. 당겨서 새로고침해 주세요.", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 비 구간 칩. 고른 칩의 바탕이 다음 칩으로 미끄러져 옮겨 간다
    private func chips(windows: [RainWindow], index: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(windows.enumerated()), id: \.offset) { i, window in
                    let isSelected = i == index
                    Button {
                        withMotion(Motion.standard, reduceMotion: reduceMotion) { selected = i }
                    } label: {
                        Text("\(clock.compactWindowText(start: window.start, end: window.end, now: now)) \(window.maxPop)%")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.blue)
                                        .matchedGeometryEffect(id: "selectedChip", in: chipNamespace)
                                }
                            }
                            .overlay { Capsule().strokeBorder(isSelected ? Color.blue : Color(.separator)) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        // 칩이 다 들어가면 가로로 밀리지 않아 장소 넘기기를 가로채지 않는다
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    @ViewBuilder
    private var splitNote: some View {
        let spans = place.splitSpans(now: now)
        if !spans.isEmpty {
            NavigationLink(value: RainDetailRoute(placeID: place.id, window: 0, section: .sources)) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right")
                    Text("\(spans.map { clock.compactWindowText(start: $0.start, end: $0.end, now: now) }.joined(separator: ", "))는 예보끼리 차이가 커요")
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("예보별 보기")
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func timelineDescription(_ windows: [RainWindow]) -> String {
        guard !windows.isEmpty else { return "앞으로 24시간 시간별 강수확률과 기온, 비 예상 시간 없음" }
        let parts = windows.map { "\(clock.windowText(start: $0.start, end: $0.end, now: now)) 최대 \($0.maxPop)%" }
        return "앞으로 24시간 시간별 강수확률과 기온, 비 예상 \(parts.joined(separator: ", "))"
    }
}

/// 장소 카드 맨 아래: "지금 어제보다 3° 낮아요 / 조금 선선해요" → 기온 탭.
/// 견줄 기록이 아직 없으면(배포 직후·새 장소) 기본 문구와 안내를 보여 준다.
private struct TemperatureLinkRow: View {
    var symbolName = "thermometer.medium"
    var tint = Color.secondary
    var title = "어제·오늘·내일 기온"
    let caption: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Text("기온 탭")
                .font(.subheadline.weight(.semibold))
            // 다른 탭으로 가므로 밀어 넣기(›) 대신 화살표
            Image(systemName: "arrow.right")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct SourcesFooter: View {
    let today: TodayResponse

    var body: some View {
        let providers = ForecastSourceInfo.sorted(today.places.flatMap { $0.sources.map(\.provider) })
        Text("\(providers.map(ForecastSourceInfo.label).joined(separator: " · ")) 예보를 종합했습니다. 출처는 설정에서 볼 수 있어요.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
