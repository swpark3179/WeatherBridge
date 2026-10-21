import SwiftUI
import WeatherCore

/// 여행 탭: 등록한 여행 목록. 카드를 누르면 날짜별 날씨, 밀거나 길게 누르면 고치기·지우기.
struct TripListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path: [String] = []
    @State private var editor: EditorTarget?
    @State private var deleting: Trip?
    @State private var appeared = false

    /// 편집 시트: 새 여행 또는 고칠 여행
    private enum EditorTarget: Identifiable {
        case new
        case edit(Trip)

        var id: String {
            switch self {
            case .new: "new"
            case let .edit(trip): trip.id
            }
        }

        var trip: Trip? {
            if case let .edit(trip) = self { return trip }
            return nil
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("여행")
                .navigationDestination(for: String.self) { id in
                    TripDetailView(tripID: id)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editor = .new
                        } label: {
                            Label("여행 추가", systemImage: "plus")
                        }
                    }
                }
                .sheet(item: $editor) { target in
                    NavigationStack {
                        TripEditorView(trip: target.trip)
                    }
                }
                .confirmationDialog(
                    "'\(deleting?.name ?? "")' 여행을 지울까요?",
                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                    titleVisibility: .visible,
                    presenting: deleting
                ) { trip in
                    Button("지우기", role: .destructive) {
                        Task { await delete(trip) }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let trips = model.trips {
            let models = trips.models(now: Int(Date().timeIntervalSince1970))
            if models.isEmpty {
                empty
            } else {
                list(models)
            }
        } else if let error = model.tripsError {
            ContentUnavailableView {
                Label("여행을 불러오지 못했습니다", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("다시 시도") { Task { await model.refreshTrips() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if model.isRefreshingTrips {
            ProgressView("불러오는 중…")
        } else {
            empty
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("등록한 여행이 없어요", systemImage: "airplane.departure")
        } description: {
            Text("여행지와 기간을 등록하면 그 기간 여행지와 집의 날씨를 보여드려요. 기온은 지금(집의 최근 3일)과 비교해요.")
        } actions: {
            Button("여행 추가") { editor = .new }
                .buttonStyle(.borderedProminent)
        }
    }

    private func list(_ models: [TripModel]) -> some View {
        let active = models.filter { $0.status != .ended }
        let ended = models.filter { $0.status == .ended }
        return List {
            if let error = model.tripsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .listRowBackground(Color.clear)
            } else if model.tripsIsCached {
                Label("저장해 둔 예보예요. 당겨서 새로 받아요.", systemImage: "clock.arrow.circlepath")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .listRowBackground(Color.clear)
            }
            if !active.isEmpty {
                Section {
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, trip in
                        row(trip, index: index)
                    }
                }
            }
            if !ended.isEmpty {
                Section("지난 여행") {
                    ForEach(Array(ended.enumerated()), id: \.element.id) { index, trip in
                        row(trip, index: active.count + index)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable { await model.refreshTrips() }
        .onAppear { appeared = true }
    }

    private func row(_ trip: TripModel, index: Int) -> some View {
        let shown = appeared || reduceMotion
        return Button {
            path.append(trip.id)
        } label: {
            TripCard(model: trip)
        }
        .buttonStyle(.plain)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .animation(
            reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.25).delay(Double(index) * 0.06),
            value: appeared
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleting = trip.trip
            } label: {
                Label("지우기", systemImage: "trash")
            }
            Button {
                editor = .edit(trip.trip)
            } label: {
                Label("고치기", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("고치기", systemImage: "pencil") { editor = .edit(trip.trip) }
            Button("지우기", systemImage: "trash", role: .destructive) { deleting = trip.trip }
        }
    }

    private func delete(_ trip: Trip) async {
        do {
            try await model.deleteTrip(id: trip.id)
        } catch {
            model.notice = "여행을 지우지 못했습니다: \(AppModel.describe(error))"
        }
    }
}

/// 목록 카드: 목적지, 기간, 배지, 날짜별 하늘·최고/최저, "지금보다 …" 한 줄. 뒤에 첫날 하늘을 옅게 깐다.
private struct TripCard: View {
    let model: TripModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(model.trip.name, systemImage: "airplane")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                TripBadge(model: model)
            }
            Text(model.periodText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if model.status != .ended, model.days.contains(where: \.destination.hasForecast) {
                DayStrip(days: Array(model.days.prefix(7)))
            }
            if let line = model.summaryLine {
                Label(line, systemImage: model.outlook?.symbolName ?? "calendar.badge.clock")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(model.outlook?.tint ?? .secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Color(.secondarySystemGroupedBackground)
                if model.status != .ended, let sky = model.leadSky {
                    WeatherSceneView(sky: sky, isActive: false)
                        .opacity(0.22)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint("날짜별 날씨 보기")
    }
}

/// 날짜마다 요일, 하늘 아이콘, 최고/최저
private struct DayStrip: View {
    let days: [TripModel.Day]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Text(day.relative ?? day.date.weekdayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let sky = day.destination.sky {
                        Image(systemName: sky.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                            .frame(height: 24)
                    } else {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.tertiary)
                            .font(.title3)
                            .frame(height: 24)
                    }
                    Text(degreesText(day.destination.high))
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(degreesText(day.destination.low))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
