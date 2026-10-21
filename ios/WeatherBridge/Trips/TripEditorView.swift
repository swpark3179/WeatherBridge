import SwiftUI
import WeatherCore

/// 여행 등록·고치기: 목적지(국내·해외 검색), 이름, 기간(목적지 날짜).
struct TripEditorView: View {
    /// 고칠 여행. nil이면 새 여행
    let trip: Trip?

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// 고른 장소 이름으로 채운 이름. 사용자가 이름을 바꾸지 않았으면 다른 장소를 고를 때 따라 바뀐다.
    @State private var autoName = ""
    @State private var picked: PickedPlace?
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.startOfDay(for: .now)
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    /// 서버가 받는 가장 긴 여행 (31일)
    private static let maxNights = 30

    var body: some View {
        Form {
            Section("이름") {
                TextField("예: 삿포로", text: $name)
                    .submitLabel(.done)
            }

            if let trip, picked == nil {
                Section {
                    Label(trip.name, systemImage: "mappin.and.ellipse")
                    LabeledContent("시간대", value: timeZoneName(trip.tz))
                } header: {
                    Text("목적지")
                } footer: {
                    Text("다른 곳으로 바꾸려면 아래에서 검색하세요.")
                }
            }

            PlaceSearchSection(
                picked: $picked,
                allowsCurrentLocation: false,
                region: .world,
                prompt: "도시, 주소, 장소 이름으로 검색",
                footer: "국내·해외 모두 됩니다. 좌표는 약 1km 단위로 반올림해 저장하며, 예보 조회에만 씁니다.",
                busy: $busy,
                error: $error
            )

            Section {
                DatePicker("출발", selection: $start, in: startRange, displayedComponents: .date)
                DatePicker("돌아오는 날", selection: $end, in: start...lastDay(from: start), displayedComponents: .date)
            } header: {
                Text("기간")
            } footer: {
                Text("여행지 날짜 기준이에요. 예보는 출발 16일 전부터 보이고, 기간은 31일까지 등록할 수 있어요.")
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(trip == nil ? "여행 추가" : "여행 고치기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("취소") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if busy {
                    ProgressView()
                } else {
                    Button("저장") { Task { await save() } }
                        .bold()
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(busy)
        .onAppear(perform: load)
        .onChange(of: picked) { _, new in
            guard let new, name.isEmpty || name == autoName else { return }
            name = String(new.label.prefix(30))
            autoName = name
        }
        .onChange(of: start) { _, new in
            if end < new { end = new }
            let last = lastDay(from: new)
            if end > last { end = last }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !busy && !trimmedName.isEmpty && (picked != nil || trip != nil)
    }

    /// 어제부터 1년 뒤까지 (서버 검사와 같다). 이미 시작한 여행을 고칠 때는 원래 출발일도 고를 수 있다.
    private var startRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var first = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        if let trip {
            first = min(first, trip.startDate.date(in: calendar))
        }
        let last = calendar.date(byAdding: .day, value: 365, to: today) ?? today
        return first...max(first, last)
    }

    private func lastDay(from start: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: Self.maxNights, to: start) ?? start
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let trip else { return }
        let calendar = Calendar.current
        name = trip.name
        autoName = trip.name
        start = trip.startDate.date(in: calendar)
        end = trip.endDate.date(in: calendar)
    }

    private func save() async {
        var destination: (coordinate: Coordinate, tz: String)?
        if let picked {
            guard let tz = Self.timeZone(for: picked) else {
                error = "이 장소의 시간대를 알 수 없어요. 가까운 도시 이름으로 다시 검색해 주세요."
                return
            }
            destination = (picked.coordinate, tz)
        }
        // 날짜 고르기는 기기 달력으로 보이므로 같은 달력에서 날짜만 꺼낸다(시간대 변환 없이)
        let calendar = Calendar.current
        busy = true
        defer { busy = false }
        do {
            try await model.saveTrip(
                id: trip?.id,
                name: trimmedName,
                destination: destination,
                start: LocalDate(start, calendar: calendar),
                end: LocalDate(end, calendar: calendar)
            )
            error = nil
            dismiss()
        } catch {
            self.error = "저장하지 못했습니다: \(AppModel.describe(error))"
        }
    }

    /// 지도 검색 결과의 시간대. 없으면 한국 안에서만 서울로 본다(해외를 기기 시간대로 잘못 저장하지 않게).
    static func timeZone(for place: PickedPlace) -> String? {
        if let tz = place.timeZone { return tz.identifier }
        let c = place.coordinate
        return (32.5...39).contains(c.lat) && (124...132).contains(c.lon) ? "Asia/Seoul" : nil
    }
}
