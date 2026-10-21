import Foundation
import WeatherCore

/// 마지막 today 응답을 Caches 폴더에 둔다. 앱을 열자마자, 또는 오프라인일 때 보여준다.
/// (UserDefaults는 쓰지 않는다 — 개인정보 매니페스트에 사유가 필요해진다)
enum TodayCache {
    private static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("today_response.json")
    }

    static func load() -> TodayResponse? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TodayResponse.self, from: data)
    }

    static func save(_ today: TodayResponse) {
        guard let url, let data = try? JSONEncoder().encode(today) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
