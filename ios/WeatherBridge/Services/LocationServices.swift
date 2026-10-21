import CoreLocation
import MapKit
import WeatherCore

/// 현재 위치 한 번 받기. 약 1km 정확도면 충분하다(저장도 소수 둘째 자리까지만 한다).
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "위치 권한이 꺼져 있습니다. 설정 앱에서 WeatherBridge의 위치 권한을 켜거나 주소로 검색해 주세요."
            case .unavailable: "현재 위치를 찾지 못했습니다. 잠시 후 다시 시도하거나 주소로 검색해 주세요."
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Coordinate, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// 현재 위치와, 찾을 수 있으면 그 동네 주소("서울특별시 중구 태평로1가"). 주소는 1km로 반올림한 좌표로 찾는다.
    func currentPlace() async throws -> PickedPlace {
        let coordinate = try await currentCoordinate()
        let rounded = coordinate.rounded2
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: rounded.lat, longitude: rounded.lon),
            preferredLocale: Locale(identifier: "ko_KR")
        ).first
        let parts = [placemark?.administrativeArea, placemark?.locality, placemark?.subLocality].compactMap { $0 }
        // "서울특별시 서울특별시"처럼 겹치는 이름은 한 번만
        let address = parts.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }.joined(separator: " ")
        return PickedPlace(
            label: "현재 위치",
            subtitle: address.isEmpty ? nil : address,
            coordinate: coordinate,
            timeZone: placemark?.timeZone
        )
    }

    func currentCoordinate() async throws -> Coordinate {
        continuation?.resume(throwing: CancellationError())
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                finish(.failure(LocationError.denied))
            default:
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<Coordinate, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    // 위치 관리자를 메인 스레드에서 만들었으므로 콜백도 메인 스레드로 온다.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: finish(.failure(LocationError.denied))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let c = locations.last?.coordinate else { return }
            finish(.success(Coordinate(lat: c.latitude, lon: c.longitude)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            finish(.failure(LocationError.unavailable))
        }
    }
}

/// 고른 장소: 이름, 주소, 좌표, (알 수 있으면) 그곳의 시간대
struct PickedPlace: Equatable {
    var label: String
    var subtitle: String?
    var coordinate: Coordinate
    var timeZone: TimeZone?
}

extension PickedPlace {
    /// 이 기기에 기억해 둔 장소 (좌표는 이미 약 1km로 반올림돼 있다)
    init(_ remembered: RememberedPlace) {
        self.init(
            label: remembered.label,
            subtitle: remembered.subtitle,
            coordinate: remembered.coordinate,
            timeZone: remembered.tz.flatMap(TimeZone.init(identifier:))
        )
    }

    func remembered(id: String, tz: String? = nil) -> RememberedPlace {
        RememberedPlace(id: id, label: label, subtitle: subtitle, coordinate: coordinate, tz: tz ?? timeZone?.identifier)
    }
}

/// 주소·장소 이름 검색 (Apple 지도). 한국 주소와 회사·건물 이름을 찾을 수 있다.
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    /// 결과를 먼저 보여줄 지역
    enum Region {
        /// 한반도 중심. 해외 주소도 검색은 되지만 국내 결과를 먼저 보여준다.
        case korea
        /// 지역 편향 없이 (여행지)
        case world
    }

    struct Suggestion: Identifiable, Hashable {
        /// 제목·주소로 만든 고정 id (결과가 바뀔 때 목록이 줄 단위로 움직인다)
        var id: String { "\(title)|\(subtitle)" }
        let title: String
        let subtitle: String
        fileprivate let completion: MKLocalSearchCompletion
    }

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                completer.cancel()
                suggestions = []
                isSearching = false
                failed = false
            } else {
                completer.queryFragment = query
                isSearching = true
            }
        }
    }
    @Published private(set) var suggestions: [Suggestion] = []
    /// 검색어를 바꾼 뒤 결과를 기다리는 중
    @Published private(set) var isSearching = false
    /// 검색이 실패했다 (네트워크 등). 결과가 없는 것과 다르다
    @Published private(set) var failed = false

    private let completer = MKLocalSearchCompleter()

    init(region: Region = .korea) {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        if region == .korea {
            completer.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 36.4, longitude: 127.8),
                span: MKCoordinateSpan(latitudeDelta: 7, longitudeDelta: 7)
            )
        }
    }

    /// 고른 제안의 좌표와 시간대
    func place(for suggestion: Suggestion) async throws -> PickedPlace {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion)).start()
        guard let item = response.mapItems.first else { throw LocationProvider.LocationError.unavailable }
        let c = item.placemark.coordinate
        return PickedPlace(
            label: suggestion.title,
            subtitle: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle,
            coordinate: Coordinate(lat: c.latitude, lon: c.longitude),
            timeZone: item.timeZone
        )
    }

    // 검색 완성기도 메인 스레드에서 만들었으므로 콜백이 메인 스레드로 온다.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            var seen = Set<String>()
            suggestions = completer.results.prefix(8).compactMap { completion in
                let suggestion = Suggestion(title: completion.title, subtitle: completion.subtitle, completion: completion)
                return seen.insert(suggestion.id).inserted ? suggestion : nil
            }
            isSearching = false
            failed = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // 결과가 없을 때도 이 콜백이 온다
        let notFound = (error as? MKError)?.code == .placemarkNotFound
        MainActor.assumeIsolated {
            suggestions = []
            isSearching = false
            failed = !notFound
        }
    }
}
