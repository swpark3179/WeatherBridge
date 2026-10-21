import Foundation
import Testing
@testable import WeatherCore

/// 서버 `today` 응답(계약 샘플)을 앱 모델로 디코딩할 수 있는지 확인한다.
/// 같은 파일을 server/tests/today_test.ts가 서버 생성 결과와 비교한다.
@Suite struct TodayContractTests {
    private func loadFixture() throws -> TodayResponse {
        let url = try #require(
            Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(TodayResponse.self, from: Data(contentsOf: url))
    }

    @Test func decodesTodayResponse() throws {
        let today = try loadFixture()
        #expect(today.tz == "Asia/Seoul")
        #expect(today.threshold == 30)
        #expect(today.places.map(\.kind) == [.home, .office])
        #expect(today.places.map(\.name) == ["집", "회사"])

        let home = today.places[0]
        #expect(home.highlight)
        #expect(home.hours.count == 4)
        #expect(home.windows.count == 1)
        #expect(home.windows[0].end - home.windows[0].start == 2 * 3600)
        #expect(home.sources.map(\.provider) == ["kma_short", "om_ecmwf", "om_gfs", "om_icon"])
        #expect(home.hours[2].families["kma"] == 60)
        #expect(home.hours[2].providers["om_ecmwf"] == 80)
        #expect(home.hours[2].split)
        #expect(home.hours[3].level == .high)

        #expect(home.tempHistory?.providers == ["om_ecmwf"])
        #expect(home.tempHistory?.temps.count == 28)

        // 7일 보기: 10/20–10/22 (모레는 기상청이 정오에 끝나 3개 예보만)
        let days = try #require(home.days)
        #expect(days.map(\.pop) == [68, 17, 43])
        #expect(days.map(\.rainy) == [true, false, true])
        #expect(days.map(\.total) == [4, 4, 3])
        #expect(zip(days.dropFirst(), days).allSatisfy { $0.date - $1.date == 86400 })
        #expect(days[0].level == .high)

        let office = today.places[1]
        #expect(!office.highlight)
        #expect(office.errors == ["om_icon: timeout"])
        #expect(office.hours[0].families["dwd"] == nil)
        #expect(office.tempHistory == nil)
        #expect(office.days == [])
    }

    /// 기온 비교 이전 서버의 응답(또는 저장해 둔 응답)에는 tempHistory가 없다
    @Test func decodesResponsesWithoutTemperatureHistory() throws {
        var today = try loadFixture()
        for index in today.places.indices {
            today.places[index].tempHistory = nil
        }
        let data = try JSONEncoder().encode(today)
        #expect(!String(decoding: data, as: UTF8.self).contains("tempHistory"))
        let decoded = try JSONDecoder().decode(TodayResponse.self, from: data)
        #expect(decoded.places.allSatisfy { $0.tempHistory == nil })
    }

    /// 7일 보기 이전 서버의 응답(또는 저장해 둔 응답)에는 days가 없다
    @Test func decodesResponsesWithoutDays() throws {
        var today = try loadFixture()
        for index in today.places.indices {
            today.places[index].days = nil
        }
        let data = try JSONEncoder().encode(today)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"days\""))
        let decoded = try JSONDecoder().decode(TodayResponse.self, from: data)
        #expect(decoded.places.allSatisfy { $0.days == nil })
    }

    @Test func briefingMatchesLiveActivityState() throws {
        let briefing = try loadFixture().briefing
        #expect(briefing.state.highlight)
        #expect(briefing.state.headline.hasPrefix("☔"))
        #expect(briefing.state.places.map(\.name) == ["집", "회사"])
        #expect(briefing.state.places[1].rainWindow == nil)
        #expect(briefing.firstHour == 6)
        #expect(!briefing.summary.isEmpty)
    }

    @Test func hoursAreHourlyAndAscending() throws {
        for place in try loadFixture().places {
            let gaps = zip(place.hours.dropFirst(), place.hours).map { $0.t - $1.t }
            #expect(gaps.allSatisfy { $0 == 3600 })
        }
    }

    @Test func roundTrips() throws {
        let today = try loadFixture()
        let data = try JSONEncoder().encode(today)
        #expect(try JSONDecoder().decode(TodayResponse.self, from: data) == today)
    }
}
