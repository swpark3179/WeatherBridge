import Foundation
import Testing
@testable import WeatherCore

@Suite struct ThreeDayTemperatureTests {
    /// 2026-10-20(화) 00:00 KST
    private let todayStart = 1_792_422_000
    /// 2026-10-20 14:10 KST
    private var now: Int { todayStart + 14 * 3600 + 600 }
    private let tz = "Asia/Seoul"
    private let models = ["om_ecmwf", "om_gfs", "om_icon"]

    /// 03시 최저, 15시 최고인 하루 24시간 기온
    private func shape(high: Double, low: Double) -> [Double?] {
        let mid = (high + low) / 2
        let amp = (high - low) / 2
        return (0..<24).map { mid + amp * sin(2 * Double.pi * Double($0 - 9) / 24) }
    }

    private func day(start: Int, _ values: [Double?], providers: [String]? = nil, firstHour: Int = 0) -> TripDayWeather {
        TripDayWeather(
            start: start,
            rain: nil,
            cloud: nil,
            snowCm: nil,
            temps: TemperatureHistory(providers: providers ?? models, start: start + firstHour, temps: values)
        )
    }

    /// 어제 24/14°, 오늘 21/12°, 내일 22/15°
    private func sample() -> [TripDayWeather] {
        [
            day(start: todayStart - 86400, shape(high: 24, low: 14)),
            day(start: todayStart, shape(high: 21, low: 12)),
            day(start: todayStart + 86400, shape(high: 22, low: 15)),
        ]
    }

    private func place(_ around: [TripDayWeather]?) throws -> TodayPlace {
        let url = try #require(Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures"))
        var place = try JSONDecoder().decode(TodayResponse.self, from: Data(contentsOf: url)).places[0]
        place.around = around
        return place
    }

    @Test func eachDayIsComparedWithTheDayBefore() throws {
        let model = try #require(ThreeDayTemperatureModel(place: try place(sample()), tz: tz, now: now))
        #expect(model.days.map(\.label) == ["어제", "오늘", "내일"])
        #expect(model.days.map(\.offset) == [-1, 0, 1])
        #expect(model.days.map(\.dateText) == ["10/19 월", "10/20 화", "10/21 수"])
        #expect(model.days.map(\.high) == [24, 21, 22])
        #expect(model.days.map(\.low) == [14, 12, 15])
        #expect(model.days.map(\.modelCount) == [3, 3, 3])
        // 어제는 견줄 전날이 없다
        #expect(model.days[0].outlook.headline == nil)
        // 하루 가운데 값 16.5°(17°) vs 19°
        #expect(model.days[1].outlook.headline == "어제보다 조금 선선해요")
        // 숫자는 어제 값에서 굴러간다
        #expect(model.days[1].outlook.high?.baseline == 24)
        #expect(model.days[1].outlook.low?.baseline == 14)
        // 최고는 비슷(+1°), 최저는 +3°: 하루 가운데 값 18.5°(19°) vs 16.5°(17°)
        #expect(model.days[2].outlook.headline == "오늘보다 조금 따뜻해요")
        #expect(model.providers == models)
    }

    @Test func daysWithDifferentModelsAreNotCompared() throws {
        var around = sample()
        around[2] = day(start: todayStart + 86400, shape(high: 22, low: 15), providers: ["om_ecmwf", "om_gfs"])
        let model = try #require(ThreeDayTemperatureModel(place: try place(around), tz: tz, now: now))
        #expect(model.days[2].outlook.headline == nil)
        #expect(model.days[2].outlook.high == nil)
        #expect(model.days[2].high == 22 && model.days[2].low == 15)
        #expect(model.days[2].modelCount == 2)
        #expect(model.days[1].outlook.headline == "어제보다 조금 선선해요")
    }

    @Test func headlineComparesNowWithTheSameHourYesterday() throws {
        let model = try #require(ThreeDayTemperatureModel(place: try place(sample()), tz: tz, now: now))
        let headline = try #require(model.headline)
        #expect(headline.hour == 14)
        // 14시: 오늘 20.8°(21°), 어제 23.8°(24°), 내일 21.9°(22°)
        #expect(Int(headline.now.rounded()) == 21)
        #expect(headline.yesterday.map { Int($0.rounded()) } == 24)
        #expect(headline.tomorrow.map { Int($0.rounded()) } == 22)
        #expect(headline.delta?.degrees == -3)
        #expect(headline.text == "어제 이맘때보다 3° 낮아요")
        #expect(headline.cardText == "지금 어제보다 3° 낮아요")

        var similar = sample()
        similar[0] = day(start: todayStart - 86400, shape(high: 21, low: 12))
        let same = try #require(ThreeDayTemperatureModel(place: try place(similar), tz: tz, now: now)?.headline)
        #expect(same.text == "어제 이맘때와 비슷해요")
        #expect(same.cardText == "지금 어제와 비슷해요")
    }

    @Test func headlineWithoutYesterdayOrNow() throws {
        var around = sample()
        around[0].temps = nil
        let model = try #require(ThreeDayTemperatureModel(place: try place(around), tz: tz, now: now))
        let headline = try #require(model.headline)
        #expect(headline.yesterday == nil && headline.delta == nil)
        #expect(headline.text == nil && headline.cardText == nil)
        #expect(Int(headline.now.rounded()) == 21)
        #expect(model.days[1].outlook.headline == nil)

        // 지금 시간 값이 없으면 맨 위 문장도 없다
        var gap = sample()
        var temps = try #require(gap[1].temps)
        temps.temps[14] = nil
        gap[1].temps = temps
        let missing = try #require(ThreeDayTemperatureModel(place: try place(gap), tz: tz, now: now))
        #expect(missing.headline == nil)
        // 빈 시간에서 선이 끊긴다
        let segments = Set((missing.chart?.points ?? []).map { $0.segment })
        #expect(segments == [0, 1])
    }

    @Test func chartRunsFromYesterdayMidnightToTomorrowNight() throws {
        let model = try #require(ThreeDayTemperatureModel(place: try place(sample()), tz: tz, now: now))
        let chart = try #require(model.chart)
        #expect(chart.points.count == 72)
        #expect(chart.points.first?.x == 0)
        #expect(chart.points.last?.x == 71)
        #expect(chart.dayBounds == [0, 24, 48, 72])
        #expect(abs((chart.nowX ?? 0) - (38 + 1.0 / 6)) < 0.0001)
        #expect(chart.nowHour == todayStart + 14 * 3600)
        #expect(chart.day(at: 30) == 1)
        #expect(chart.day(at: -3) == 0)
        #expect(chart.day(at: 80) == 2)
        #expect(chart.valueRange == 11...25)
        let segments = Set(chart.points.map { $0.segment })
        #expect(segments == [0])
    }

    @Test func daylightSavingDaysKeepTheirRealLength() throws {
        // 뉴욕 11/2(월) 10:10 EST. 어제(11/1)는 서머타임이 끝나 25시간이다.
        let newYorkNow = 1_793_632_200
        let starts = [1_793_505_600, 1_793_595_600, 1_793_682_000]
        let around = [
            day(start: starts[0], (0..<25).map { Double($0) }),
            day(start: starts[1], (0..<24).map { 100 + Double($0) }),
            day(start: starts[2], (0..<24).map { 200 + Double($0) }),
        ]
        let model = try #require(ThreeDayTemperatureModel(place: try place(around), tz: "America/New_York", now: newYorkNow))
        #expect(model.days.map(\.start) == starts)
        #expect(model.days[0].high == 24 && model.days[0].low == 0)
        let chart = try #require(model.chart)
        #expect(chart.dayBounds == [0, 25, 49, 73])
        #expect(chart.points.count == 73)
        let headline = try #require(model.headline)
        #expect(headline.hour == 10)
        #expect(headline.now == 110)
        // 어제 같은 시계 시각(10:10 EST)은 어제 0시(EDT)부터 11시간째
        #expect(headline.yesterday == 11)
        #expect(headline.tomorrow == 210)
    }

    @Test func halfHourZonesStartBetweenHours() throws {
        // 콜카타(+5:30) 10/20 14:10. 현지 자정이 정시가 아니라 기온은 0시 30분(UTC 정시)부터다.
        let kolkataToday = 1_792_434_600
        let kolkataNow = 1_792_485_600
        let around = (-1...1).map { offset in
            day(start: kolkataToday + offset * 86400, (0..<24).map { 100 * Double(offset + 1) + Double($0) }, firstHour: 1800)
        }
        let model = try #require(ThreeDayTemperatureModel(place: try place(around), tz: "Asia/Kolkata", now: kolkataNow))
        let chart = try #require(model.chart)
        #expect(chart.points.first?.x == 0.5)
        #expect(chart.dayBounds == [0, 24, 48, 72])
        #expect(chart.points.count == 72)
        #expect(model.headline?.hour == 14)
        // 14:10은 0시 30분부터 13시간째 값
        #expect(model.headline?.now == 113)
    }

    @Test func staleResponseShiftsTheDaysByDate() throws {
        // 하루 뒤에 저장해 둔 응답을 보면 어제는 그때의 오늘, 내일은 없다
        let model = try #require(ThreeDayTemperatureModel(place: try place(sample()), tz: tz, now: now + 86400))
        #expect(model.days.map(\.start) == [todayStart, todayStart + 86400, todayStart + 2 * 86400])
        #expect(model.days[0].high == 21)
        #expect(model.days[2].weather == nil)
        #expect(model.days[2].outlook.headline == nil)
        #expect(!model.days[2].hasForecast)
        #expect(model.days[1].outlook.headline == "어제보다 조금 따뜻해요")
        // 14시: 21.9°(22°) vs 20.8°(21°)
        #expect(model.headline?.text == "어제 이맘때와 비슷해요")
        #expect(model.headline?.tomorrow == nil)
    }

    @Test func pastDaySkyComesFromPrecipitation() throws {
        var around = sample()
        around[0].precipMm = 6
        around[0].cloud = 20
        around[1].rain = TripRain(pop: 10, agreeing: 0, total: 3, rainy: false)
        around[1].cloud = 20
        let model = try #require(ThreeDayTemperatureModel(place: try place(around), tz: tz, now: now))
        #expect(model.days[0].sky == .rain)
        #expect(model.days[0].rain == nil)
        #expect(model.days[1].sky == .clear)
        #expect(model.days[2].sky == nil)
    }

    @Test func contractSampleHasDaysButTooFewHours() throws {
        let url = try #require(Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures"))
        let today = try JSONDecoder().decode(TodayResponse.self, from: Data(contentsOf: url))
        let model = try #require(ThreeDayTemperatureModel(place: today.places[0], tz: today.tz, now: today.generatedAt))
        // 어제 기온은 06–09시뿐이라 하루 최고·최저를 구하지 않는다
        #expect(model.days.allSatisfy { $0.high == nil && $0.low == nil })
        #expect(model.days[1].rain?.pop == 68)
        #expect(model.headline == nil)
        #expect(model.chart?.points.count == 4)
        #expect(ThreeDayTemperatureModel(place: try place(nil), tz: tz, now: now) == nil)
    }
}
