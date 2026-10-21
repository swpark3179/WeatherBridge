import SwiftUI
import WeatherCore

/// 집·회사 위치 고르기: 이름과 위치 카드(누르면 현재 위치 또는 주소·장소 검색). 저장은 약 1km 단위로만 한다.
/// 이 기기에서 전에 고른 위치가 있으면 처음부터 보여 주고, 이름만 바꿔도 저장할 수 있다.
struct PlacePickerView: View {
    let kind: PlaceKind
    var initialName: String?
    /// 이 기기에서 마지막으로 고른 위치 (서버는 좌표를 돌려주지 않는다)
    var remembered: RememberedPlace?
    var saveTitle = "저장"
    /// 저장하면 화면을 닫는다 (설정에서 열었을 때)
    var dismissOnSave = false
    let onSave: (_ name: String, _ place: PickedPlace) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picked: PickedPlace?
    @State private var busy = false
    @State private var error: String?
    @State private var saves = 0

    /// 저장할 위치: 새로 고른 것, 없으면 기억해 둔 것
    private var location: PickedPlace? {
        picked ?? remembered.map { PickedPlace($0) }
    }

    var body: some View {
        Form {
            Section("이름") {
                TextField(kind.defaultName, text: $name)
                    .submitLabel(.done)
            }

            Section {
                // 서버에 등록돼 있지만 이 기기에 기억이 없으면(재설치 등) "저장된 위치"로 보인다
                PlaceField(place: location, savedName: initialName.map { _ in "저장된 위치" }) { picked = $0 }
            } header: {
                Text("위치")
            } footer: {
                Text("좌표는 약 1km 단위로 반올림해 저장하며, 예보 조회에만 씁니다.")
            }

            if let error {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(saveTitle).bold()
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(location == nil || busy)
            }
        }
        .navigationTitle(kind.title)
        .onAppear {
            if name.isEmpty { name = initialName ?? kind.defaultName }
        }
        .sensoryFeedback(.success, trigger: saves)
        .motion(value: error)
    }

    private func save() async {
        guard let location else { return }
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        defer { busy = false }
        do {
            try await onSave(finalName.isEmpty ? kind.defaultName : String(finalName.prefix(30)), location)
            error = nil
            saves += 1
            if dismissOnSave { dismiss() }
        } catch {
            self.error = "저장하지 못했습니다: \(AppModel.describe(error))"
        }
    }
}

extension PlaceKind {
    var defaultName: String {
        switch self {
        case .home: "집"
        case .office: "회사"
        case .trip: "여행지"
        }
    }

    var title: String {
        switch self {
        case .home: "집 위치"
        case .office: "회사 위치"
        case .trip: "여행지"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .office: "building.2.fill"
        case .trip: "airplane"
        }
    }
}
