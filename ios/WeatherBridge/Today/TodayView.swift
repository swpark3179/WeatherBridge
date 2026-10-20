import SwiftUI
import WeatherCore

/// 오늘 화면 (기본형). 요약 알림·잠금화면과 같은 브리핑을 보여준다. 장소별 카드·비교 화면은 다음 단계에서 채운다.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let today = model.today {
                    briefing(today)
                } else if let error = model.todayError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Section {
                        HStack {
                            ProgressView()
                            Text("예보를 불러오는 중…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("오늘")
            .refreshable { await model.refreshToday() }
        }
    }

    @ViewBuilder
    private func briefing(_ today: TodayResponse) -> some View {
        let state = today.briefing.state
        Section {
            Label {
                Text(state.headline).font(.headline)
            } icon: {
                Image(systemName: state.highlight ? "umbrella.fill" : "sun.max.fill")
                    .foregroundStyle(state.highlight ? .blue : .orange)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("갱신 \(Date(timeIntervalSince1970: TimeInterval(today.generatedAt)).formatted(date: .omitted, time: .shortened)) · 강조 기준 \(today.threshold)%")
        }

        ForEach(state.places, id: \.name) { place in
            Section(place.name) {
                HStack(alignment: .firstTextBaseline) {
                    if let temp = place.temp {
                        Text("\(temp)°").font(.title2.weight(.semibold))
                    }
                    Spacer()
                    Text(place.rainWindow.map { "☔ \($0) 최대 \(place.maxPop)%" } ?? "비 소식 없음 (최대 \(place.maxPop)%)")
                        .foregroundStyle(place.level >= .moderate ? .blue : .secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HourlyPopBars(pops: place.pops, maxHeight: 40)
                    HStack {
                        Text("\(today.briefing.firstHour)시")
                        Spacer()
                        Text("24시")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
