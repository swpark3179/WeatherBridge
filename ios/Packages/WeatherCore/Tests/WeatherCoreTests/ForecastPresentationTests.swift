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

    @Test func spanAndRangeTexts() {
        let seoul = LocalClock(tz: "Asia/Seoul")
        let t = 1_792_450_800 // 2026-10-20(화) 08:00 KST
        #expect(seoul.spanText(start: t, end: t + 2 * 3600) == "8–10시")
        #expect(seoul.compactWindowText(start: t, end: t + 2 * 3600, now: t) == "8–10시")
        #expect(seoul.compactWindowText(start: t + 16 * 3600, end: t + 18 * 3600, now: t) == "내일 0–2시")
        #expect(seoul.rangeText(start: t, end: t + 2 * 3600) == "08:00 – 10:00")
        #expect(seoul.rangeText(start: t + 14 * 3600, end: t + 16 * 3600) == "22:00 – 24:00")
        #expect(seoul.rangeText(start: t + 1800, end: t + 3600) == "08:30 – 09:00")
        #expect(seoul.timeText(t + 1800) == "08:30")
        #expect(seoul.dayLabel(t + 40 * 3600, from: t) == "모레")
    }

    @Test func weekdayAndDateTexts() {
        let seoul = LocalClock(tz: "Asia/Seoul")
        let t = 1_792_450_800 // 2026-10-20(화) 08:00 KST
        #expect(seoul.weekdayText(t) == "화")
        #expect(seoul.weekdayText(t + 5 * 86400) == "일")
        #expect(seoul.monthDayText(t) == "10/20")
        #expect(seoul.monthDayText(t + 12 * 86400) == "11/1")
        #expect(seoul.weekDayLabel(t, from: t) == "오늘")
        #expect(seoul.weekDayLabel(t + 86400, from: t) == "내일")
        #expect(seoul.weekDayLabel(t + 2 * 86400, from: t) == "목")
        // 16시간 뒤는 다음 날 0시
        #expect(seoul.weekDayLabel(t + 16 * 3600, from: t) == "내일")
    }

    @Test func commuteOccurrencesFollowWeekdays() {
        let seoul = LocalClock(tz: "Asia/Seoul")
        let t = 1_792_450_800 // 화요일 08:00
        let commute = ClockTime(hour: 8, minute: 30)
        let weekdays = [1, 2, 3, 4, 5]
        #expect(seoul.occurrences(of: commute, days: weekdays, from: t, to: t + 48 * 3600) == [t + 1800, t + 1800 + 86400])
        #expect(seoul.occurrences(of: commute, days: [3], from: t, to: t + 48 * 3600) == [t + 1800 + 86400])
        #expect(seoul.occurrences(of: commute, days: [1], from: t, to: t + 48 * 3600).isEmpty)
        // 이미 지난 오늘 출근 시각은 빼고 [from, to)만 본다
        #expect(seoul.occurrences(of: commute, days: weekdays, from: t + 3600, to: t + 24 * 3600).isEmpty)
    }

    @Test func upcomingWindowsPeakAndClearing() throws {
        let today = try fixture()
        var home = today.places[0]
        let now = today.generatedAt
        let morning = home.windows[0]
        #expect(home.upcomingWindows(now: now) == [morning])
        #expect(home.upcomingWindows(now: morning.end).isEmpty)
        #expect(morning.hourCount == 2)
        #expect(morning.contains(morning.start) && !morning.contains(morning.end))
        #expect(home.peakHour(of: morning)?.t == morning.start + 3600)
        #expect(home.clearingText(after: morning, now: now, tz: today.tz) == "10시부터 그쳐요 · 이후 비 소식 없음")

        let evening = RainWindow(start: morning.start + 10 * 3600, end: morning.start + 13 * 3600, maxPop: 43, agreeing: 3, total: 4)
        let night = RainWindow(start: morning.start + 19 * 3600, end: morning.start + 21 * 3600, maxPop: 35, agreeing: 2, total: 4)
        home.windows = [night, morning, evening]
        #expect(home.upcomingWindows(now: now) == [morning, evening, night])
        #expect(home.upcomingWindows(within: 12, now: now) == [morning, evening])
        #expect(home.clearingText(after: morning, now: now, tz: today.tz) == "10시부터 그쳐요 · 18시에 다시 와요")
        #expect(home.clearingText(after: evening, now: now, tz: today.tz) == "21시부터 그쳐요 · 내일 3시에 다시 와요")
    }

    @Test func splitSpansAndTemperatureRange() throws {
        let today = try fixture()
        let home = today.places[0]
        let now = today.generatedAt
        #expect(home.splitSpans(now: now) == [TimeSpan(start: home.hours[2].t, end: home.hours[3].t + 3600)])
        #expect(today.places[1].splitSpans(now: now).isEmpty)
        let range = try #require(home.temperatureRange(now: now))
        #expect(range.low == 15 && range.high == 17)
    }

    @Test func overviewListsEveryRainWindow() throws {
        var today = try fixture()
        let now = today.generatedAt
        let rainy = today.overview(now: now)
        #expect(rainy.headline == "집 8–10시 비")
        #expect(rainy.detail == "회사 비 소식 없음 (최대 9%)")
        #expect(rainy.isRainy)

        let morning = today.places[0].windows[0]
        today.places[0].windows.append(RainWindow(start: morning.start + 10 * 3600, end: morning.start + 13 * 3600, maxPop: 43, agreeing: 3, total: 4))
        today.places[0].windows.append(RainWindow(start: morning.start + 19 * 3600, end: morning.start + 21 * 3600, maxPop: 35, agreeing: 2, total: 4))
        #expect(today.overview(now: now).headline == "집 8–10시, 18–21시, 내일 3–5시 비")

        today.places[0].windows = []
        let dry = today.overview(now: now)
        #expect(dry.headline == "앞으로 24시간 비 소식 없음")
        #expect(dry.detail == "집 최대 68% · 회사 최대 9%")
        #expect(!dry.isRainy)
    }

    @Test func weekModelShowsWhetherEachDayIsRainy() throws {
        let today = try fixture()
        let now = today.generatedAt // 10/20(화) 06:10
        let week = WeekRainModel(place: today.places[0], tz: today.tz, now: now)
        #expect(week.rows.map(\.label) == ["오늘", "내일", "목"])
        #expect(week.rows.map(\.dateText) == ["10/20", "10/21", "10/22"])
        #expect(week.rows.map(\.pop) == [68, 17, 43])
        #expect(week.rows.map(\.level) == [.high, .clear, .moderate])
        #expect(week.rows.map(\.agreement) == ["예보 4개 중 4개", "예보 4개 중 1개", "예보 3개 중 2개"])
        #expect(week.rainyCount == 2)
        #expect(week.headline == "오늘 · 목")
        #expect(week.detail == "가장 높을 때 오늘 68%")

        // 하루 뒤 저장된 응답을 보면 지난 날은 빠지고 이름이 하루씩 당겨진다
        let tomorrow = WeekRainModel(place: today.places[0], tz: today.tz, now: now + 86400)
        #expect(tomorrow.rows.map(\.label) == ["오늘", "내일"])
        #expect(tomorrow.headline == "내일")
        #expect(tomorrow.detail == "가장 높을 때 내일 43%")
    }

    @Test func weekModelWithoutRainOrDays() throws {
        let today = try fixture()
        var home = today.places[0]
        home.days = home.days?.map { day in
            var dry = day
            dry.rainy = false
            return dry
        }
        let dry = WeekRainModel(place: home, tz: today.tz, now: today.generatedAt)
        #expect(dry.rainyCount == 0)
        #expect(dry.headline == "앞으로 7일 비 소식 없음")
        #expect(dry.detail == "가장 높을 때 오늘 68%")

        // 회사는 날짜별 값이 없고, 이전 서버의 응답이면 days가 nil이다
        #expect(WeekRainModel(place: today.places[1], tz: today.tz, now: today.generatedAt).headline == nil)
        home.days = nil
        let missing = WeekRainModel(place: home, tz: today.tz, now: today.generatedAt)
        #expect(missing.rows.isEmpty)
        #expect(missing.headline == nil)
        #expect(home.upcomingDays(now: today.generatedAt, tz: today.tz) == nil)
    }

    @Test func weekOverviewListsRainyDaysPerPlace() throws {
        var today = try fixture()
        let now = today.generatedAt
        // 회사는 날짜별 값이 없어 빠진다
        let rainy = today.weekOverview(now: now)
        #expect(rainy.headline == "집 오늘·목 비")
        #expect(rainy.detail == nil)
        #expect(rainy.isRainy)

        let tomorrow = try #require(today.places[0].days?[1].date)
        today.places[1].days = [TodayDay(date: tomorrow, pop: 12, agreeing: 0, total: 3, rainy: false)]
        #expect(today.weekOverview(now: now).detail == "회사 비 소식 없음 (최대 12%)")

        today.places[0].days = today.places[0].days?.map { day in
            var dry = day
            dry.rainy = false
            return dry
        }
        let dry = today.weekOverview(now: now)
        #expect(dry.headline == "앞으로 7일 비 소식 없음")
        #expect(dry.detail == "집 최대 68% · 회사 최대 12%")
        #expect(!dry.isRainy)

        for index in today.places.indices { today.places[index].days = nil }
        #expect(today.weekOverview(now: now).headline == "7일 예보를 받는 중이에요")
    }

    @Test func timelinePlacesBracketsTicksAndMarkers() throws {
        let today = try fixture()
        let home = today.places[0]
        let commute = home.windows[0].start + 1800 // 08:30
        let model = RainTimelineModel(place: home, tz: today.tz, now: today.generatedAt, commuteTimes: [commute, commute + 86400])
        #expect(model.bars.map(\.pop) == [4, 16, 51, 68])
        #expect(model.bars.map(\.level) == [.clear, .clear, .moderate, .high])
        #expect(model.brackets == [.init(window: 0, start: 2, end: 4, label: "8–10시")])
        #expect(model.ticks == [.init(position: 0, label: "6시", isDayStart: false), .init(position: 3, label: "9시", isDayStart: false)])
        #expect(abs(model.now - 10.0 / 60) < 0.0001)
        #expect(model.midnight == nil)
        #expect(model.commutes == [2.5])

        // 22시부터 4시간으로 바꾸면 2번째 칸에서 날짜가 바뀐다
        var late = home
        let start = home.hours[0].t + 16 * 3600
        for i in late.hours.indices { late.hours[i].t = start + i * 3600 }
        late.windows = []
        let night = RainTimelineModel(place: late, tz: today.tz, now: start)
        #expect(night.midnight == 2)
        #expect(night.ticks == [.init(position: 2, label: "내일", isDayStart: true)])
        #expect(night.brackets.isEmpty)
    }

    @Test func upcomingStartsAtTheCurrentHour() throws {
        let today = try fixture()
        let home = today.places[0]
        #expect(home.upcoming(hours: 2, now: today.generatedAt).map(\.t) == [home.hours[0].t, home.hours[1].t])
        #expect(home.upcoming(hours: 10, now: home.hours[2].t + 59).count == 2)
    }

    @Test func compareChartExplainsWhoDisagrees() throws {
        let today = try fixture()
        let home = today.places[0]
        let model = CompareChartModel(place: home, tz: today.tz, now: today.generatedAt)
        #expect(model.hours.map(\.t) == home.hours.map(\.t))
        #expect(model.providers == ["kma_short", "om_ecmwf", "om_gfs", "om_icon"])
        #expect(model.windows == home.windows)
        #expect(model.splits == [TimeSpan(start: home.hours[2].t, end: home.hours[3].t + 3600)])
        let d = try #require(model.disagreements.first)
        #expect(model.disagreements.count == 1)
        #expect(d.provider == "om_ecmwf" && d.isHigh && d.value == 90 && d.spread == 60)
        #expect(d.when == "8–10시 · 차이 60%p")
        #expect(d.detail == "가장 높게 본 예보 ECMWF(유럽) 90%")
        #expect(model.ticks == [
            .init(t: home.hours[0].t, label: "6시", isDayStart: false),
            .init(t: home.hours[3].t, label: "9시", isDayStart: false),
        ])
    }

    @Test func compareChartNamesALowOutlier() throws {
        let today = try fixture()
        var home = today.places[0]
        // ECMWF를 종합 가까이 내리면 ICON이 가장 멀리(낮게) 떨어진다
        home.hours[2].providers["om_ecmwf"] = 60
        home.hours[3].providers["om_ecmwf"] = 70
        let d = try #require(CompareChartModel(place: home, tz: today.tz, now: today.generatedAt).disagreements.first)
        #expect(d.provider == "om_icon" && !d.isHigh && d.value == 20)
        #expect(d.detail == "가장 낮게 본 예보 ICON(독일) 20%")
    }

    @Test func compareChartSkipsMissingSourcesAndQuietHours() throws {
        let today = try fixture()
        let office = CompareChartModel(place: today.places[1], tz: today.tz, now: today.generatedAt)
        #expect(office.providers == ["kma_short", "om_ecmwf", "om_gfs"])
        #expect(office.windows.isEmpty && office.splits.isEmpty && office.disagreements.isEmpty)
    }

    @Test func compareChartTicksWidenForTwoDays() throws {
        let today = try fixture()
        var place = today.places[0]
        // 22시부터 4시간으로 바꿔 자정을 넘기게 한다
        let start = place.hours[0].t + 16 * 3600
        for i in place.hours.indices { place.hours[i].t = start + i * 3600 }
        let twoDays = CompareChartModel(place: place, tz: today.tz, now: start, hours: 48)
        #expect(twoDays.ticks == [.init(t: start + 2 * 3600, label: "내일", isDayStart: true)])
        let oneDay = CompareChartModel(place: today.places[0], tz: today.tz, now: today.generatedAt, hours: 48)
        #expect(oneDay.ticks.map(\.label) == ["6시"])
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
