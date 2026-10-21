import Foundation
import WeatherCore

/// 마지막 서버 응답을 Caches 폴더에 둔다. 앱을 열자마자, 또는 오프라인일 때 보여준다.
/// (UserDefaults는 쓰지 않는다 — 개인정보 매니페스트에 사유가 필요해진다)
struct FileCache<Value: Codable> {
    let name: String

    private var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    func load() -> Value? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
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
