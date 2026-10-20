import SwiftUI
import UserNotifications
import WeatherCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = UserSettings(tz: TimeZone.current.identifier)
    @State private var loaded = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var confirmDelete = false

    private static let thresholds = [20, 30, 40, 50, 60]
    private static let weekdays: [(Int, String)] = [(1, "월"), (2, "화"), (3, "수"), (4, "목"), (5, "금"), (6, "토"), (7, "일")]

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                thresholdSection
                commuteSection
                placesSection
                attributionSection
                otherSection
            }
            .navigationTitle("설정")
            .onAppear {
                if !loaded {
                    draft = model.settings
                    loaded = true
                }
            }
            .task { notificationStatus = await NotificationPermission.status() }
            .onChange(of: draft) { old, new in
                guard loaded, old != new else { return }
                model.saveSettingsQuietly(new)
            }
            .onChange(of: draft.summaryEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    await NotificationPermission.request()
                    notificationStatus = await NotificationPermission.status()
                }
            }
            .confirmationDialog("계정을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    Task { await model.deleteAccount() }
                }
            } message: {
                Text("집·회사, 설정, 알림 기록이 서버에서 모두 지워지고 처음 화면으로 돌아갑니다.")
            }
        }
    }

    private var summarySection: some View {
        Section {
            Toggle("매일 요약 알림", isOn: $draft.summaryEnabled)
            if draft.summaryEnabled {
                DatePicker("받을 시각", selection: clockBinding(\.summaryTime), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("요약 알림")
        } footer: {
            if draft.summaryEnabled && notificationStatus == .denied {
                Text("알림 권한이 꺼져 있습니다. 설정 앱 → WeatherBridge → 알림에서 켜 주세요.")
                    .foregroundStyle(.orange)
            } else {
                Text("정한 시각에 집·회사의 오늘 남은 시간 강수 요약을 보내 드려요.")
            }
        }
    }

    private var thresholdSection: some View {
        Section {
            Picker("강조 기준", selection: $draft.threshold) {
                ForEach(Self.thresholds, id: \.self) { value in
                    Text("강수확률 \(value)% 이상").tag(value)
                }
            }
        } header: {
            Text("비 소식 강조")
        } footer: {
            Text("여러 예보의 종합 확률이 이 값 이상이거나, 기상청 60%↑ 또는 두 곳 이상이 60%↑이면 강조합니다.")
        }
    }

    private var commuteSection: some View {
        Section {
            DatePicker("출근 시각", selection: clockBinding(\.commuteTime), displayedComponents: .hourAndMinute)
            HStack(spacing: 6) {
                ForEach(Self.weekdays, id: \.0) { day, label in
                    let on = draft.commuteDays.contains(day)
                    Button(label) {
                        if on {
                            draft.commuteDays.removeAll { $0 == day }
                        } else {
                            draft.commuteDays = (draft.commuteDays + [day]).sorted()
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(on ? .accentColor : .gray)
                    .frame(maxWidth: .infinity)
                }
            }
            Toggle("공휴일에는 쉬기", isOn: $draft.skipHolidays)
        } header: {
            Text("출근")
        } footer: {
            Text("출근 1시간 전부터 잠금화면에 비 소식을 보여주는 기능(다음 업데이트)에 씁니다.")
        }
    }

    private var placesSection: some View {
        Section("장소") {
            ForEach([PlaceKind.home, .office], id: \.self) { kind in
                let place = model.places.first { $0.kind == kind }
                NavigationLink {
                    PlacePickerView(kind: kind, initialName: place?.name) { name, coordinate in
                        try await model.savePlace(kind: kind, name: name, coordinate: coordinate)
                    }
                } label: {
                    LabeledContent {
                        Text(place?.name ?? "등록 안 됨")
                    } label: {
                        Label(kind.defaultName, systemImage: kind.symbolName)
                    }
                }
            }
        }
    }

    private var attributionSection: some View {
        Section {
            Link(destination: URL(string: "https://www.data.go.kr/data/15084084/openapi.do")!) {
                LabeledContent("기상청 단기예보·초단기실황", value: "공공데이터포털")
            }
            Link(destination: URL(string: "https://open-meteo.com/")!) {
                LabeledContent("ECMWF·GFS·ICON 모델", value: "Open-Meteo (CC BY 4.0)")
            }
        } header: {
            Text("날씨 데이터 출처")
        } footer: {
            Text("예보는 서버가 매시 모아 종합합니다. 실제 날씨와 다를 수 있습니다.")
        }
    }

    private var otherSection: some View {
        Section {
            NavigationLink("실험실 (잠금화면 시험)") {
                SpikeView()
            }
            LabeledContent("버전", value: model.appVersion)
            Button("계정 삭제", role: .destructive) {
                confirmDelete = true
            }
        }
    }

    private func clockBinding(_ keyPath: WritableKeyPath<UserSettings, ClockTime>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath].date },
            set: { draft[keyPath: keyPath] = ClockTime(date: $0) }
        )
    }
}
