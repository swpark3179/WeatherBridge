import Foundation
import Testing
@testable import WeatherCore

@Suite struct ForecastPresentationTests {
    /// 계약 샘플: 2026-10-20 06:10 KST 기준, 06–09시 4시간, 집은 08–10시 비
    private func fixture() throws -> TodayResponse {
        let url = try #require(Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(TodayResponse.self, from: Data(contentsOf: url))
    }

    @Test func sourceLabelsAndOrder() {
        #expect(ForecastSourceInfo.label("kma_short") == "기상청")
        #expect(ForecastSourceInfo.label("om_gfs") == "GFS(미국)")
        #expect(ForecastSourceInfo.label("new_source") == "new_source")
        #expect(ForecastSourceInfo.sorted(["om_icon", "zz", "kma_short", "om_ecmwf", "aa", "om_icon"])
            == ["kma_short", "om_ecmwf", "om_icon", "aa", "zz"])
    }

    @Test func localClockUsesThePlaceTimeZone() {
        let seoul = LocalClock(tz: "Asia/Seoul")
        let t = 1_792_450_800 // 2026-10-20 08:00 KST
        #expect(seoul.hour(t) == 8)
        #expect(LocalClock(tz: "UTC").hour(t) == 23)
        #expect(seoul.dayOffset(t + 16 * 3600, from: t) == 1)
        #expect(seoul.windowText(start: t, end: t + 2 * 3600, now: t) == "오늘 8–10시")
        #expect(seoul.windowText(start: t + 15 * 3600, end: t + 16 * 3600, now: t) == "오늘 23시")
        #expect(seoul.windowText(start: t + 16 * 3600, end: t + 17 * 3600, now: t) == "내일 0시")
        #expect(seoul.windowText(start: t + 14 * 3600, end: t + 16 * 3600, now: t) == "오늘 22–24시")
    }

    @Test func bannerDescribesTheNextRainWindow() throws {
        let today = try fixture()
        let home = today.places[0]
        #expect(home.bannerText(now: today.generatedAt, tz: today.tz) == "☔ 오늘 8–10시 최대 68% · 4개 중 4개")
        let office = today.places[1]
        #expect(office.bannerText(now: today.generatedAt, tz: today.tz) == "앞으로 24시간 비 소식 없음 (최대 9%)")
        // 지난 비 구간은 무시한다
        #expect(home.nextWindow(now: home.windows[0].end) == nil)
    }

    @Test func upcomingStartsAtTheCurrentHour() throws {
        let today = try fixture()
        let home = today.places[0]
        #expect(home.upcoming(hours: 2, now: today.generatedAt).map(\.t) == [home.hours[0].t, home.hours[1].t])
        #expect(home.upcoming(hours: 10, now: home.hours[2].t + 59).count == 2)
    }

    @Test func heatmapHasAConsensusRowThenSources() throws {
        let today = try fixture()
        let model = HeatmapModel(place: today.places[0], tz: today.tz, now: today.generatedAt)
        #expect(model.rows.map(\.id) == ["consensus", "kma_short", "om_ecmwf", "om_gfs", "om_icon"])
        #expect(model.rows[0].isConsensus)
        #expect(model.rows[0].cells == [4, 16, 51, 68])
        #expect(model.rows[1].cells == [10, 20, 60, 70])
        #expect(model.columns.map(\.hour) == [6, 7, 8, 9])
        #expect(model.columns.map(\.split) == [false, false, true, true])
        #expect(model.columns[2].agreement == "3/4")
        #expect(model.columns.allSatisfy { $0.dayLabel == nil })
    }

    @Test func heatmapShowsMissingSourcesAsEmptyCells() throws {
        let today = try fixture()
        let office = today.places[1]
        let model = HeatmapModel(place: office, tz: today.tz, now: today.generatedAt)
        // 회사는 ICON을 받지 못했다(errors)
        #expect(model.rows.map(\.id) == ["consensus", "kma_short", "om_ecmwf", "om_gfs"])
        var withGap = office
        withGap.hours[1].providers["om_gfs"] = nil
        let gapped = HeatmapModel(place: withGap, tz: today.tz, now: today.generatedAt)
        #expect(gapped.rows[3].cells == [0, nil, 0, 0])
    }

    @Test func heatmapMarksTheFirstColumnOfANewDay() throws {
        let today = try fixture()
        var place = today.places[0]
        // 22시부터 4시간으로 바꿔 자정을 넘기게 한다
        let start = place.hours[0].t + 16 * 3600
        for i in place.hours.indices { place.hours[i].t = start + i * 3600 }
        let model = HeatmapModel(place: place, tz: today.tz, now: start)
        #expect(model.columns.map(\.hour) == [22, 23, 0, 1])
        #expect(model.columns.map(\.dayLabel) == [nil, nil, "내일", nil])
    }
}
