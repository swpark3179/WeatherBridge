import SwiftUI
import WeatherCore

/// 처음 실행: 집 → 회사 → 요약 알림. 이미 등록된 장소는 건너뛴다.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step: Step?

    enum Step {
        case home, office, summary
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step ?? firstStep {
                case .home:
                    PlacePickerView(kind: .home, saveTitle: "다음") { name, coordinate in
                        try await model.savePlace(kind: .home, name: name, coordinate: coordinate)
                        step = model.office == nil ? .office : .summary
                    }
                case .office:
                    PlacePickerView(kind: .office, saveTitle: "다음") { name, coordinate in
                        try await model.savePlace(kind: .office, name: name, coordinate: coordinate)
                        step = .summary
                    }
                case .summary:
                    SummarySetupView()
                }
            }
            .safeAreaInset(edge: .top) { intro }
        }
        .onAppear {
            if step == nil { step = firstStep }
        }
    }

    private var firstStep: Step {
        model.home == nil ? .home : model.office == nil ? .office : .summary
    }

    @ViewBuilder
    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(introText)
            if let notice = model.notice {
                Text(notice).foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var introText: String {
        switch step ?? firstStep {
        case .home: "1/3 · 집과 회사의 시간대별 강수확률을 여러 예보에서 모아 알려 드려요. 먼저 집 위치를 정해 주세요."
        case .office: "2/3 · 회사(또는 자주 가는 곳) 위치를 정해 주세요."
        case .summary: "3/3 · 매일 받을 요약 알림 시각을 정해 주세요."
        }
    }
}

/// 요약 알림 시각 정하기. 켜면 알림 권한을 이때 묻는다.
struct SummarySetupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var enabled = true
    @State private var time = ClockTime(hour: 7, minute: 0).date
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("매일 요약 알림 받기", isOn: $enabled)
                if enabled {
                    DatePicker("받을 시각", selection: $time, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("정한 시각에 집·회사의 오늘 강수 요약을 알림으로 보내 드려요. 설정에서 언제든 바꿀 수 있습니다.")
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await finish() }
                } label: {
                    HStack {
                        Text("시작하기").bold()
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(busy)
            }
        }
        .navigationTitle("요약 알림")
        .onAppear {
            enabled = model.settings.summaryEnabled || !model.hasSavedSettings
            time = model.settings.summaryTime.date
        }
    }

    private func finish() async {
        busy = true
        defer { busy = false }
        var settings = model.settings
        settings.summaryEnabled = enabled
        settings.summaryTime = ClockTime(date: time)
        do {
            if enabled {
                let granted = await NotificationPermission.request()
                if !granted {
                    error = "알림 권한이 꺼져 있어 알림이 보이지 않습니다. 설정 앱 → WeatherBridge → 알림에서 켜 주세요."
                }
            }
            try await model.saveSettings(settings)
            model.finishOnboarding()
        } catch {
            self.error = "저장하지 못했습니다: \(AppModel.describe(error))"
        }
    }
}

extension ClockTime {
    /// 오늘 날짜의 이 시각 (DatePicker용)
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    init(date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}
