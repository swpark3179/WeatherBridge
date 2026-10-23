import Foundation

/// 검색 제안(제목·부제목)을 지도가 좌표로 바꾸지 못했을 때 차례로 찾아볼 검색어 (D28).
/// 고른 곳 그대로 찾는 검색어가 먼저이고, 그다음은 넓은 곳 순서다: 건물번호를 뺀 도로 → 상위 도로 → 동 → 시군구.
/// 시·도나 나라만으로는 찾지 않는다(그만큼 넓으면 날씨가 달라진다). 저장은 어차피 약 1km 단위다.
public enum AddressQuery {
    public struct Candidate: Hashable, Sendable {
        public let query: String
        /// 넓혀 찾은 곳 이름("명지국제5로", "명지동", "부산광역시 강서구"). 고른 곳 그대로 찾는 검색어면 nil
        public let area: String?

        public var isApproximate: Bool { area != nil }

        init(_ query: String, area: String? = nil) {
            self.query = query
            self.area = area
        }
    }

    /// 후보 수 (지오코딩은 호출 수가 제한된다)
    public static let limit = 7

    public static func candidates(title: String, subtitle: String) -> [Candidate] {
        let title = clean(title)
        guard !title.isEmpty else { return [] }
        let subtitle = clean(subtitle)
        let found = subtitle.contains(",")
            ? commaCandidates(title: title, subtitle: subtitle)
            : koreanCandidates(title: title, subtitle: subtitle)
        // 같은 검색어는 한 번만
        var seen = Set<String>()
        return Array(found.filter { !$0.query.isEmpty && seen.insert($0.query).inserted }.prefix(limit))
    }

    // MARK: 한국 주소 (띄어쓰기로 나뉜 부제목)

    private static func koreanCandidates(title: String, subtitle: String) -> [Candidate] {
        let titleWords = words(title)
        var regionWords = words(subtitle).filter { !koreaNames.contains($0) && !isPostalCode($0) }
        // 부제목이 제목까지 담고 있으면("서울특별시 중구 세종대로 110") 그 부분을 뺀다
        if regionWords.count > titleWords.count, Array(regionWords.suffix(titleWords.count)) == titleWords {
            regionWords.removeLast(titleWords.count)
        }
        // 제목이 주소면 부제목과 이어서, 아니면(건물·회사 이름) 부제목 끝의 주소를 읽는다
        let titleIsAddress = Address(titleWords) != nil
        let address = titleIsAddress ? Address(regionWords + titleWords) : Address(regionWords)
        let region = address?.region ?? regionWords
        let admin = region.filter { !isDongLevel($0) }
        let dong = address?.lotDong ?? region.last(where: isDongLevel)

        var result = [Candidate(join(regionWords + titleWords))]
        if let address {
            if let road = address.road {
                result.append(Candidate(join(admin + [road] + (address.underground ? ["지하"] : []) + [address.number])))
                if address.underground {
                    result.append(Candidate(join(admin + [road, address.number])))
                }
            } else if let lotDong = address.lotDong {
                result.append(Candidate(join(admin + [lotDong, address.number])))
            }
        }
        if !titleIsAddress {
            result.append(Candidate(title))
        }

        // 넓혀 찾기는 시·도부터 아는 국내 주소만
        guard let province = admin.first, provinces.contains(province) else { return result }
        if let road = address?.road {
            result.append(Candidate(join(admin + [road]), area: road))
            if let parent = parentRoad(road) {
                result.append(Candidate(join(admin + [parent]), area: parent))
            }
        }
        if let dong {
            result.append(Candidate(join(admin + [dong]), area: dong))
        }
        // 시군구를 뒤에서부터 줄인다. 시·도만 남기지는 않는다(세종처럼 시군구가 없는 곳은 예외)
        let smallest = singleLevelProvinces.contains(province) ? 1 : 2
        if admin.count >= smallest {
            for count in stride(from: admin.count, through: smallest, by: -1) {
                let area = join(Array(admin.prefix(count)))
                result.append(Candidate(area, area: area))
            }
        }
        return result
    }

    /// 단어들 끝의 주소: 도로명("명지국제5로 90", "강남대로 지하 396") 또는 지번("서초동 1303-22", "상리 산 12")
    struct Address: Equatable {
        /// 주소 앞의 지역 ("부산광역시 강서구 명지동")
        let region: [String]
        let road: String?
        /// 지번 주소의 동·리
        let lotDong: String?
        let underground: Bool
        /// "90", "1303-22", 지번 산이면 "산12"
        let number: String

        init?(_ words: [String]) {
            guard let last = words.last, AddressQuery.isBuildingNumber(last) else { return nil }
            var rest = Array(words.dropLast())
            var marker: String?
            if let word = rest.last, word == "지하" || word == "산" {
                marker = word
                rest.removeLast()
            }
            guard let name = rest.popLast() else { return nil }
            if AddressQuery.isRoad(name), marker != "산" {
                road = name
                lotDong = nil
                underground = marker == "지하"
                number = last
            } else if AddressQuery.isDongLevel(name), marker != "지하" {
                road = nil
                lotDong = name
                underground = false
                number = marker == "산" ? "산" + last : last
            } else {
                return nil
            }
            region = rest
        }
    }

    // MARK: 해외 주소 (쉼표로 나뉜 부제목)

    /// "제목, 부제목" 다음에 구성요소를 앞에서부터 빼며 넓힌다. 마지막 구성요소(대개 나라)만으로는 찾지 않는다.
    private static func commaCandidates(title: String, subtitle: String) -> [Candidate] {
        let parts = subtitle.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !koreaNames.contains($0) }
        var result = [Candidate(([title] + parts).joined(separator: ", "))]
        for index in parts.indices.dropLast() {
            result.append(Candidate(parts[index...].joined(separator: ", "), area: parts[index]))
        }
        return result
    }

    // MARK: 낱말

    /// 괄호 안("(역삼동)")을 빼고 띄어쓰기를 하나로
    static func clean(_ text: String) -> String {
        var kept = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "（": depth += 1
            case ")", "）": depth = max(0, depth - 1)
            default: if depth == 0 { kept.append(character) }
            }
        }
        return join(words(kept))
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func join(_ words: [String]) -> String {
        words.joined(separator: " ")
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "90", "1303-22", "산12"
    static func isBuildingNumber(_ word: String) -> Bool {
        let number = word.hasPrefix("산") ? word.dropFirst() : Substring(word)
        let parts = number.split(separator: "-", omittingEmptySubsequences: false)
        return (1...2).contains(parts.count) && parts.allSatisfy(isDigits)
    }

    /// 다섯 자리 우편번호
    static func isPostalCode(_ word: String) -> Bool {
        word.count == 5 && isDigits(Substring(word))
    }

    /// "명지국제5로", "테헤란로4길", "중앙대로123번길"
    static func isRoad(_ word: String) -> Bool {
        word.count >= 2 && (word.hasSuffix("로") || word.hasSuffix("길")) && word.contains(where: isHangul)
    }

    /// 동·리·가 ("명지동", "상리", "태평로1가"). 읍·면은 도로명 주소에도 들어가므로 시군구 쪽으로 본다.
    static func isDongLevel(_ word: String) -> Bool {
        word.count >= 2 && (word.hasSuffix("동") || word.hasSuffix("리") || word.hasSuffix("가"))
            && word.contains(where: isHangul)
    }

    /// 번호 붙은 길의 큰 길: "테헤란로4길" → "테헤란로", "중앙대로123번길" → "중앙대로". 없으면 nil
    static func parentRoad(_ road: String) -> String? {
        guard road.hasSuffix("길") else { return nil }
        var name = Substring(road.dropLast())
        if name.hasSuffix("번") { name = name.dropLast() }
        let trimmed = name.reversed().drop { $0.isASCII && $0.isNumber }
        let parent = String(trimmed.reversed())
        guard parent.count < name.count, isRoad(parent) else { return nil }
        return parent
    }

    private static func isHangul(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    // MARK: 이름 목록

    /// 지도 제안 부제목에 붙는 나라 이름
    static let koreaNames: Set<String> = ["대한민국", "한국", "South Korea", "Korea", "Republic of Korea"]

    /// 17개 시·도 (정식 이름과 줄인 이름). 이것으로 시작해야 국내 주소로 보고 넓혀 찾는다.
    static let provinces: Set<String> = [
        "서울특별시", "서울시", "서울", "부산광역시", "부산시", "부산", "대구광역시", "대구시", "대구",
        "인천광역시", "인천시", "인천", "광주광역시", "광주", "대전광역시", "대전시", "대전",
        "울산광역시", "울산시", "울산", "세종특별자치시", "세종시", "세종", "경기도", "경기",
        "강원특별자치도", "강원도", "강원", "충청북도", "충북", "충청남도", "충남",
        "전북특별자치도", "전라북도", "전북", "전라남도", "전남", "경상북도", "경북", "경상남도", "경남",
        "제주특별자치도", "제주도", "제주",
    ]

    /// 시군구 없이 바로 동·도로로 이어지는 곳
    static let singleLevelProvinces: Set<String> = ["세종특별자치시", "세종시", "세종"]
}
