import SwiftUI
import WeatherCore

/// 기온 탭 7일 보기: 오늘부터 날짜별 최고·최저를 최근 3일(어제·그제·3일 전) 평균 최고·최저와 견준다.
/// 최고끼리·최저끼리, 그 날과 같은 예보 모델 묶음으로 만든 기준과 비교한다(D26).
struct WeekTemperatureView: View {
    let place: TodayPlace
    let tz: String
    let now: Int

    var body: some View {
        if let week = WeekTemperatureModel(place: place, tz: tz, now: now) {
            VStack(spacing: 16) {
                WeekHero(week: week)
                WeekRangeList(week: week)
                footnote(week)
            }
        } else {
            ContentUnavailableView(
                "7일 기온을 받는 중이에요",
                systemImage: "calendar",
                description: Text("서버가 날짜별 기온을 보내면 보여 드려요. 당겨서 새로고침해 주세요.")
            )
        }
    }

    private func footnote(_ week: WeekTemperatureModel) -> some View {
        var lines = [
            "날마다 그 날 끝까지 닿는 예보 모델의 평균이고, 최근 3일 기준도 그 날과 같은 모델로 만들어 모델마다 다른 치우침을 뺐어요. 먼 날일수록 쓸 수 있는 모델이 적어요.",
        ]
        if let days = week.baseline?.dayCount, days < HomeBaseline.days {
            lines.append("지난 기록이 \(days)일치뿐이라 그 날들로만 계산했어요.")
        }
        lines.append("같은 예보끼리 비교한 값이라 날씨 탭 카드의 기온(기상청 우선)과 조금 다를 수 있어요.")
        return Footnote(text: lines.joined(separator: " "))
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
                    ValueTile(title: "\(WeekTemperatureModel.valueLabel) 최고", value: baseline.high, tint: nil)
                    ValueTile(title: "\(WeekTemperatureModel.valueLabel) 최저", value: baseline.low, tint: nil)
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
                    Text(WeekTemperatureModel.valueLabel)
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
