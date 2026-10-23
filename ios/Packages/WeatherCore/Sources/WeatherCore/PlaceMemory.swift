import Foundation

/// 이 기기에서 고른 장소 하나의 표시 정보: 이름, 주소, 약 1km 좌표, 시간대, 넓혀 찾았는지.
public struct RememberedPlace: Codable, Hashable, Sendable {
    /// 서버 장소 id(집·회사) 또는 여행 id. 지금 id와 다르면 쓰지 않는다
    public var id: String
    /// "서울특별시청"
    public var label: String
    /// "서울특별시 중구 세종대로 110"
    public var subtitle: String?
    /// 약 1km로 반올림한 좌표 (서버에 보낸 값과 같다)
    public var coordinate: Coordinate
    /// IANA 시간대 (알 때만)
    public var tz: String?
    /// 고른 곳을 찾지 못해 넓혀 찾은 곳 ("명지국제5로"). 고른 곳 그대로면 nil (D28)
    public var approximateArea: String?

    public init(
        id: String,
        label: String,
        subtitle: String? = nil,
        coordinate: Coordinate,
        tz: String? = nil,
        approximateArea: String? = nil
    ) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.coordinate = coordinate.rounded2
        self.tz = tz
        self.approximateArea = approximateArea
    }
}

/// 이 기기에만 기억해 두는 장소 표시 정보. 서버는 좌표를 돌려주지 않으므로, 다시 열었을 때
/// 무엇을 골랐는지(지도·주소) 보여 주는 데만 쓴다(D27). 다른 기기에서 바꿨거나 새로 시작해 id가 바뀌면 쓰지 않는다.
public struct PlaceMemory: Codable, Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        /// 집·회사 (사용자마다 하나)
        case place(PlaceKind)
        case trip(String)

        var name: String {
            switch self {
            case let .place(kind): kind.rawValue
            case let .trip(id): Self.tripPrefix + id
            }
        }

        static let tripPrefix = "trip:"
    }

    /// `Key.name` → 장소
    private var entries: [String: RememberedPlace]

    public init() {
        entries = [:]
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// 기억해 둔 장소. 기억해 둔 id가 `id`(지금 서버의 id)와 다르면 nil
    public func place(_ key: Key, id: String) -> RememberedPlace? {
        guard let entry = entries[key.name], entry.id == id else { return nil }
        return entry
    }

    public mutating func remember(_ place: RememberedPlace, as key: Key) {
        entries[key.name] = place
    }

    public mutating func forget(_ key: Key) {
        entries[key.name] = nil
    }

    /// `ids`에 없는 여행(지웠거나 목록에서 사라진 여행)은 잊는다
    public mutating func keepTrips(_ ids: Set<String>) {
        entries = entries.filter { name, place in !name.hasPrefix(Key.tripPrefix) || ids.contains(place.id) }
    }
}
