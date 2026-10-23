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
        // 7일 기온 비교 기준: 모델마다 하나씩, 오늘은 빼고
        #expect(home.recentTemps?.map(\.providers) == [["om_ecmwf"]])
        #expect(home.recentTemps?.first?.temps == [17.1, 18, 19.2, 19.9])

        // 7일 보기: 10/20–10/22 (모레는 기상청이 정오에 끝나 3개 예보만)
        let days = try #require(home.days)
        #expect(days.map(\.pop) == [68, 17, 43])
        #expect(days.map(\.rainy) == [true, false, true])
        #expect(days.map(\.total) == [4, 4, 3])
        #expect(zip(days.dropFirst(), days).allSatisfy { $0.date - $1.date == 86400 })
        #expect(days[0].level == .high)
        // 샘플의 기온은 하루 끝까지 닿지 않아 날짜별 기온이 없다
        #expect(days.allSatisfy { $0.temps == nil })

        // 3일 보기: 어제·오늘·내일. 어제는 비 소식이 없고, 기온은 ECMWF의 어제 06–09시뿐이다
        let around = try #require(home.around)
        #expect(around.count == 3)
        #expect(zip(around.dropFirst(), around).allSatisfy { $0.start - $1.start == 86400 })
        #expect(around[1].start == days[0].date)
        #expect(around[0].rain == nil)
        #expect(around[0].temps?.temps == [17.1, 18, 19.2, 19.9])
        #expect(around[1].rain?.pop == days[0].pop)
        #expect(around[2].rain?.pop == days[1].pop)

        let office = today.places[1]
        #expect(!office.highlight)
        #expect(office.errors == ["om_icon: timeout"])
        #expect(office.hours[0].families["dwd"] == nil)
        #expect(office.tempHistory == nil)
        #expect(office.recentTemps == [])
        #expect(office.days == [])
        #expect(office.around?.count == 3)
        #expect(office.around?.allSatisfy { $0.rain == nil && $0.temps == nil && $0.cloud == nil } == true)
    }

    /// 3일 보기 이전 서버의 응답(또는 저장해 둔 응답)에는 around가 없다
    @Test func decodesResponsesWithoutAround() throws {
        var today = try loadFixture()
        for index in today.places.indices {
            today.places[index].around = nil
        }
        let data = try JSONEncoder().encode(today)
        #expect(!String(decoding: data, as: UTF8.self).contains("around"))
        let decoded = try JSONDecoder().decode(TodayResponse.self, from: data)
        #expect(decoded.places.allSatisfy { $0.around == nil })
        #expect(ThreeDayTemperatureModel(place: decoded.places[0], tz: decoded.tz, now: decoded.generatedAt) == nil)
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

    /// 7일 기온 비교 이전 서버의 응답(또는 저장해 둔 응답)에는 recentTemps와 날짜별 temps가 없다
    @Test func decodesResponsesWithoutWeekTemperatures() throws {
        var today = try loadFixture()
        for index in today.places.indices {
            today.places[index].tempHistory = nil
            today.places[index].recentTemps = nil
            // 3일 보기(around)는 7일 기온 비교보다 나중에 생겼다
            today.places[index].around = nil
            today.places[index].days = today.places[index].days?.map { day in
                var day = day
                day.temps = nil
                return day
            }
        }
        let data = try JSONEncoder().encode(today)
        #expect(!String(decoding: data, as: UTF8.self).contains("temps"))
        #expect(!String(decoding: data, as: UTF8.self).contains("recentTemps"))
        let decoded = try JSONDecoder().decode(TodayResponse.self, from: data)
        #expect(decoded.places.allSatisfy { $0.recentTemps == nil })
        #expect(decoded.places[0].days?.count == 3)
        #expect(decoded.places[0].days?.allSatisfy { $0.temps == nil } == true)
        #expect(WeekTemperatureModel(place: decoded.places[0], tz: decoded.tz, now: decoded.generatedAt) == nil)
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
