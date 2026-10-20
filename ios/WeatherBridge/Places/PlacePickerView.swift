import SwiftUI
import WeatherCore

/// 집·회사 위치 고르기: 현재 위치 또는 주소·장소 검색. 저장은 약 1km 단위로만 한다.
struct PlacePickerView: View {
    let kind: PlaceKind
    var initialName: String?
    var saveTitle = "저장"
    let onSave: (_ name: String, _ coordinate: Coordinate) async throws -> Void

    @StateObject private var search = PlaceSearch()
    @State private var location = LocationProvider()
    @State private var name = ""
    @State private var picked: (label: String, coordinate: Coordinate)?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("이름") {
                TextField(kind.defaultName, text: $name)
                    .submitLabel(.done)
            }

            Section {
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    Label("현재 위치 사용", systemImage: "location.fill")
                }
                .disabled(busy)

                TextField("주소, 건물·회사 이름으로 검색", text: $search.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ForEach(search.suggestions) { suggestion in
                    Button {
                        Task { await choose(suggestion) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(busy)
                }
            } header: {
                Text("위치")
            } footer: {
                Text("좌표는 약 1km 단위로 반올림해 저장하며, 예보 조회에만 씁니다.")
            }

            if let picked {
                Section("선택한 위치") {
                    Label(picked.label, systemImage: "mappin.and.ellipse")
                }
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
                .disabled(picked == nil || busy)
            }
        }
        .navigationTitle(kind.title)
        .onAppear {
            if name.isEmpty { name = initialName ?? kind.defaultName }
        }
    }

    private func useCurrentLocation() async {
        busy = true
        defer { busy = false }
        do {
            let coordinate = try await location.currentCoordinate()
            picked = ("현재 위치", coordinate)
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func choose(_ suggestion: PlaceSearch.Suggestion) async {
        busy = true
        defer { busy = false }
        do {
            let coordinate = try await search.coordinate(for: suggestion)
            picked = (suggestion.title, coordinate)
            error = nil
        } catch {
            self.error = "위치를 찾지 못했습니다. 다른 이름으로 검색해 주세요."
        }
    }

    private func save() async {
        guard let picked else { return }
        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        defer { busy = false }
        do {
            try await onSave(finalName.isEmpty ? kind.defaultName : String(finalName.prefix(30)), picked.coordinate)
            error = nil
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
