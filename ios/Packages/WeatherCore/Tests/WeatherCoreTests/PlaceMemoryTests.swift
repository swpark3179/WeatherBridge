import Foundation
import Testing
@testable import WeatherCore

@Suite struct PlaceMemoryTests {
    private let cityHall = Coordinate(lat: 37.566535, lon: 126.977969)

    @Test func remembersByKindAndChecksTheID() {
        var memory = PlaceMemory()
        #expect(memory.isEmpty)
        memory.remember(RememberedPlace(id: "home-1", label: "서울특별시청", subtitle: "중구 세종대로 110", coordinate: cityHall), as: .place(.home))

        let home = memory.place(.place(.home), id: "home-1")
        #expect(home?.label == "서울특별시청")
        #expect(home?.subtitle == "중구 세종대로 110")
        // 다른 기기에서 바꿨거나 새로 시작해 id가 바뀌었으면 쓰지 않는다
        #expect(memory.place(.place(.home), id: "home-2") == nil)
        #expect(memory.place(.place(.office), id: "home-1") == nil)
    }

    @Test func storesCoordinatesRoundedToAboutOneKilometer() {
        let place = RememberedPlace(id: "home-1", label: "집", coordinate: cityHall)
        #expect(place.coordinate == Coordinate(lat: 37.57, lon: 126.98))
    }

    @Test func forgetsAndPrunesTrips() {
        var memory = PlaceMemory()
        let sapporo = Coordinate(lat: 43.06, lon: 141.35)
        memory.remember(RememberedPlace(id: "home-1", label: "집", coordinate: cityHall), as: .place(.home))
        memory.remember(RememberedPlace(id: "t1", label: "삿포로", coordinate: sapporo, tz: "Asia/Tokyo"), as: .trip("t1"))
        memory.remember(RememberedPlace(id: "t2", label: "파리", coordinate: Coordinate(lat: 48.86, lon: 2.35), tz: "Europe/Paris"), as: .trip("t2"))

        memory.keepTrips(["t1"])
        #expect(memory.place(.trip("t1"), id: "t1")?.tz == "Asia/Tokyo")
        #expect(memory.place(.trip("t2"), id: "t2") == nil)
        // 집·회사는 여행 정리와 상관없다
        #expect(memory.place(.place(.home), id: "home-1") != nil)

        memory.forget(.trip("t1"))
        #expect(memory.place(.trip("t1"), id: "t1") == nil)
        memory.forget(.place(.home))
        #expect(memory.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var memory = PlaceMemory()
        memory.remember(RememberedPlace(id: "office-1", label: "회사", subtitle: nil, coordinate: cityHall), as: .place(.office))
        memory.remember(RememberedPlace(id: "t1", label: "제주", coordinate: Coordinate(lat: 33.5, lon: 126.53)), as: .trip("t1"))
        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(PlaceMemory.self, from: data) == memory)
    }
}
