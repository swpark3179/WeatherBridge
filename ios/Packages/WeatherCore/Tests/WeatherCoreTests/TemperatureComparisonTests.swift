import Foundation
import Testing
@testable import WeatherCore

@Suite struct TemperatureComparisonTests {
    /// 2026-10-20(화) 00:00 KST
    private let todayStart = 1_792_422_000
    /// 2026-10-20 06:10 KST (계약 샘플의 generatedAt)
    private var now: Int { todayStart + 6 * 3600 + 600 }

    private func fixture() throws -> TodayResponse {
        let url = try #require(Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(TodayResponse.self, from: Data(contentsOf: url))
    }

    /// 7일 전 0시부터 오늘 자정까지 매시 기온: 10° + 시×0.25° + 그 날의 더한 값 (`offsets[n]` = n일 전)
    private func samplePlace(offsets: [Double]) throws -> TodayPlace {
        var place = try fixture().places[0]
        let start = todayStart - 7 * 86400
        let temps = (0..<(8 * 24)).map { i -> Double? in
            let daysAgo = 7 - i / 24
            return 10 + Double(i % 24) * 0.25 + offsets[daysAgo]
        }
        place.tempHistory = TemperatureHistory(providers: ["om_ecmwf", "om_icon"], start: start, temps: temps)
        return place
    }

    @Test func deltaTextsUseTheShownWholeDegrees() {
        let similar = TemperatureDelta(today: 20.4, baseline: 19.6)
        #expect(similar.degrees == 0 && similar.isSimilar)
        #expect(similar.signedText == "0°")
        #expect(similar.sentence(.yesterday) == "어제와 비슷해요")
        #expect(similar.sentence(.week) == "최근 7일 평균과 비슷해요")
        #expect(similar.feeling == nil)
        // 0.6° 차이지만 보이는 값은 13°와 15°라 2° 낮다고 말한다
        let shown = TemperatureDelta(today: 13.4, baseline: 14.6)
        #expect(shown.degrees == -2)
        #expect(shown.sentence(.yesterday) == "어제보다 2° 낮아요")
        #expect(TemperatureDelta(today: 15, baseline: 16).isSimilar)
    }

    @Test(arguments: [
        (8.0, 14.0, "−6°", "어제보다 6° 낮아요", "많이 추워요"),
        (12.0, 9.0, "+3°", "어제보다 3° 높아요", "조금 포근해요"),
        (18.0, 21.0, "−3°", "어제보다 3° 낮아요", "조금 선선해요"),
        (22.0, 15.0, "+7°", "어제보다 7° 높아요", "많이 따뜻해요"),
        (29.0, 33.0, "−4°", "어제보다 4° 낮아요", "조금 덜 더워요"),
        (31.0, 25.0, "+6°", "어제보다 6° 높아요", "훨씬 더 더워요"),
    ])
    func feelingDependsOnTodaysTemperature(today: Double, baseline: Double, signed: String, sentence: String, feeling: String) {
        let delta = TemperatureDelta(today: today, baseline: baseline)
        #expect(delta.signedText == signed)
        #expect(delta.sentence(.yesterday) == sentence)
        #expect(delta.feeling == feeling)
    }

    @Test func baselineNames() {
        #expect(TemperatureBaseline.allCases.map(\.label) == ["어제", "최근 3일", "최근 7일"])
        #expect(TemperatureBaseline.allCases.map(\.days) == [1, 3, 7])
        #expect(TemperatureDelta(today: 10, baseline: 13).sentence(.threeDays) == "최근 3일 평균보다 3° 낮아요")
    }

    @Test func historyLooksUpTheHourThatContainsATime() {
        let history = TemperatureHistory(providers: ["om_ecmwf"], start: todayStart, temps: [10, nil, 12])
        #expect(history.temp(at: todayStart + 1800) == 10)
        #expect(history.temp(at: todayStart + 3600) == nil)
        #expect(history.temp(at: todayStart + 2 * 3600) == 12)
        #expect(history.temp(at: todayStart - 1) == nil)
        #expect(history.temp(at: todayStart + 3 * 3600) == nil)
    }

    @Test func comparesTodayWithYesterdayHourByHour() throws {
        let place = try samplePlace(offsets: [0, 3, 6, 3, 1, 1, 1, 1])
        let model = try #require(TemperatureComparisonModel(place: place, tz: "Asia/Seoul", now: now, baseline: .yesterday))
        #expect(model.hours.count == 24)
        #expect(model.hours.map(\.hour) == Array(0..<24))
        #expect(model.hours[0].t == todayStart)
        #expect(model.hours.allSatisfy { $0.delta?.degrees == -3 })
        #expect(model.hours[6].low == model.hours[6].high)

        let current = try #require(model.current)
        #expect(current.t == todayStart + 6 * 3600)
        #expect(current.today == 11.5 && current.baseline == 14.5)
        #expect(model.headline == TemperatureComparisonModel.Headline(subject: "지금", delta: TemperatureDelta(today: 11.5, baseline: 14.5), text: "어제보다 3° 낮아요"))
        #expect(model.headline?.delta.feeling == "조금 추워요")

        #expect(model.high == TemperatureComparisonModel.Extreme(today: 15.75, baseline: 18.75))
        #expect(model.low == TemperatureComparisonModel.Extreme(today: 10, baseline: 13))
        #expect(model.baselineDays == 1)
        #expect(model.providers == ["om_ecmwf", "om_icon"])
        #expect(model.valueRange == 9...20)
    }

    @Test func recentDaysAverageWithARange() throws {
        let place = try samplePlace(offsets: [0, 3, 6, 3, 1, 1, 1, 1])
        let three = try #require(TemperatureComparisonModel(place: place, tz: "Asia/Seoul", now: now, baseline: .threeDays))
        let hour = try #require(three.current)
        // 1–3일 전 같은 시각: 14.5, 17.5, 14.5
        #expect(hour.baseline == 15.5)
        #expect(hour.low == 14.5 && hour.high == 17.5)
        #expect(three.headline?.text == "최근 3일 평균보다 4° 낮아요")
        #expect(three.high == TemperatureComparisonModel.Extreme(today: 15.75, baseline: 19.75))
        #expect(three.baselineDays == 3)

        let week = try #require(TemperatureComparisonModel(place: place, tz: "Asia/Seoul", now: now, baseline: .week))
        #expect(week.baselineDays == 7)
        #expect(week.current?.low == 12.5 && week.current?.high == 17.5)
    }

    @Test func shortHistoryUsesTheDaysItHas() throws {
        // 어제와 오늘만 있다
        var place = try samplePlace(offsets: [0, 3, 6, 3, 1, 1, 1, 1])
        let history = try #require(place.tempHistory)
        place.tempHistory = TemperatureHistory(
            providers: history.providers,
            start: todayStart - 86400,
            temps: Array(history.temps.suffix(48))
        )
        let week = try #require(TemperatureComparisonModel(place: place, tz: "Asia/Seoul", now: now, baseline: .week))
        #expect(week.baselineDays == 1)
        #expect(week.current?.baseline == 14.5)
        #expect(week.headline?.text == "최근 7일 평균보다 3° 낮아요")
    }

    @Test func nothingToCompareWithoutPastValues() throws {
        let today = try fixture()
        // 이전 서버 응답이나 Open-Meteo 기온이 없는 장소
        #expect(TemperatureComparisonModel(place: today.places[1], tz: today.tz, now: now, baseline: .yesterday) == nil)

        var place = try samplePlace(offsets: [0, 3, 6, 3, 1, 1, 1, 1])
        let history = try #require(place.tempHistory)
        place.tempHistory = TemperatureHistory(providers: history.providers, start: todayStart, temps: Array(history.temps.suffix(24)))
        #expect(TemperatureComparisonModel(place: place, tz: "Asia/Seoul", now: now, baseline: .yesterday) == nil)
    }

    @Test func contractSampleComparesTheMorningWithYesterday() throws {
        let today = try fixture()
        let home = today.places[0]
        let history = try #require(home.tempHistory)
        #expect(history.providers == ["om_ecmwf"])
        #expect(history.start == todayStart - 18 * 3600)

        let model = try #require(TemperatureComparisonModel(place: home, tz: today.tz, now: today.generatedAt, baseline: .yesterday))
        // 06시: 오늘 14.6°(15°) · 어제 17.1°(17°)
        #expect(model.headline?.subject == "지금")
        #expect(model.headline?.text == "어제보다 2° 낮아요")
        #expect(model.headline?.delta.feeling == "조금 선선해요")
        #expect(model.hours.compactMap(\.delta).map(\.degrees) == [-2, -3, -3, -4])
        // 오늘 값이 06–09시뿐이라 하루 최고·최저는 구하지 않는다
        #expect(model.high == nil && model.low == nil)
    }

    @Test func headlineFallsBackToTheDailyHigh() throws {
        var place = try samplePlace(offsets: [0, 3, 6, 3, 1, 1, 1, 1])
        let history = try #require(place.tempHistory)
        var temps = history.temps
        temps[7 * 24 + 6] = nil // 오늘 06시
        place.tempHistory = TemperatureHistory(providers: history.providers, start: history.start, temps: temps)
        let model = try #require(TemperatureComparisonModel(place: place, tz: "Asia/Seoul", now: now, baseline: .yesterday))
        #expect(model.current?.delta == nil)
        #expect(model.headline?.subject == "최고 기온")
        #expect(model.headline?.text == "어제보다 3° 낮아요")
    }

    @Test func dayStepsKeepTheWallClockAcrossDaylightSaving() {
        let newYork = LocalClock(tz: "America/New_York")
        let noon = 1_793_552_400 // 2026-11-01 12:00 EST, 서머타임이 끝난 날
        #expect(newYork.addingDays(-1, to: noon) == noon - 25 * 3600)
        #expect(newYork.hour(newYork.addingDays(-1, to: noon)) == 12)
        #expect(newYork.startOfDay(noon) == noon - 13 * 3600)
        let seoul = LocalClock(tz: "Asia/Seoul")
        #expect(seoul.startOfDay(now) == todayStart)
        #expect(seoul.addingDays(-7, to: todayStart) == todayStart - 7 * 86400)
    }
}
