import Foundation
import Testing
@testable import WeatherCore

struct AddressQueryCase: Sendable, CustomTestStringConvertible {
    let title: String
    let subtitle: String
    let expected: [AddressQuery.Candidate]

    var testDescription: String { "\(title) | \(subtitle)" }
}

private func candidate(_ query: String, area: String? = nil) -> AddressQuery.Candidate {
    AddressQuery.Candidate(query, area: area)
}

let addressQueryCases: [AddressQueryCase] = [
    // 지도 제안은 뜨지만 좌표로 바꾸지 못하던 주소
    AddressQueryCase(title: "명지국제5로 90", subtitle: "부산광역시 강서구 명지동", expected: [
        candidate("부산광역시 강서구 명지동 명지국제5로 90"),
        candidate("부산광역시 강서구 명지국제5로 90"),
        candidate("부산광역시 강서구 명지국제5로", area: "명지국제5로"),
        candidate("부산광역시 강서구 명지동", area: "명지동"),
        candidate("부산광역시 강서구", area: "부산광역시 강서구"),
    ]),
    // 나라 이름은 빼고, 같은 검색어는 한 번만
    AddressQueryCase(title: "명지국제5로 90", subtitle: "대한민국 부산광역시 강서구", expected: [
        candidate("부산광역시 강서구 명지국제5로 90"),
        candidate("부산광역시 강서구 명지국제5로", area: "명지국제5로"),
        candidate("부산광역시 강서구", area: "부산광역시 강서구"),
    ]),
    AddressQueryCase(title: "강남대로 지하 396", subtitle: "서울특별시 강남구", expected: [
        candidate("서울특별시 강남구 강남대로 지하 396"),
        candidate("서울특별시 강남구 강남대로 396"),
        candidate("서울특별시 강남구 강남대로", area: "강남대로"),
        candidate("서울특별시 강남구", area: "서울특별시 강남구"),
    ]),
    // 지번 주소
    AddressQueryCase(title: "서초동 1303-22", subtitle: "서울특별시 서초구", expected: [
        candidate("서울특별시 서초구 서초동 1303-22"),
        candidate("서울특별시 서초구 서초동", area: "서초동"),
        candidate("서울특별시 서초구", area: "서울특별시 서초구"),
    ]),
    AddressQueryCase(title: "상리 산 12", subtitle: "경기도 화성시 봉담읍", expected: [
        candidate("경기도 화성시 봉담읍 상리 산 12"),
        candidate("경기도 화성시 봉담읍 상리 산12"),
        candidate("경기도 화성시 봉담읍 상리", area: "상리"),
        candidate("경기도 화성시 봉담읍", area: "경기도 화성시 봉담읍"),
        candidate("경기도 화성시", area: "경기도 화성시"),
    ]),
    // 건물·회사 이름이면 부제목 끝의 주소로
    AddressQueryCase(title: "삼성전자 서울R&D캠퍼스", subtitle: "대한민국 서울특별시 서초구 성촌길 33", expected: [
        candidate("서울특별시 서초구 성촌길 33 삼성전자 서울R&D캠퍼스"),
        candidate("서울특별시 서초구 성촌길 33"),
        candidate("삼성전자 서울R&D캠퍼스"),
        candidate("서울특별시 서초구 성촌길", area: "성촌길"),
        candidate("서울특별시 서초구", area: "서울특별시 서초구"),
    ]),
    AddressQueryCase(title: "경기도청", subtitle: "경기도 수원시 팔달구 효원로 1", expected: [
        candidate("경기도 수원시 팔달구 효원로 1 경기도청"),
        candidate("경기도 수원시 팔달구 효원로 1"),
        candidate("경기도청"),
        candidate("경기도 수원시 팔달구 효원로", area: "효원로"),
        candidate("경기도 수원시 팔달구", area: "경기도 수원시 팔달구"),
        candidate("경기도 수원시", area: "경기도 수원시"),
    ]),
    // 번호 붙은 길은 큰 길로도 찾는다
    AddressQueryCase(title: "테헤란로4길 14", subtitle: "서울특별시 강남구 역삼동", expected: [
        candidate("서울특별시 강남구 역삼동 테헤란로4길 14"),
        candidate("서울특별시 강남구 테헤란로4길 14"),
        candidate("서울특별시 강남구 테헤란로4길", area: "테헤란로4길"),
        candidate("서울특별시 강남구 테헤란로", area: "테헤란로"),
        candidate("서울특별시 강남구 역삼동", area: "역삼동"),
        candidate("서울특별시 강남구", area: "서울특별시 강남구"),
    ]),
    AddressQueryCase(title: "중앙대로123번길 5", subtitle: "부산광역시 동구 초량동", expected: [
        candidate("부산광역시 동구 초량동 중앙대로123번길 5"),
        candidate("부산광역시 동구 중앙대로123번길 5"),
        candidate("부산광역시 동구 중앙대로123번길", area: "중앙대로123번길"),
        candidate("부산광역시 동구 중앙대로", area: "중앙대로"),
        candidate("부산광역시 동구 초량동", area: "초량동"),
        candidate("부산광역시 동구", area: "부산광역시 동구"),
    ]),
    // 부제목이 제목까지 담고 있으면 겹치는 부분을 뺀다
    AddressQueryCase(title: "세종대로 110", subtitle: "대한민국 서울특별시 중구 세종대로 110", expected: [
        candidate("서울특별시 중구 세종대로 110"),
        candidate("서울특별시 중구 세종대로", area: "세종대로"),
        candidate("서울특별시 중구", area: "서울특별시 중구"),
    ]),
    // 제목이 시·도부터 쓴 주소
    AddressQueryCase(title: "부산광역시 강서구 명지국제5로 90", subtitle: "대한민국", expected: [
        candidate("부산광역시 강서구 명지국제5로 90"),
        candidate("부산광역시 강서구 명지국제5로", area: "명지국제5로"),
        candidate("부산광역시 강서구", area: "부산광역시 강서구"),
    ]),
    // 지역을 모르면 넓히지 않는다
    AddressQueryCase(title: "명지국제5로 90", subtitle: "", expected: [
        candidate("명지국제5로 90"),
    ]),
    // 세종은 시군구가 없어 시만으로도 찾는다
    AddressQueryCase(title: "한누리대로 2130", subtitle: "세종특별자치시", expected: [
        candidate("세종특별자치시 한누리대로 2130"),
        candidate("세종특별자치시 한누리대로", area: "한누리대로"),
        candidate("세종특별자치시", area: "세종특별자치시"),
    ]),
    // 시·도만으로는 찾지 않는다
    AddressQueryCase(title: "해운대해변로 264", subtitle: "부산광역시", expected: [
        candidate("부산광역시 해운대해변로 264"),
        candidate("부산광역시 해운대해변로", area: "해운대해변로"),
    ]),
    // 읍은 남기고 리를 동으로 본다
    AddressQueryCase(title: "동화길 10", subtitle: "경기도 화성시 봉담읍 상리", expected: [
        candidate("경기도 화성시 봉담읍 상리 동화길 10"),
        candidate("경기도 화성시 봉담읍 동화길 10"),
        candidate("경기도 화성시 봉담읍 동화길", area: "동화길"),
        candidate("경기도 화성시 봉담읍 상리", area: "상리"),
        candidate("경기도 화성시 봉담읍", area: "경기도 화성시 봉담읍"),
        candidate("경기도 화성시", area: "경기도 화성시"),
    ]),
    // 괄호, 겹친 띄어쓰기, 우편번호
    AddressQueryCase(title: "테헤란로 152 (역삼동)", subtitle: "서울특별시  강남구 06236", expected: [
        candidate("서울특별시 강남구 테헤란로 152"),
        candidate("서울특별시 강남구 테헤란로", area: "테헤란로"),
        candidate("서울특별시 강남구", area: "서울특별시 강남구"),
    ]),
    // 해외: 쉼표 구성요소를 앞에서부터 빼고, 마지막(나라)만으로는 찾지 않는다
    AddressQueryCase(title: "Eiffel Tower", subtitle: "Av. Gustave Eiffel, 75007 Paris, France", expected: [
        candidate("Eiffel Tower, Av. Gustave Eiffel, 75007 Paris, France"),
        candidate("Av. Gustave Eiffel, 75007 Paris, France", area: "Av. Gustave Eiffel"),
        candidate("75007 Paris, France", area: "75007 Paris"),
    ]),
    AddressQueryCase(title: "Gangnam Station", subtitle: "Gangnam-gu, Seoul, South Korea", expected: [
        candidate("Gangnam Station, Gangnam-gu, Seoul"),
        candidate("Gangnam-gu, Seoul", area: "Gangnam-gu"),
    ]),
    // 국내 시·도로 시작하지 않으면 그대로만 찾는다
    AddressQueryCase(title: "삿포로시", subtitle: "일본 홋카이도", expected: [
        candidate("일본 홋카이도 삿포로시"),
        candidate("삿포로시"),
    ]),
]

@Suite struct AddressQueryTests {
    @Test(arguments: addressQueryCases)
    func candidatesGoFromTheExactPlaceToWiderAreas(_ example: AddressQueryCase) {
        let found = AddressQuery.candidates(title: example.title, subtitle: example.subtitle)
        #expect(found == example.expected)
        // 그대로 찾는 검색어가 늘 먼저다
        if let firstApproximate = found.firstIndex(where: \.isApproximate) {
            #expect(found[firstApproximate...].allSatisfy(\.isApproximate))
        }
        #expect(found.count <= AddressQuery.limit)
        #expect(found.allSatisfy { !$0.query.isEmpty })
        #expect(Set(found.map(\.query)).count == found.count)
    }

    @Test func emptyTitleHasNoCandidates() {
        #expect(AddressQuery.candidates(title: "  ", subtitle: "서울특별시 중구").isEmpty)
    }

    @Test func recognizesAddressWords() {
        #expect(AddressQuery.isBuildingNumber("90"))
        #expect(AddressQuery.isBuildingNumber("1303-22"))
        #expect(AddressQuery.isBuildingNumber("산12"))
        #expect(!AddressQuery.isBuildingNumber("1303-"))
        #expect(!AddressQuery.isBuildingNumber("B1"))
        #expect(AddressQuery.isRoad("명지국제5로"))
        #expect(AddressQuery.isRoad("동화길"))
        #expect(!AddressQuery.isRoad("강서구"))
        #expect(AddressQuery.isDongLevel("태평로1가"))
        #expect(!AddressQuery.isDongLevel("봉담읍"))
        #expect(AddressQuery.parentRoad("테헤란로4길") == "테헤란로")
        #expect(AddressQuery.parentRoad("중앙대로123번길") == "중앙대로")
        #expect(AddressQuery.parentRoad("가로수길") == nil)
        #expect(AddressQuery.parentRoad("명지국제5로") == nil)
    }
}
