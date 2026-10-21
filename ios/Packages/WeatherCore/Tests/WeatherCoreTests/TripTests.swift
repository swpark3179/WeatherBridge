import Foundation
import Testing
@testable import WeatherCore

/// 서버 `trips` 응답(계약 샘플)을 앱 모델로 디코딩할 수 있는지 확인한다.
/// 같은 파일을 server/tests/trips_test.ts가 서버 생성 결과와 비교한다.
@Suite struct TripContractTests {
    @Test func decodesTripsResponse() throws {
        let res = try tripsFixture()
        #expect(res.generatedAt == tripsNow)
        #expect(res.threshold == 30)
        #expect(res.home?.name == "집")
        #expect(res.home?.recent.map(\.providers) == [["om_ecmwf"], ["om_gfs"], ["om_icon"]])
        #expect(res.trips.map(\.name) == ["콜카타", "삿포로", "파리", "제주"])
        #expect(res.trips.map(\.watched) == [true, true, false, false])

        let sapporo = res.trips[1]
        #expect(sapporo.tz == "Asia/Tokyo")
        #expect(sapporo.startDate == LocalDate(year: 2026, month: 10, day: 23))
        #expect(sapporo.endDate == LocalDate(year: 2026, month: 10, day: 24))
        let day = try #require(sapporo.days.last)
        #expect(day.date.description == "2026-10-24")
        let weather = try #require(day.destination)
        #expect(weather.rain == TripRain(pop: 80, agreeing: 2, total: 2, rainy: true))
        #expect(weather.rain?.level == .high)
        #expect(weather.cloud == 95)
        #expect(weather.snowCm == 2.4)
        #expect(weather.temps?.providers == ["om_ecmwf", "om_gfs"])
        #expect(weather.temps?.temps.count == 24)

        // 먼 여행은 날짜만, 끝난 여행은 날짜도 없다
        #expect(res.trips[2].days.allSatisfy { $0.destination == nil && $0.home == nil })
        #expect(res.trips[3].days.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let res = try tripsFixture()
        let data = try JSONEncoder().encode(res)
        #expect(try JSONDecoder().decode(TripsResponse.self, from: data) == res)
        // 날짜는 문자열 그대로
        #expect(String(decoding: data, as: UTF8.self).contains(#""startDate":"2026-10-23""#))
    }
}

@Suite struct LocalDateTests {
    @Test func parsesAndFormatsPostgresDates() throws {
        let date = try #require(LocalDate(string: "2026-10-20"))
        #expect(date == LocalDate(year: 2026, month: 10, day: 20))
        #expect(date.description == "2026-10-20")
        #expect(date.weekdayText == "화")
        #expect(date.monthDayText == "10/20")
        for bad in ["2026-02-30", "2026-2-03", "20261020", "2026-10-20T00:00", ""] {
            #expect(LocalDate(string: bad) == nil)
        }
    }

    @Test func addsDaysAcrossMonthsYearsAndLeapDays() {
        let date = LocalDate(year: 2026, month: 12, day: 30)
        #expect(date.adding(days: 3).description == "2027-01-02")
        #expect(LocalDate(year: 2028, month: 2, day: 28).adding(days: 1).description == "2028-02-29")
        #expect(LocalDate(year: 2026, month: 3, day: 1).adding(days: -1).description == "2026-02-28")
        #expect(date.days(to: LocalDate(year: 2027, month: 1, day: 2)) == 3)
        #expect(LocalDate(year: 1970, month: 1, day: 1).dayNumber == 0)
        #expect(LocalDate(year: 1969, month: 12, day: 31).weekdayText == "수")
        #expect(LocalDate(year: 2026, month: 10, day: 23) < LocalDate(year: 2026, month: 11, day: 1))
    }

    @Test func convertsWithCalendarsAndClocks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = LocalDate(year: 2026, month: 10, day: 25)
        #expect(LocalDate(date.date(in: calendar), calendar: calendar) == date)

        // 콜카타(+5:30) 10/20 0시 = UTC 10/19 18:30
        let kolkata = LocalClock(tz: "Asia/Kolkata")
        #expect(kolkata.startOfDay(LocalDate(year: 2026, month: 10, day: 20)) == 1_792_434_600)
        #expect(kolkata.localDate(tripsNow).description == "2026-10-20")
        #expect(LocalClock(tz: "Pacific/Honolulu").localDate(tripsNow).description == "2026-10-19")
    }
}

@Suite struct TripPresentationTests {
    @Test func koreanParticleFollowsTheLastSound() {
        #expect(Hangul.withAnd("지금") == "지금과")
        #expect(Hangul.withAnd("어제") == "어제와")
        #expect(Hangul.withAnd("최근 3일 평균") == "최근 3일 평균과")
        #expect(Hangul.withAnd("3") == "3과")
        #expect(Hangul.withAnd("2") == "2와")
        #expect(Hangul.withAnd("abc") == "abc와")
        #expect(TemperatureDelta(today: 10, baseline: 10.4).sentence(comparedTo: "지금") == "지금과 비슷해요")
        #expect(TemperatureDelta(today: 10, baseline: 13).sentence(comparedTo: "지금") == "지금보다 3° 낮아요")
    }

    @Test(arguments: [
        // 최고(오늘, 기준), 최저(오늘, 기준), 방향, 문구
        ((16.1, 20.1), (7.1, 10.1), TemperatureOutlook.Trend.colder, "지금보다 조금 추워요"),
        ((24.0, 20.0), (7.0, 10.0), .widerSwing, "지금보다 일교차가 커요"),
        ((16.0, 20.0), (13.0, 10.0), .narrowerSwing, "지금보다 일교차가 작아요"),
        ((20.4, 20.0), (10.0, 10.6), .similar, "지금과 비슷해요"),
        // 한쪽만 비슷하면 다른 쪽의 체감
        ((22.0, 20.0), (10.0, 10.0), .warmer, "지금보다 조금 따뜻해요"),
        ((32.1, 20.1), (25.2, 10.1), .warmer, "지금보다 훨씬 더 더워요"),
        ((3.5, 20.5), (-1.5, 10.5), .colder, "지금보다 많이 추워요"),
    ] as [((Double, Double), (Double, Double), TemperatureOutlook.Trend, String)])
    func outlookHeadline(high: (Double, Double), low: (Double, Double), trend: TemperatureOutlook.Trend, text: String) {
        let outlook = TemperatureOutlook(
            high: TemperatureDelta(today: high.0, baseline: high.1),
            low: TemperatureDelta(today: low.0, baseline: low.1)
        )
        #expect(outlook.trend == trend)
        #expect(outlook.headline == text)
    }

    @Test func outlookNamesItsBaseline() {
        let label = TemperatureComparisonModel.label
        #expect(TemperatureOutlook(high: TemperatureDelta(today: 16.1, baseline: 20.1), low: TemperatureDelta(today: 7.1, baseline: 10.1), label: label).headline == "최근 3일보다 조금 추워요")
        #expect(TemperatureOutlook(high: TemperatureDelta(today: 20.4, baseline: 20), low: nil, label: label).headline == "최근 3일과 비슷해요")
        #expect(TemperatureOutlook(high: TemperatureDelta(today: 24, baseline: 20), low: TemperatureDelta(today: 7, baseline: 10), label: label).headline == "최근 3일보다 일교차가 커요")
    }

    @Test func outlookWithOneSideOrNone() {
        #expect(TemperatureOutlook(high: nil, low: nil).headline == nil)
        #expect(TemperatureOutlook(high: nil, low: nil).trend == nil)
        #expect(TemperatureOutlook(high: TemperatureDelta(today: 30, baseline: 24), low: nil).headline == "지금보다 훨씬 더 더워요")
        #expect(TemperatureOutlook(high: nil, low: TemperatureDelta(today: 9.6, baseline: 10)).headline == "지금과 비슷해요")
    }

    @Test(arguments: [
        (TripRain(pop: 80, agreeing: 2, total: 2, rainy: true), 2.4, 95, TripSky.snow),
        (TripRain(pop: 80, agreeing: 2, total: 2, rainy: true), 0.4, 95, .rain),
        (TripRain(pop: 80, agreeing: 2, total: 2, rainy: true), nil, nil, .rain),
        (TripRain(pop: 10, agreeing: 0, total: 3, rainy: false), 3.0, 29, .clear),
        (nil, nil, 30, .partlyCloudy),
        (nil, nil, 69, .partlyCloudy),
        (nil, nil, 70, .cloudy),
    ] as [(TripRain?, Double?, Int?, TripSky)])
    func skyFromRainSnowAndCloud(rain: TripRain?, snowCm: Double?, cloud: Int?, sky: TripSky) {
        let weather = TripDayWeather(start: 0, rain: rain, cloud: cloud, snowCm: snowCm, temps: nil)
        #expect(TripSky(weather) == sky)
    }

    @Test func noSkyWithoutRainOrCloud() {
        #expect(TripSky(TripDayWeather(start: 0, rain: nil, cloud: nil, snowCm: 1, temps: nil)) == nil)
        #expect(TripSky.allCases.map(\.label) == ["맑음", "구름 조금", "흐림", "비", "눈"])
    }

    @Test func homeBaselineAveragesTheLastThreeFullDaysPerModelMix() throws {
        let home = try #require(try tripsFixture().home)
        let all = try #require(HomeBaseline(recent: home.recent, tz: home.tz, now: tripsNow))
        // 모델 평균 = 서울 모양 + (0 + 1 − 0.6) / 3. 최근 3일 최고 21·20·19, 최저 11·10·9
        #expect(abs(all.high - 20.133) < 0.01)
        #expect(abs(all.low - 10.133) < 0.01)
        #expect(all.dayCount == 3)
        #expect(all.providers == ["om_ecmwf", "om_gfs", "om_icon"])

        let two = try #require(HomeBaseline(recent: home.recent, providers: ["om_ecmwf", "om_gfs"], tz: home.tz, now: tripsNow))
        #expect(abs(two.high - 20.5) < 0.01)
        #expect(abs(two.low - 10.5) < 0.01)

        // 원하는 모델의 기록이 없으면 비교하지 않는다(다른 묶음으로 바꿔 쓰지 않는다)
        #expect(HomeBaseline(recent: home.recent, providers: ["om_ecmwf", "kma_short"], tz: home.tz, now: tripsNow) == nil)
        #expect(HomeBaseline(recent: [], tz: home.tz, now: tripsNow) == nil)
    }

    @Test func homeBaselineSkipsDaysWithoutEnoughHours() throws {
        let tz = "Asia/Seoul"
        let todayStart = LocalClock(tz: tz).startOfDay(tripsNow)
        // 3일 전 0시부터 매시 값, 그제는 낮 12시간만 → 그 날은 빠진다
        let start = todayStart - 3 * 86400
        let temps = (0..<72).map { i -> Double? in
            let day = i / 24
            let hour = i % 24
            if day == 1 && (hour < 6 || hour >= 18) { return nil }
            return Double(10 + day * 2 + (hour == 15 ? 5 : 0))
        }
        let history = TemperatureHistory(providers: ["om_ecmwf"], start: start, temps: temps)
        let baseline = try #require(HomeBaseline(recent: [history], tz: tz, now: tripsNow))
        #expect(baseline.dayCount == 2)
        // 3일 전: 최고 15, 최저 10. 어제: 최고 19, 최저 14
        #expect(baseline.high == 17)
        #expect(baseline.low == 12)
    }

    @Test func homeBaselineFromAMixedHistoryMatchesOneModel() throws {
        let home = try #require(try tripsFixture().home)
        for history in home.recent {
            let fromHistory = try #require(HomeBaseline(history: history, tz: home.tz, now: tripsNow))
            let fromRecent = try #require(HomeBaseline(recent: [history], tz: home.tz, now: tripsNow))
            #expect(fromHistory == fromRecent)
        }
        #expect(HomeBaseline(history: TemperatureHistory(providers: ["om_ecmwf"], start: 0, temps: []), tz: home.tz, now: tripsNow) == nil)
    }

    @Test func homeBaselineHandlesA25HourDay() throws {
        // 뉴욕 11/1은 서머타임이 끝나 25시간
        let tz = "America/New_York"
        let clock = LocalClock(tz: tz)
        let now = clock.startOfDay(LocalDate(year: 2026, month: 11, day: 2)) + 8 * 3600
        let start = clock.startOfDay(LocalDate(year: 2026, month: 10, day: 30))
        let end = clock.startOfDay(LocalDate(year: 2026, month: 11, day: 2))
        let hours = (end - start) / 3600
        #expect(hours == 73)
        let temps = (0..<hours).map { i -> Double? in Double(i % 24) }
        let history = TemperatureHistory(providers: ["om_gfs"], start: start, temps: temps)
        let baseline = try #require(HomeBaseline(recent: [history], tz: tz, now: now))
        #expect(baseline.dayCount == 3)
        #expect(HomeBaseline(history: history, tz: tz, now: now) == baseline)
    }

    @Test func modelsDescribeStatusPeriodAndComparison() throws {
        let models = try tripsFixture().models(now: tripsNow)
        let (kolkata, sapporo, paris, jeju) = (models[0], models[1], models[2], models[3])

        #expect(kolkata.status == .ongoing(day: 2, of: 2))
        #expect(kolkata.badge == "여행 중 2/2일")
        #expect(kolkata.periodText == "10/19 월 – 10/20 화 · 1박 2일")
        let today = try #require(kolkata.days.first)
        #expect(today.label == "10/20 화")
        #expect(today.ordinal == 2)
        #expect(today.relative == "오늘")
        #expect(today.destination.sky == .rain)
        #expect(today.destination.outlook.headline == "지금보다 훨씬 더 더워요")
        #expect(today.destination.outlook.high?.degrees == 12)
        #expect(today.destination.outlook.low?.degrees == 15)
        #expect(today.home.outlook.high?.degrees == -2)

        #expect(sapporo.status == .upcoming(daysLeft: 3))
        #expect(sapporo.badge == "D-3")
        #expect(sapporo.periodText == "10/23 금 – 10/24 토 · 1박 2일")
        let (first, second) = (sapporo.days[0], sapporo.days[1])
        #expect(first.relative == nil)
        #expect(first.destination.high == 16.1)
        #expect(first.destination.low == 7.1)
        #expect(first.destination.modelCount == 3)
        #expect(first.destination.outlook.high?.signedText == "−4°")
        #expect(first.destination.outlook.low?.signedText == "−3°")
        #expect(first.destination.outlook.headline == "지금보다 조금 추워요")
        #expect(first.destination.sky == .clear)
        // 둘째 날은 ICON이 닿지 않아 2개 모델: 기준도 같은 2개 모델로
        #expect(second.destination.modelCount == 2)
        #expect(second.destination.baseline?.providers == ["om_ecmwf", "om_gfs"])
        #expect(second.destination.outlook.high?.degrees == -17)
        #expect(second.destination.sky == .snow)
        #expect(sapporo.rainyDays == 1)
        #expect(sapporo.summaryLine == "지금보다 많이 추워요 · 눈 1일")
        #expect(abs((sapporo.baseline?.high ?? 0) - 20.133) < 0.01)

        #expect(paris.status == .upcoming(daysLeft: 25))
        #expect(paris.forecastFrom?.description == "2026-10-30")
        #expect(paris.summaryLine == "예보는 10/30부터")
        #expect(paris.days.allSatisfy { !$0.destination.hasForecast && !$0.home.hasForecast })
        #expect(paris.outlook == nil)

        #expect(jeju.status == .ended)
        #expect(jeju.badge == "지난 여행")
        #expect(jeju.summaryLine == nil)
        #expect(jeju.forecastFrom == nil)
    }

    @Test func singleDayTripsAndDepartureDay() throws {
        var trip = try tripsFixture().trips[1]
        trip.startDate = LocalDate(year: 2026, month: 10, day: 20)
        trip.endDate = trip.startDate
        let model = TripModel(trip: trip, home: nil, now: tripsNow)
        #expect(model.periodText == "10/20 화 · 당일")
        #expect(model.status == .ongoing(day: 1, of: 1))

        // 집에서는 오늘 출발이지만 목적지(호놀룰루)는 아직 어제
        trip.tz = "Pacific/Honolulu"
        let behind = TripModel(trip: trip, home: try tripsFixture().home, now: tripsNow)
        #expect(behind.status == .upcoming(daysLeft: 0))
        #expect(behind.badge == "오늘 출발")
    }

    @Test func withoutHomeThereIsNoComparison() throws {
        let res = try tripsFixture()
        let model = TripModel(trip: res.trips[1], home: nil, now: tripsNow)
        #expect(model.baseline == nil)
        #expect(model.homeName == nil)
        #expect(model.days[0].destination.outlook.headline == nil)
        #expect(model.days[0].destination.high == 16.1)
        #expect(model.summaryLine == "눈 1일")
    }

    @Test func chartPlacesBothPlacesOnTheTripClock() throws {
        let models = try tripsFixture().models(now: tripsNow)
        let sapporo = try #require(TripChartModel(model: models[1]))
        #expect(sapporo.dayCount == 2)
        let destination = sapporo.points.filter { $0.series == .destination }
        let home = sapporo.points.filter { $0.series == .home }
        #expect(destination.count == 48 && home.count == 48)
        #expect(destination.first?.x == 0 && destination.last?.x == 47)
        #expect(Set(destination.map(\.line)) == ["destination-0", "destination-1"])
        #expect(sapporo.day(at: 30) == 1)
        #expect(sapporo.day(at: 99) == 1)
        #expect(sapporo.valueRange.lowerBound <= -2 && sapporo.valueRange.upperBound >= 22)

        // +5:30은 현지 0:30부터
        let kolkata = try #require(TripChartModel(model: models[0]))
        #expect(kolkata.points.first { $0.series == .destination }?.x == 0.5)
        #expect(kolkata.points.first { $0.series == .home }?.x == 0)

        #expect(TripChartModel(model: models[2]) == nil)
    }
}

/// 계약 샘플의 generatedAt: 2026-10-20 06:10 KST
let tripsNow = 1_792_444_200

func tripsFixture() throws -> TripsResponse {
    let url = try #require(Bundle.module.url(forResource: "trips_response", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode(TripsResponse.self, from: Data(contentsOf: url))
}
