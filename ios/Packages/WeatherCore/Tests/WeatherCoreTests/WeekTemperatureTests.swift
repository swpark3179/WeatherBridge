import Foundation
import Testing
@testable import WeatherCore

@Suite struct WeekTemperatureTests {
    /// 2026-10-20(화) 00:00 KST
    private let todayStart = 1_792_422_000
    /// 2026-10-20 06:10 KST
    private var now: Int { todayStart + 6 * 3600 + 600 }
    private let tz = "Asia/Seoul"
    private let models = ["om_ecmwf", "om_gfs", "om_icon"]
    /// 모델마다 다른 치우침. 셋의 평균은 0, ECMWF·GFS 둘은 +0.5
    private let bias: [String: Double] = ["om_ecmwf": 0, "om_gfs": 1, "om_icon": -1]
    /// 날짜(오늘부터 며칠, 음수는 지난 날)마다 더하는 값
    private let offsets: [Int: Double] = [-3: 3, -2: 6, -1: 3, 0: 0, 1: -2, 2: -5, 3: 0, 4: 2, 5: -6, 6: 1]

    /// 그 날 h시 기온: 10° + 시×0.25° + 날짜 값 (+ 모델 치우침)
    private func temp(day: Int, hour: Int, model: String? = nil) -> Double {
        10 + Double(hour) * 0.25 + offsets[day]! + (model.flatMap { bias[$0] } ?? 0)
    }

    private func dayTemps(_ day: Int, providers: [String]) -> TemperatureHistory {
        let mean = { (h: Int) in providers.map { temp(day: day, hour: h, model: $0) }.reduce(0, +) / Double(providers.count) }
        return TemperatureHistory(providers: providers, start: todayStart + day * 86400, temps: (0..<24).map(mean))
    }

    /// 모델 평균 기록(3일 전 ~ 오늘), 모델별 최근 3일, 날짜별 기온(ICON은 5일째부터 빠짐)
    private func samplePlace(recentModels: [String]? = nil) throws -> TodayPlace {
        let url = try #require(Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures"))
        var place = try JSONDecoder().decode(TodayResponse.self, from: Data(contentsOf: url)).places[0]
        place.tempHistory = TemperatureHistory(
            providers: models,
            start: todayStart - 3 * 86400,
            temps: (-3...0).flatMap { day in (0..<24).map { Double?(temp(day: day, hour: $0)) } }
        )
        place.recentTemps = (recentModels ?? models).map { model in
            TemperatureHistory(
                providers: [model],
                start: todayStart - 3 * 86400,
                temps: (-3 ... -1).flatMap { day in (0..<24).map { Double?(temp(day: day, hour: $0, model: model)) } }
            )
        }
        place.days = (0..<7).map { day in
            TodayDay(
                date: todayStart + day * 86400, pop: 10, agreeing: 0, total: 3, rainy: false,
                temps: dayTemps(day, providers: day < 5 ? models : ["om_ecmwf", "om_gfs"])
            )
        }
        return place
    }

    @Test func comparesEachDayWithTheLastThreeDays() throws {
        let week = try #require(WeekTemperatureModel(place: try samplePlace(), tz: tz, now: now))
        #expect(week.days.count == 7)
        #expect(week.days.map(\.label) == ["오늘", "내일", "목", "금", "토", "일", "월"])
        #expect(week.days.map(\.dateText).prefix(2) == ["10/20", "10/21"])
        #expect(week.days.map(\.modelCount) == [3, 3, 3, 3, 3, 2, 2])
        // 최근 3일 최고 18.75·21.75·18.75, 최저 13·16·13
        #expect(week.baseline?.high == 19.75 && week.baseline?.low == 14)
        #expect(week.days.map { $0.outlook.high?.degrees } == [-4, -6, -9, -4, -2, -10, -3])
        #expect(week.days.map { $0.outlook.low?.degrees } == [-4, -6, -9, -4, -2, -10, -3])
        #expect(week.days[1].outlook.headline == "최근 3일보다 많이 추워요")
        // 하루 가운데 값 14.875°(15°) vs 16.875°(17°)
        #expect(week.days[4].outlook.headline == "최근 3일보다 조금 선선해요")
    }

    @Test func todayMatchesTheTodayView() throws {
        let place = try samplePlace()
        let today = try #require(TemperatureComparisonModel(place: place, tz: tz, now: now))
        let week = try #require(WeekTemperatureModel(place: place, tz: tz, now: now))
        let first = try #require(week.days.first)
        #expect(first.high == today.high?.today && first.low == today.low?.today)
        #expect(first.baseline == today.daily)
        #expect(first.outlook.high == today.high?.delta && first.outlook.low == today.low?.delta)
    }

    @Test func daysWithFewerModelsUseTheSameModelsForTheBaseline() throws {
        let week = try #require(WeekTemperatureModel(place: try samplePlace(), tz: tz, now: now))
        let five = week.days[5]
        // ECMWF·GFS 둘의 평균은 +0.5라 그 날도 기준도 0.5° 높다 → 차이는 그대로
        #expect(five.baseline?.providers == ["om_ecmwf", "om_gfs"])
        #expect(five.baseline?.high == 20.25 && five.baseline?.low == 14.5)
        #expect(five.high == 10.25 && five.low == 4.5)
        // 같은 묶음끼리는 기준을 함께 쓴다
        #expect(week.days[6].baseline == five.baseline)
        #expect(week.days[1].baseline == week.baseline)
    }

    @Test func noComparisonWhenTheDaysModelsHaveNoRecentValues() throws {
        // GFS의 지난 기록이 없으면 ECMWF·GFS 날은 비교하지 않는다(다른 묶음으로 바꿔 쓰지 않는다)
        let week = try #require(WeekTemperatureModel(place: try samplePlace(recentModels: ["om_ecmwf", "om_icon"]), tz: tz, now: now))
        #expect(week.days[5].baseline == nil && week.days[5].outlook.headline == nil)
        #expect(week.days[5].high == 10.25)
        // 세 모델 날은 모델 평균 기록으로 비교한다
        #expect(week.days[0].outlook.high?.degrees == -4)
    }

    @Test func weekHeadlineAndStandoutDay() throws {
        let week = try #require(WeekTemperatureModel(place: try samplePlace(), tz: tz, now: now))
        #expect(week.outlook?.trend == .colder)
        #expect(week.headline == "최근 3일보다 많이 추워요")
        // 가장 추운 날: 일요일 최저 4.5°(5°) vs 14.5°(15°)
        #expect(week.detail == "가장 추운 날 일 최저 5° (−10°)")
        #expect(week.scale == 3...22)
    }

    @Test func noStandoutWhenEveryDayIsSimilar() throws {
        var place = try samplePlace()
        // 앞으로 7일이 최근 3일 평균(날짜 값 4)과 같다
        place.days = (0..<7).map { day in
            let temps = (0..<24).map { Double?(14 + Double($0) * 0.25) }
            return TodayDay(
                date: todayStart + day * 86400, pop: 10, agreeing: 0, total: 3, rainy: false,
                temps: TemperatureHistory(providers: models, start: todayStart + day * 86400, temps: temps)
            )
        }
        // 오늘 보기의 오늘 값도 같게
        var history = try #require(place.tempHistory)
        history.temps = Array(history.temps.prefix(72)) + (0..<24).map { Double?(14 + Double($0) * 0.25) }
        place.tempHistory = history
        let week = try #require(WeekTemperatureModel(place: place, tz: tz, now: now))
        #expect(week.headline == "최근 3일과 비슷해요")
        #expect(week.outlook?.trend == .similar)
        #expect(week.detail == nil)
    }

    @Test func staleResponseDropsPastDays() throws {
        let tomorrow = now + 86400
        let week = try #require(WeekTemperatureModel(place: try samplePlace(), tz: tz, now: tomorrow))
        #expect(week.days.count == 6)
        #expect(week.days.first?.label == "오늘")
        #expect(week.days.first?.dateText == "10/21")
    }

    @Test func daysWithoutEnoughHoursAreLeftOut() throws {
        var place = try samplePlace()
        var temps = try #require(place.days?[3].temps)
        temps.temps = temps.temps.enumerated().map { $0.offset < 12 ? $0.element : nil }
        place.days?[3].temps = temps
        let week = try #require(WeekTemperatureModel(place: place, tz: tz, now: now))
        #expect(week.days.count == 6)
        #expect(!week.days.contains { $0.date == todayStart + 3 * 86400 })
    }

    @Test func nothingWithoutDailyTemperatures() throws {
        var place = try samplePlace()
        place.days = place.days?.map { day in
            var day = day
            day.temps = nil
            return day
        }
        // 오늘 값은 오늘 보기로 채울 수 있지만, 날짜별 기온이 없는 이전 서버 응답이면 7일 보기를 만들지 않는다
        #expect(WeekTemperatureModel(place: place, tz: tz, now: now) == nil)
        place.days = nil
        #expect(WeekTemperatureModel(place: place, tz: tz, now: now) == nil)
    }
}
