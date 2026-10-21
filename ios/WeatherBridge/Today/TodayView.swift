import SwiftUI
import WeatherCore

/// 오늘 화면: 맨 위에 한 줄 요약, 아래에 집·회사 카드(앞으로 24시간). 카드를 누르면 비 상세로 간다.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Namespace private var cardTransition

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let today = model.today {
                        let now = Int(Date().timeIntervalSince1970)
                        OverviewHeader(today: today, now: now, isCached: model.todayIsCached)
                        ForEach(today.places) { place in
                            PlaceCard(
                                place: place,
                                tz: today.tz,
                                now: now,
                                commuteTimes: model.commuteTimes(tz: today.tz, now: now),
                                zoomNamespace: cardTransition
                            )
                        }
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
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("오늘")
            .refreshable { await model.refreshToday() }
            .navigationDestination(for: RainDetailRoute.self) { route in
                RainDetailView(route: route)
                    .navigationTransition(.zoom(sourceID: route.placeID, in: cardTransition))
            }
            .navigationDestination(for: TemperatureRoute.self) { route in
                TemperatureCompareView(route: route)
                    .navigationTransition(.zoom(sourceID: route.placeID, in: cardTransition))
            }
        }
    }
}

/// 비 상세로 가는 경로
struct RainDetailRoute: Hashable {
    let placeID: String
    /// 처음 보여줄 비 구간 (`upcomingWindows` 순번)
    let window: Int
}

/// 맨 위 요약: 비 오는 장소와 시간을 모두 나열한다
private struct OverviewHeader: View {
    let today: TodayResponse
    let now: Int
    let isCached: Bool

    var body: some View {
        let overview = today.overview(now: now)
        let tint = overview.isRainy ? Color.blue : Color.orange
        HStack(spacing: 12) {
            Image(systemName: overview.isRainy ? "umbrella.fill" : "sun.max.fill")
                .font(.title3)
                .foregroundStyle(tint)
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
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(isCached ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var updatedText: String {
        let time = Date(timeIntervalSince1970: TimeInterval(today.generatedAt)).formatted(date: .omitted, time: .shortened)
        return isCached ? "저장된 예보 (\(time) 기준) · 당겨서 새로고침" : "\(time) 갱신 · 강조 기준 \(today.threshold)%"
    }
}

/// 장소 카드: 다음 비 시각(크게), 비 구간 칩, 24시간 막대와 시각 눈금. 누르면 비 상세.
/// 맨 아래 줄은 어제 같은 시각과의 기온 차이이고, 누르면 기온 비교.
private struct PlaceCard: View {
    let place: TodayPlace
    let tz: String
    let now: Int
    let commuteTimes: [Int]
    let zoomNamespace: Namespace.ID

    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0

    private var clock: LocalClock { LocalClock(tz: tz) }

    var body: some View {
        let windows = place.upcomingWindows(now: now)
        let index = min(selected, max(0, windows.count - 1))
        let route = RainDetailRoute(placeID: place.id, window: index)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                NavigationLink(value: route) {
                    headline(windows: windows, index: index)
                }
                .buttonStyle(.plain)
                if windows.count > 1 {
                    chips(windows: windows, index: index)
                }
                RainTimelineView(
                    model: RainTimelineModel(place: place, tz: tz, now: now, commuteTimes: commuteTimes),
                    selectedWindow: windows.isEmpty ? nil : index
                )
                .accessibilityLabel(timelineDescription(windows))
                splitNote
                if !place.errors.isEmpty {
                    Label("일부 예보를 받지 못해 나머지로 계산했어요.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
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
            NavigationLink(value: TemperatureRoute(placeID: place.id)) {
                TemperatureLinkRow(
                    headline: TemperatureComparisonModel(place: place, tz: tz, now: now, baseline: .yesterday)?.headline
                )
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .matchedTransitionSource(id: place.id, in: zoomNamespace)
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
                }
                if let range = place.temperatureRange(now: now) {
                    Text("최고 \(Int(range.high.rounded()))° · 최저 \(Int(range.low.rounded()))°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text("\(window.hourCount)시간 · 최대 \(window.maxPop)% · 예보 \(window.total)개 중 \(window.agreeing)개")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private func chips(windows: [RainWindow], index: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(windows.enumerated()), id: \.offset) { i, window in
                    let isSelected = i == index
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) { selected = i }
                    } label: {
                        Text("\(clock.compactWindowText(start: window.start, end: window.end, now: now)) \(window.maxPop)%")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(isSelected ? Color.blue : Color.clear, in: Capsule())
                            .overlay { Capsule().strokeBorder(isSelected ? Color.blue : Color(.separator)) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var splitNote: some View {
        let spans = place.splitSpans(now: now)
        if !spans.isEmpty {
            Button {
                model.openCompare(place.kind)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.and.right")
                    Text("\(spans.map { clock.compactWindowText(start: $0.start, end: $0.end, now: now) }.joined(separator: ", "))는 예보끼리 차이가 커요")
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text("비교 보기")
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
        guard !windows.isEmpty else { return "앞으로 24시간 시간별 강수확률, 비 예상 시간 없음" }
        let parts = windows.map { "\(clock.windowText(start: $0.start, end: $0.end, now: now)) 최대 \($0.maxPop)%" }
        return "앞으로 24시간 시간별 강수확률, 비 예상 \(parts.joined(separator: ", "))"
    }
}

/// 장소 카드 맨 아래: "지금 어제보다 3° 낮아요 / 조금 추워요" → 기온 비교.
/// 어제와 견줄 기록이 아직 없으면(배포 직후·새 장소) 안내 문구를 보여 준다.
private struct TemperatureLinkRow: View {
    let headline: TemperatureComparisonModel.Headline?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: headline?.delta.symbolName ?? "thermometer.medium")
                .font(.title3)
                .foregroundStyle(headline?.delta.tint ?? Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline.map { "\($0.subject) \($0.text)" } ?? "어제와 기온 비교")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            Text("기온 비교")
                .font(.subheadline.weight(.semibold))
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    /// 체감 표현("조금 추워요"). 아직 견줄 기록이 없으면 안내
    private var caption: String? {
        guard let headline else { return "지난 기온을 받는 중이에요" }
        return headline.delta.feeling
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
