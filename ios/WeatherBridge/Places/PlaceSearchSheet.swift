import SwiftUI
import WeatherCore

/// 위치 검색 시트: 현재 위치(선택) 또는 주소·장소 검색. 줄을 누르면 좌표를 받아 `onPick`에 넘기고 닫힌다.
/// 좌표를 받는 동안 다른 줄은 막고, 그 사이 닫으면 결과를 버린다. 지도가 바로 찾지 못해 넓혀 찾는 동안은
/// 줄 아래에 "주변 주소로 찾는 중…"을 보인다.
struct PlaceSearchSheet: View {
    let options: PlaceSearchOptions
    let onPick: (PickedPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var search: PlaceSearch
    @State private var location = LocationProvider()
    @State private var searchPresented = false
    /// 좌표를 받는 중인 줄 (`Suggestion.id`, 현재 위치는 `currentLocationID`)
    @State private var resolving: String?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    /// 좌표를 받는 데 오래 걸린다 (넓혀 찾는 중)
    @State private var slow = false

    private static let currentLocationID = "current-location"

    init(options: PlaceSearchOptions, onPick: @escaping (PickedPlace) -> Void) {
        self.options = options
        self.onPick = onPick
        _search = StateObject(wrappedValue: PlaceSearch(region: options.region))
    }

    var body: some View {
        NavigationStack {
            List {
                if options.allowsCurrentLocation && search.query.isEmpty {
                    Section {
                        Button {
                            pick(Self.currentLocationID) { try await location.currentPlace() }
                        } label: {
                            row(title: "현재 위치 사용", subtitle: "약 1km 단위로만 저장해요", systemImage: "location.fill",
                                id: Self.currentLocationID)
                        }
                        .disabled(resolving != nil)
                    }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                if !search.suggestions.isEmpty {
                    Section {
                        ForEach(search.suggestions) { suggestion in
                            Button {
                                pick(suggestion.id) { try await search.place(for: suggestion) }
                            } label: {
                                row(title: suggestion.title, subtitle: suggestion.subtitle, systemImage: "mappin.circle.fill",
                                    id: suggestion.id)
                            }
                            .disabled(resolving != nil)
                        }
                    } header: {
                        Text("검색 결과")
                    }
                }
            }
            .overlay { status }
            .motion(value: search.suggestions.map(\.id))
            .motion(value: error)
            .searchable(text: $search.query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: options.prompt)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("위치 검색")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .task { searchPresented = true }
        .onDisappear { task?.cancel() }
        .onChange(of: search.query) { error = nil }
        .task(id: resolving) {
            slow = false
            guard resolving != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { slow = true }
        }
    }

    /// 검색 중, 결과 없음, 검색 실패, 처음 안내
    @ViewBuilder
    private var status: some View {
        let query = search.query.trimmingCharacters(in: .whitespaces)
        if search.suggestions.isEmpty {
            if query.isEmpty {
                if !options.allowsCurrentLocation {
                    ContentUnavailableView(
                        "어디로 가세요?",
                        systemImage: "magnifyingglass",
                        description: Text("도시, 주소, 장소 이름으로 검색하세요. 국내·해외 모두 됩니다.")
                    )
                }
            } else if search.isSearching {
                ProgressView("찾는 중…")
            } else if search.failed {
                ContentUnavailableView(
                    "검색하지 못했어요",
                    systemImage: "wifi.exclamationmark",
                    description: Text("인터넷 연결을 확인하고 다시 입력해 주세요.")
                )
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func row(title: String, subtitle: String, systemImage: String, id: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if resolving == id, slow, id != Self.currentLocationID {
                    Text("주변 주소로 찾는 중…").font(.caption).foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .motion(value: slow)
            Spacer(minLength: 4)
            if resolving == id {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
    }

    /// 줄 하나의 좌표를 받는다. 받으면 넘기고 닫고, 실패하면 시트 안에서 알린다.
    private func pick(_ id: String, resolve: @escaping () async throws -> PickedPlace) {
        guard resolving == nil else { return }
        resolving = id
        error = nil
        task = Task {
            defer { resolving = nil }
            do {
                let place = try await resolve()
                guard !Task.isCancelled else { return }
                onPick(place)
                dismiss()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.error = id == Self.currentLocationID
                    ? error.localizedDescription
                    : "위치를 찾지 못했습니다. 다른 이름으로 검색해 주세요."
            }
        }
    }
}
