import MapKit
import SwiftUI
import WeatherCore

/// 검색 시트 설정: 현재 위치 버튼, 결과를 먼저 보여줄 지역, 검색창 안내
struct PlaceSearchOptions {
    var allowsCurrentLocation = true
    var region: PlaceSearch.Region = .korea
    var prompt = "주소, 건물·회사 이름으로 검색"
}

/// 위치 카드 (Form 한 줄): 지도 핀, 이름, 주소, "바꾸기". 누르면 검색 시트가 열리고,
/// 고르면 시트가 닫힌 뒤 카드가 새 위치로 바뀐다(지도가 옮겨 가고 햅틱).
struct PlaceField: View {
    /// 보여 줄 위치. 없으면 빈 카드
    let place: PickedPlace?
    /// 위치는 모르지만 저장된 이름 (이 기기에 기억이 없을 때: 재설치, 다른 기기에서 등록)
    var savedName: String?
    var options = PlaceSearchOptions()
    let onPick: (PickedPlace) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searching = false
    /// 시트에서 고른 위치. 시트가 다 닫힌 뒤 적용해야 카드가 바뀌는 모습이 보인다
    @State private var pending: PickedPlace?
    @State private var picks = 0

    var body: some View {
        Button {
            searching = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let coordinate = place?.coordinate {
                    PlaceMap(coordinate: coordinate, label: place?.label ?? "")
                        .motionTransition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                HStack(spacing: 12) {
                    if place == nil {
                        Image(systemName: savedName == nil ? "magnifyingglass" : "mappin.slash")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 바뀐 이름·주소는 흐려지며 바뀐다
                    .id(place?.coordinate)
                    .transition(.opacity)
                    Text(place == nil ? "검색" : "바꾸기")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(place == nil ? "위치를 검색합니다" : "다른 위치로 바꿉니다")
        .sheet(isPresented: $searching, onDismiss: applyPending) {
            PlaceSearchSheet(options: options) { pending = $0 }
        }
        .sensoryFeedback(.success, trigger: picks)
    }

    private var title: String {
        place?.label ?? savedName ?? "위치를 골라 주세요"
    }

    private var subtitle: String? {
        if let place { return place.subtitle }
        return savedName == nil ? "주소, 건물 이름으로 찾을 수 있어요" : "지도에 보이려면 다시 골라 주세요"
    }

    private func applyPending() {
        guard let pending else { return }
        self.pending = nil
        picks += 1
        withMotion(Motion.spring, reduceMotion: reduceMotion, reduced: Motion.fade) { onPick(pending) }
    }
}

/// 작은 지도: 고른 곳에 핀. 위치가 바뀌면 카메라가 옮겨 간다. 누르는 것은 카드가 받는다.
private struct PlaceMap: View {
    let coordinate: Coordinate
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition

    init(coordinate: Coordinate, label: String) {
        self.coordinate = coordinate
        self.label = label
        _camera = State(initialValue: Self.position(coordinate))
    }

    var body: some View {
        Map(position: $camera, interactionModes: []) {
            Marker(label, coordinate: CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lon))
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: coordinate) { _, new in
            withMotion(Motion.gentle, reduceMotion: reduceMotion) { camera = Self.position(new) }
        }
    }

    /// 약 4km 범위 (저장은 약 1km 단위)
    private static func position(_ c: Coordinate) -> MapCameraPosition {
        .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        ))
    }
}
