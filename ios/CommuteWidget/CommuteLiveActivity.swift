import ActivityKit
import SwiftUI
import WeatherCore
import WidgetKit

/// 출근 1시간 전 ~ 출근 시각까지 잠금화면/Dynamic Island에 표시되는 브리핑.
struct CommuteLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CommuteActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(context.state.highlight ? Color.indigo.opacity(0.25) : nil)
        } dynamicIsland: { context in
            let state = context.state
            let level = RainLevel(pop: state.maxPop)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(state.maxPop)%", systemImage: level.symbolName)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(end: context.attributes.windowEndDate)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.headline).font(.subheadline.bold()).lineLimit(1)
                        ForEach(state.places, id: \.name) { place in
                            PlaceRow(place: place, firstHour: context.attributes.firstHour)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: level.symbolName)
            } compactTrailing: {
                Text("\(state.maxPop)%")
            } minimal: {
                Image(systemName: level.symbolName)
            }
        }
    }
}

private struct LockScreenView: View {
    let attributes: CommuteActivityAttributes
    let state: CommuteState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.headline)
                    .font(state.highlight ? .headline.bold() : .headline)
                    .foregroundStyle(state.highlight ? Color.indigo : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isStale {
                    Text("출근 시간 지남").font(.caption).foregroundStyle(.secondary)
                } else {
                    Countdown(end: attributes.windowEndDate)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(state.places, id: \.name) { place in
                PlaceRow(place: place, firstHour: attributes.firstHour)
            }
            Text("업데이트 \(state.updatedDate, style: .time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct PlaceRow: View {
    let place: PlaceBrief
    let firstHour: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(place.name).font(.subheadline.bold()).frame(width: 32, alignment: .leading)
            if let temp = place.temp {
                Text("\(temp)°").font(.subheadline).frame(width: 34, alignment: .trailing)
            }
            HourlyPopBars(pops: place.pops)
            Text("\(place.maxPop)%")
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(place.level == .clear ? Color.secondary : place.level.color)
                .frame(width: 40, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name), \(firstHour)시부터 최대 강수확률 \(place.maxPop)%")
    }
}

/// 출근 시각까지 남은 시간. 이미 지났으면 0에서 멈춘다(범위 역전 방지).
private struct Countdown: View {
    let end: Date

    var body: some View {
        let now = Date.now
        Text(timerInterval: now...max(now, end), countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}
