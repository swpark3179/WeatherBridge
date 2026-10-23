import Foundation
import Testing
@testable import WeatherCore

@Suite struct TemperatureComparisonTests {
    /// 2026-10-20(화) 00:00 KST
    private let todayStart = 1_792_422_000
    /// 2026-10-20 06:10 KST (계약 샘플의 generatedAt)
    private var now: Int { todayStart + 6 * 3600 + 600 }

    @Test func deltaTextsUseTheShownWholeDegrees() {
        let similar = TemperatureDelta(today: 20.4, baseline: 19.6)
        #expect(similar.degrees == 0 && similar.isSimilar)
        #expect(similar.signedText == "0°")
        #expect(similar.sentence(comparedTo: WeekTemperatureModel.label) == "최근 3일과 비슷해요")
        #expect(similar.feeling == nil)
        // 0.6° 차이지만 보이는 값은 13°와 15°라 2° 낮다고 말한다
        let shown = TemperatureDelta(today: 13.4, baseline: 14.6)
        #expect(shown.degrees == -2)
        #expect(shown.sentence(comparedTo: WeekTemperatureModel.label) == "최근 3일보다 2° 낮아요")
        #expect(TemperatureDelta(today: 15, baseline: 16).isSimilar)
    }

    @Test(arguments: [
        (8.0, 14.0, "−6°", "최근 3일보다 6° 낮아요", "많이 추워요"),
        (12.0, 9.0, "+3°", "최근 3일보다 3° 높아요", "조금 포근해요"),
        (18.0, 21.0, "−3°", "최근 3일보다 3° 낮아요", "조금 선선해요"),
        (22.0, 15.0, "+7°", "최근 3일보다 7° 높아요", "많이 따뜻해요"),
        (29.0, 33.0, "−4°", "최근 3일보다 4° 낮아요", "조금 덜 더워요"),
        (31.0, 25.0, "+6°", "최근 3일보다 6° 높아요", "훨씬 더 더워요"),
    ])
    func feelingDependsOnTodaysTemperature(today: Double, baseline: Double, signed: String, sentence: String, feeling: String) {
        let delta = TemperatureDelta(today: today, baseline: baseline)
        #expect(delta.signedText == signed)
        #expect(delta.sentence(comparedTo: WeekTemperatureModel.label) == sentence)
        #expect(delta.feeling == feeling)
    }

    @Test func baselineIsTheLastThreeDays() {
        #expect(HomeBaseline.days == 3)
        #expect(WeekTemperatureModel.label == "최근 3일")
        #expect(WeekTemperatureModel.valueLabel == "최근 3일 평균")
    }

    @Test func historyLooksUpTheHourThatContainsATime() {
        let history = TemperatureHistory(providers: ["om_ecmwf"], start: todayStart, temps: [10, nil, 12])
        #expect(history.temp(at: todayStart + 1800) == 10)
        #expect(history.temp(at: todayStart + 3600) == nil)
        #expect(history.temp(at: todayStart + 2 * 3600) == 12)
        #expect(history.temp(at: todayStart - 1) == nil)
        #expect(history.temp(at: todayStart + 3 * 3600) == nil)
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
