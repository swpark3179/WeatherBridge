import SwiftUI
import WeatherCore

/// 비교 화면: 장소별로 예보 소스 × 시간 강수확률 히트맵(앞으로 48시간)
struct CompareView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: PlaceKind = .home

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let today = model.today, !today.places.isEmpty {
                        Picker("장소", selection: $selected) {
                            ForEach(today.places) { place in
                                Text(place.name).tag(place.kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        if let place = today.places.first(where: { $0.kind == selected }) ?? today.places.first {
                            let heatmap = HeatmapModel(place: place, tz: today.tz, now: Int(Date().timeIntervalSince1970))
                            HeatmapView(model: heatmap)
                            Legend()
                            if !place.errors.isEmpty {
                                Label("받지 못한 소스: \(place.errors.joined(separator: ", "))", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else if let error = model.todayError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else {
                        ProgressView("예보를 불러오는 중…").frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }
                .padding()
            }
            .navigationTitle("예보 비교")
            .refreshable { await model.refreshToday() }
        }
    }
}

private struct HeatmapView: View {
    let model: HeatmapModel

    private let cellWidth: CGFloat = 34
    private let cellHeight: CGFloat = 30
    private let labelWidth: CGFloat = 86

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // 왼쪽 행 이름은 고정하고 시간 축만 가로로 스크롤한다
            VStack(alignment: .leading, spacing: 2) {
                Color.clear.frame(height: cellHeight)
                ForEach(model.rows) { row in
                    Text(row.label)
                        .font(row.isConsensus ? .caption.bold() : .caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth, height: cellHeight, alignment: .leading)
                }
                Text("합의").font(.caption2).foregroundStyle(.secondary)
                    .frame(width: labelWidth, height: cellHeight, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        ForEach(model.columns) { column in
                            VStack(spacing: 0) {
                                Text(column.dayLabel ?? " ").font(.system(size: 9)).foregroundStyle(.blue)
                                Text("\(column.hour)").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                    ForEach(model.rows) { row in
                        GridRow {
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, value in
                                HeatCell(value: value, emphasized: row.isConsensus)
                                    .frame(width: cellWidth, height: cellHeight)
                            }
                        }
                    }
                    GridRow {
                        ForEach(model.columns) { column in
                            VStack(spacing: 0) {
                                Text(column.agreement ?? "–").font(.system(size: 9))
                                if column.split {
                                    Image(systemName: "arrow.left.and.right").font(.system(size: 8))
                                }
                            }
                            .foregroundStyle(column.split ? .orange : .secondary)
                            .frame(width: cellWidth, height: cellHeight)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("소스별 시간대 강수확률 표")
    }
}

private struct HeatCell: View {
    let value: Int?
    let emphasized: Bool

    var body: some View {
        if let value {
            let level = RainLevel(pop: value)
            Text("\(value)")
                .font(.system(size: 11, weight: emphasized ? .bold : .regular).monospacedDigit())
                .foregroundStyle(level >= .moderate ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(level.color.opacity(level == .clear ? 1 : 0.85), in: RoundedRectangle(cornerRadius: 4))
                .overlay {
                    if emphasized {
                        RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.4), lineWidth: 1)
                    }
                }
        } else {
            Text("–")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

private struct Legend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ForEach(RainLevel.allCases, id: \.self) { level in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(level.color).frame(width: 12, height: 12)
                        Text(level.label).font(.caption2)
                    }
                }
            }
            Text("맨 위 '종합'은 기상청에 가중치를 더 준 평균입니다. '합의'는 강조 기준 이상인 예보 수 / 참여 예보 수, ↔는 예보끼리 40%p 이상 차이 나는 시간입니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
