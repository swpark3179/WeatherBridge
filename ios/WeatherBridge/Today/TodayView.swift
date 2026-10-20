import SwiftUI
import WeatherCore

/// 오늘 화면: 맨 위에 요약 알림·잠금화면과 같은 브리핑, 아래에 집·회사 카드(앞으로 24시간).
struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let today = model.today {
                        BriefingCard(today: today, isCached: model.todayIsCached)
                        ForEach(today.places) { place in
                            PlaceCard(place: place, tz: today.tz, now: Int(Date().timeIntervalSince1970))
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
        }
    }
}

private struct BriefingCard: View {
    let today: TodayResponse
    let isCached: Bool

    var body: some View {
        let state = today.briefing.state
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(state.headline).font(.headline)
            } icon: {
                Image(systemName: state.highlight ? "umbrella.fill" : "sun.max.fill")
                    .foregroundStyle(state.highlight ? .blue : .orange)
            }
            Text("오늘 남은 시간 기준 · 강조 기준 \(today.threshold)%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(updatedText)
                .font(.caption2)
                .foregroundStyle(isCached ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(state.highlight ? Color.blue.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }

    private var updatedText: String {
        let time = Date(timeIntervalSince1970: TimeInterval(today.generatedAt)).formatted(date: .omitted, time: .shortened)
        return isCached ? "저장된 예보 (\(time) 기준) · 당겨서 새로고침" : "\(time) 갱신"
    }
}

/// 장소 카드: 비 구간 머리말, 현재 기온, 앞으로 24시간 막대와 시각 눈금
private struct PlaceCard: View {
    let place: TodayPlace
    let tz: String
    let now: Int

    private var hours: [TodayHour] { place.upcoming(hours: 24, now: now) }
    private var clock: LocalClock { LocalClock(tz: tz) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(place.name, systemImage: place.kind.symbolName)
                    .font(.headline)
                Spacer()
                if let temp = hours.first?.temp {
                    Text("\(Int(temp.rounded()))°").font(.title2.weight(.semibold))
                }
            }

            let banner = place.bannerText(now: now, tz: tz)
            Text(banner)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(place.nextWindow(now: now) != nil ? .blue : .secondary)

            VStack(spacing: 4) {
                HourlyPopBars(pops: hours.map { $0.consensus ?? 0 }, maxHeight: 56)
                HStack(spacing: 0) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                        Text(index % 6 == 0 ? "\(clock.hour(hour.t))시" : " ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if hours.contains(where: \.split) {
                Label("예보끼리 차이가 큰 시간이 있어요. 비교 탭에서 확인하세요.", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !place.errors.isEmpty {
                Label("일부 예보를 받지 못해 나머지로 계산했어요.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
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
