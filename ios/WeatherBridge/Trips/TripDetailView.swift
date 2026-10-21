import Charts
import SwiftUI
import WeatherCore

/// 여행 상세: 날짜마다 날씨 장면 카드(가로로 넘김), 시간별 기온 그래프, 날짜별 최고·최저 막대.
/// 기온은 "지금"(집의 최근 3일 평균)과 최고끼리·최저끼리 비교한다.
struct TripDetailView: View {
    let tripID: String

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: LocalDate?
    @State private var editing = false
    @State private var confirmDelete = false

    private var trip: Trip? {
        model.trips?.trips.first { $0.id == tripID }
    }

    var body: some View {
        Group {
            if let trips = model.trips, let trip {
                content(TripModel(trip: trip, home: trips.home, now: Int(Date().timeIntervalSince1970)))
            } else {
                ContentUnavailableView("여행을 찾을 수 없어요", systemImage: "airplane")
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(trip?.name ?? "여행")
        .toolbar {
            if trip != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("고치기", systemImage: "pencil") { editing = true }
                        Button("지우기", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Label("더 보기", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                TripEditorView(trip: trip)
            }
        }
        .confirmationDialog("이 여행을 지울까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("지우기", role: .destructive) {
                Task { await delete() }
            }
        }
    }

    private func content(_ trip: TripModel) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                TripHeader(model: trip)
                if trip.days.isEmpty {
                    Label(trip.status == .ended ? "끝난 여행이에요" : "남은 날짜가 없어요", systemImage: "flag.checkered")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    DayPager(model: trip, selected: $selected)
                        .padding(.horizontal, -16)
                    if let chart = TripChartModel(model: trip) {
                        TripTemperatureChart(chart: chart, model: trip, selected: $selected)
                    }
                    TripRangeList(model: trip, selected: $selected)
                }
                notes(trip)
            }
            .padding()
        }
        .refreshable { await model.refreshTrips() }
        .onAppear {
            if selected == nil || !trip.days.contains(where: { $0.date == selected }) {
                selected = trip.days.first { $0.destination.hasForecast }?.date ?? trip.days.first?.date
            }
        }
    }

    private func notes(_ trip: TripModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("기온은 그 날 끝까지 닿는 예보 모델(ECMWF·GFS·ICON)의 평균이고, 지금(집 최근 3일)도 같은 모델로 계산해 비교해요. 먼 날일수록 모델 수가 줄어요.")
            Text("하늘은 낮(8–20시) 구름 양으로, 비·눈은 그 날 비 소식과 적설로 정해요. 날짜는 여행지 기준이고, 집은 같은 날짜를 집 시각으로 봐요.")
            Text("날씨 데이터: Open-Meteo (CC BY 4.0), 기상청")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func delete() async {
        do {
            try await model.deleteTrip(id: tripID)
            dismiss()
        } catch {
            model.notice = "여행을 지우지 못했습니다: \(AppModel.describe(error))"
        }
    }
}

// MARK: 맨 위: 기간·기준

private struct TripHeader: View {
    let model: TripModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.periodText)
                        .font(.subheadline.weight(.semibold))
                    Text("여행지 시간: \(timeZoneName(model.trip.tz))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TripBadge(model: model)
            }

            if let outlook = model.outlook, let headline = outlook.headline {
                Label(headline, systemImage: outlook.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(outlook.tint)
            }

            if let baseline = model.baseline {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("지금 = \(model.homeName ?? "집") 최근 \(baseline.dayCount)일 평균")
                            .font(.footnote.weight(.semibold))
                        Text("최고 \(degreesText(baseline.high)) · 최저 \(degreesText(baseline.low))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            } else if model.forecastFrom == nil, model.status != .ended {
                Label("집의 지난 기온이 없어 지금과 비교하지 못했어요", systemImage: "house")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let from = model.forecastFrom {
                Label("예보는 \(from.monthDayText)(\(from.weekdayText))부터 보여요", systemImage: "calendar.badge.clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: 날짜 카드 (가로로 넘김)

private struct DayPager: View {
    let model: TripModel
    @Binding var selected: LocalDate?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.days) { day in
                        TripDayCard(day: day, homeName: model.homeName, isActive: selected == day.date)
                            .containerRelativeFrame(.horizontal)
                            .scrollTransition(axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.92)
                                    .opacity(phase.isIdentity ? 1 : 0.6)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected)
            .safeAreaPadding(.horizontal, 28)
            .sensoryFeedback(.selection, trigger: selected)

            if model.days.count > 1 {
                PageDots(days: model.days, selected: $selected)
            }
        }
    }
}

private struct PageDots: View {
    let days: [TripModel.Day]
    @Binding var selected: LocalDate?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                Capsule()
                    .fill(day.date == selected ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: day.date == selected ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: selected)
        .accessibilityHidden(true)
    }
}

/// 하루 카드: 뒤에 날씨 장면, 위에 날짜와 하늘, 아래에 최고·최저(지금 값에서 굴러감)와 비교, 같은 날 집.
private struct TripDayCard: View {
    let day: TripModel.Day
    let homeName: String?
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 처음 보일 때 숫자를 지금 값에서 그 날 값으로 굴린다
    @State private var revealed = false

    var body: some View {
        let dest = day.destination
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.relative.map { "\($0) · \(day.label)" } ?? day.label)
                        .font(.headline)
                    Text("\(day.ordinal)일째")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let sky = dest.sky {
                    Label(sky.label, systemImage: sky.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .symbolEffect(.bounce, value: isActive && !reduceMotion)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 56)

            VStack(alignment: .leading, spacing: 10) {
                if dest.hasForecast {
                    HStack(alignment: .bottom, spacing: 16) {
                        TempValue(title: "최고", value: dest.high, from: dest.baseline?.high, revealed: revealed)
                        TempValue(title: "최저", value: dest.low, from: dest.baseline?.low, revealed: revealed)
                        Spacer()
                        if let rain = dest.rain {
                            RainValue(rain: rain)
                        }
                    }
                    if let headline = dest.outlook.headline {
                        Label(headline, systemImage: dest.outlook.symbolName)
                            .font(.headline)
                            .foregroundStyle(dest.outlook.tint)
                    }
                    if dest.outlook.high != nil || dest.outlook.low != nil {
                        HStack(spacing: 6) {
                            DeltaChip(title: "최고", delta: dest.outlook.high)
                            DeltaChip(title: "최저", delta: dest.outlook.low)
                            Spacer()
                            if dest.modelCount > 0 {
                                Text("예보 \(dest.modelCount)개")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider()
                    HomeLine(name: homeName ?? "집", summary: day.home)
                } else {
                    Label("아직 예보가 닿지 않아요", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("출발이 가까워지면 이 날의 날씨가 채워져요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(10)
        .frame(height: 380)
        .background {
            WeatherSceneView(sky: dest.sky, isActive: isActive)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .onChange(of: isActive, initial: true) { _, active in
            guard active, !revealed else { return }
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.snappy(duration: 0.9).delay(0.15)) { revealed = true }
            }
        }
    }
}

/// 큰 기온 숫자. 처음에는 지금 값을 보이고 그 날 값으로 굴러간다.
private struct TempValue: View {
    let title: String
    let value: Double?
    let from: Double?
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let value {
                let shown = Int((revealed ? value : (from ?? value)).rounded())
                Text("\(shown)°")
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(value: Double(shown)))
            } else {
                Text("–")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(degreesText(value))")
    }
}

private struct RainValue: View {
    let rain: TripRain

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Image(systemName: rain.rainy ? "umbrella.fill" : "drop")
                .font(.title3)
            Text("\(rain.pop)%")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(rain.rainy ? Color.blue : Color.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("강수확률 \(rain.pop)%\(rain.rainy ? ", 비 예상" : "")")
    }
}

/// "최고 −4°" (추워지면 파랑, 더워지면 주황)
private struct DeltaChip: View {
    let title: String
    let delta: TemperatureDelta?

    var body: some View {
        if let delta {
            Label("\(title) \(delta.signedText)", systemImage: delta.symbolName)
                .font(.caption.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(delta.tint)
                .background(delta.tint.opacity(0.15), in: Capsule())
        }
    }
}

/// 같은 날 집: 하늘, 최고/최저, 비, 지금과 비교
private struct HomeLine: View {
    let name: String
    let summary: TripDaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(name, systemImage: "house.fill")
                    .font(.subheadline.weight(.semibold))
                if let sky = summary.sky {
                    Image(systemName: sky.symbolName)
                        .symbolRenderingMode(.multicolor)
                }
                if summary.high != nil || summary.low != nil {
                    Text("\(degreesText(summary.high)) / \(degreesText(summary.low))")
                        .font(.subheadline.monospacedDigit())
                }
                Spacer()
                if let rain = summary.rain {
                    Label("\(rain.pop)%", systemImage: rain.rainy ? "umbrella.fill" : "drop")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(rain.rainy ? Color.blue : Color.secondary)
                }
            }
            if let headline = summary.outlook.headline {
                Text(headline)
                    .font(.caption)
                    .foregroundStyle(summary.outlook.tint)
            } else if !summary.hasForecast {
                Text("집 예보가 없어요")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: 시간별 기온 그래프

private struct TripTemperatureChart: View {
    let chart: TripChartModel
    let model: TripModel
    @Binding var selected: LocalDate?
    @State private var rawX: Double?

    private var selectedIndex: Int? {
        model.days.firstIndex { $0.date == selected }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("시간별 기온")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 12) {
                LegendLine(color: .orange, dashed: false, text: model.trip.name)
                LegendLine(color: .secondary, dashed: true, text: model.homeName ?? "집")
                if chart.baseline != nil {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.25))
                            .frame(width: 14, height: 10)
                        Text("지금")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Chart {
                if let baseline = chart.baseline {
                    RectangleMark(
                        xStart: .value("시작", 0.0),
                        xEnd: .value("끝", Double(chart.dayCount * 24)),
                        yStart: .value("지금 최저", baseline.low),
                        yEnd: .value("지금 최고", baseline.high)
                    )
                    .foregroundStyle(Color.gray.opacity(0.18))
                }
                if let index = selectedIndex {
                    RectangleMark(
                        xStart: .value("시작", Double(index * 24)),
                        xEnd: .value("끝", Double(index * 24 + 24)),
                        yStart: .value("아래", chart.valueRange.lowerBound),
                        yEnd: .value("위", chart.valueRange.upperBound)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.08))
                }
                ForEach(chart.points) { point in
                    LineMark(
                        x: .value("시각", point.x),
                        y: .value("기온", point.temp),
                        series: .value("선", point.line)
                    )
                    .foregroundStyle(point.series == .destination ? Color.orange : Color.secondary)
                    .lineStyle(
                        point.series == .destination
                            ? StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            : StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3])
                    )
                    .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: 0...Double(chart.dayCount * 24))
            .chartYScale(domain: chart.valueRange)
            .chartXAxis {
                AxisMarks(values: (0...chart.dayCount).map { Double($0 * 24) }) { _ in
                    AxisGridLine()
                }
                AxisMarks(values: model.days.indices.map { Double($0 * 24 + 12) }) { value in
                    AxisValueLabel(centered: true) {
                        if let x = value.as(Double.self), model.days.indices.contains(Int(x / 24)) {
                            Text(model.days[Int(x / 24)].date.monthDayText)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))°")
                        }
                    }
                }
            }
            .chartXSelection(value: $rawX)
            .onChange(of: rawX) { _, x in
                guard let x else { return }
                let index = chart.day(at: x)
                if model.days.indices.contains(index), selected != model.days[index].date {
                    selected = model.days[index].date
                }
            }
            .frame(height: 200)
            .revealsPlotOnAppear()
            .accessibilityLabel("여행 기간 시간별 기온 그래프")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct LegendLine: View {
    let color: Color
    let dashed: Bool
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 16, y: 5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 2] : []))
            .frame(width: 16, height: 10)
            Text(text)
                .lineLimit(1)
        }
    }
}

// MARK: 날짜별 최고·최저 막대

/// 날짜마다 최저~최고 막대. 회색 눈금은 지금(집 최근 3일)의 최저·최고. 막대는 차례로 자란다.
private struct TripRangeList: View {
    let model: TripModel
    @Binding var selected: LocalDate?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// 모든 막대와 기준을 담는 눈금 범위
    private var scale: ClosedRange<Double> {
        let values = model.days.flatMap { [$0.destination.high, $0.destination.low] }.compactMap { $0 }
            + [model.baseline?.high, model.baseline?.low].compactMap { $0 }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 1)...max(high + 1, low)
    }

    var body: some View {
        let scale = scale
        VStack(alignment: .leading, spacing: 6) {
            Text("날짜별 최고·최저")
                .font(.headline)
                .padding(.bottom, 4)
            ForEach(Array(model.days.enumerated()), id: \.element.id) { index, day in
                RangeRow(
                    day: day,
                    scale: scale,
                    baseline: model.baseline,
                    shown: appeared || reduceMotion,
                    isSelected: selected == day.date
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .snappy) { selected = day.date }
                }
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

private struct RangeRow: View {
    let day: TripModel.Day
    let scale: ClosedRange<Double>
    let baseline: HomeBaseline?
    /// false면 막대가 가운데에서 0 너비로 시작한다 (나타날 때 자라는 애니메이션)
    let shown: Bool
    let isSelected: Bool

    var body: some View {
        let dest = day.destination
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.relative ?? day.date.weekdayText)
                    .font(.subheadline.weight(.semibold))
                Text(day.date.monthDayText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, alignment: .leading)
            Group {
                if let sky = dest.sky {
                    Image(systemName: sky.symbolName).symbolRenderingMode(.multicolor)
                } else {
                    Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 24)
            Text(degreesText(dest.low))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            GeometryReader { geo in
                let x = { (v: Double) -> CGFloat in
                    geo.size.width * CGFloat((v - scale.lowerBound) / (scale.upperBound - scale.lowerBound))
                }
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 6)
                    if let low = dest.low, let high = dest.high {
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .orange], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(6, x(high) - x(low)), height: 6)
                            .scaleEffect(x: shown ? 1 : 0.01, anchor: .center)
                            .offset(x: x(low))
                    }
                    if let baseline {
                        ForEach([baseline.low, baseline.high], id: \.self) { value in
                            Rectangle()
                                .fill(Color.secondary.opacity(0.7))
                                .frame(width: 2, height: 14)
                                .offset(x: x(value) - 1)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            Text(degreesText(dest.high))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 40)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        let dest = day.destination
        var parts = ["\(day.label)"]
        if let sky = dest.sky { parts.append(sky.label) }
        parts.append("최고 \(degreesText(dest.high)), 최저 \(degreesText(dest.low))")
        if let headline = dest.outlook.headline { parts.append(headline) }
        return parts.joined(separator: ", ")
    }
}
