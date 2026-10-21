import Foundation
import WeatherCore

/// 값 하나를 JSON 파일로 둔다. 마지막 서버 응답은 Caches 폴더(앱을 열자마자, 또는 오프라인일 때 보여준다),
/// OS가 지우면 안 되는 기기 기록은 Application Support 폴더(백업에서는 뺀다)에 둔다.
/// (UserDefaults는 쓰지 않는다 — 개인정보 매니페스트에 사유가 필요해진다)
struct FileCache<Value: Codable> {
    let name: String
    var directory: FileManager.SearchPathDirectory = .cachesDirectory

    private var url: URL? {
        FileManager.default.urls(for: directory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    func load() -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard var url, let data = try? JSONEncoder().encode(value) else { return }
        // Application Support 폴더는 처음에는 없다
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        if directory != .cachesDirectory {
            // 세션이 이 기기 키체인에만 있어(D19) 다른 기기로 옮겨도 쓸모가 없다
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum ResponseCache {
    static let today = FileCache<TodayResponse>(name: "today_response.json")
    static let trips = FileCache<TripsResponse>(name: "trips_response.json")
}

enum DeviceStore {
    /// 고른 장소의 이름·주소·약 1km 좌표 (다시 열었을 때 지도에 보여 준다, D27)
    static let placeMemory = FileCache<PlaceMemory>(name: "place_memory.json", directory: .applicationSupportDirectory)
}
