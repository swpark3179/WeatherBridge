import SwiftUI
import WeatherCore

/// 기온 탭 보기: 어제·오늘·내일, 앞으로 7일
enum TemperatureMode: String, Hashable {
    case threeDay, week
}

/// 기온 탭: 장소(집·회사)와 [어제·오늘·내일 | 7일]. 3일 보기는 날마다 전날과, 7일 보기는 최근 3일과 견준다.
/// 고른 장소와 보기는 날씨 탭과 함께 쓴다(날씨 탭 카드의 기온 줄을 누르면 그 장소·보기로 온다).
struct TemperatureTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("보기", selection: $model.temperatureMode) {
                        Text("어제·오늘·내일").tag(TemperatureMode.threeDay)
                        Text("7일").tag(TemperatureMode.week)
                    }
                    .pickerStyle(.segmented)
                    if let today = model.today, !today.places.isEmpty {
                        let now = Int(Date().timeIntervalSince1970)
                        // 날짜 카드를 밀어 넘기므로 장소는 칸을 눌러서만 바꾼다
                        PlaceTileRow(tiles: tiles(today, now: now), selection: model.focusedPlace) { kind in
                            withMotion(Motion.standard, reduceMotion: reduceMotion) { model.focusedPlace = kind }
                        }
                        if let place = today.places.first(where: { $0.kind == model.focusedPlace }) ?? today.places.first {
                            // 3일은 왼쪽에서, 7일은 오른쪽에서 들어온다
                            ZStack(alignment: .top) {
                                switch model.temperatureMode {
                                case .threeDay:
                                    ThreeDayView(place: place, tz: today.tz, now: now)
                                        .motionTransition(Motion.slide(.leading))
                                case .week:
                                    WeekTemperatureView(place: place, tz: today.tz, now: now)
                                        .motionTransition(Motion.slide(.trailing))
                                }
                            }
                        }
                    } else if let error = model.todayError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ProgressView("예보를 불러오는 중…")
                            .padding(.top, 80)
                    }
                }
                .padding()
                .motion(reduced: Motion.fade, value: model.temperatureMode)
                .motion(Motion.gentle, value: model.focusedPlace)
                .motion(reduced: Motion.fade, value: model.today == nil)
                .motion(Motion.gentle, value: model.today?.generatedAt)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("기온")
            .refreshable { await model.refreshToday() }
            .sensoryFeedback(.selection, trigger: model.temperatureMode)
        }
    }

    /// 장소 칸: 지금 기온과, 3일 보기면 어제 이맘때와의 차이, 7일 보기면 최근 3일과 견준 한 줄
    private func tiles(_ today: TodayResponse, now: Int) -> [PlaceTile] {
        today.places.map { place in
            let current = place.upcoming(hours: 1, now: now).first?.temp
            switch model.temperatureMode {
            case .threeDay:
                let headline = ThreeDayTemperatureModel(place: place, tz: today.tz, now: now)?.headline
                let delta = headline?.delta
                return PlaceTile(
                    kind: place.kind,
                    name: place.name,
                    value: degreesText(current),
                    detail: delta.map { $0.isSimilar ? "어제 이맘때와 비슷" : "어제 이맘때보다 \($0.signedText)" } ?? "어제와 견줄 기록을 받는 중",
                    symbolName: delta?.symbolName ?? "thermometer.medium",
                    tint: delta?.tint ?? .secondary
                )
            case .week:
                let week = WeekTemperatureModel(place: place, tz: today.tz, now: now)
                return PlaceTile(
                    kind: place.kind,
                    name: place.name,
                    value: degreesText(current),
                    detail: week?.headline ?? "7일 기온을 받는 중",
                    symbolName: week?.outlook?.symbolName ?? "thermometer.medium",
                    tint: week?.outlook?.tint ?? .secondary
                )
            }
        }
    }
}
