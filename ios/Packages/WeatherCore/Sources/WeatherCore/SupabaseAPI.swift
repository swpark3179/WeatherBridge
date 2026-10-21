import Foundation

/// 앱이 쓰는 서버 API. 읽기는 RLS(본인 행), 쓰기는 RPC, 예보는 `today`·`trips` 함수.
/// 모든 요청에 publishable key(`apikey`)와 사용자 토큰(`Authorization`)을 붙인다.
public struct SupabaseAPI: Sendable {
    public let config: AppConfig
    public let auth: AuthClient
    private let transport: HTTPTransport

    public init(config: AppConfig, transport: HTTPTransport, auth: AuthClient) {
        self.config = config
        self.transport = transport
        self.auth = auth
    }

    // MARK: 예보

    /// 집·회사 48시간 종합과 오늘 브리핑. 집·회사가 없으면 `SupabaseError.noPlaces`.
    public func today() async throws -> TodayResponse {
        do {
            return try decode(TodayResponse.self, from: await send("GET", "/functions/v1/today"))
        } catch SupabaseError.http(status: 404, code: .some("no_places"), message: _) {
            throw SupabaseError.noPlaces
        }
    }

    /// 여행마다 날짜별 목적지·집 날씨와 집의 지난 기온
    public func trips() async throws -> TripsResponse {
        try decode(TripsResponse.self, from: await send("GET", "/functions/v1/trips"))
    }

    // MARK: 장소

    public func places() async throws -> [PlaceSummary] {
        try decode(
            [PlaceSummary].self,
            from: await send(
                "GET",
                "/rest/v1/places",
                query: [
                    ("select", "id,kind,name,tz"),
                    ("active", "eq.true"),
                    ("kind", "in.(home,office)"),
                    ("order", "created_at"),
                ]
            )
        )
    }

    /// 집 또는 회사 저장. 좌표는 보내기 전에 소수 둘째 자리로 반올림한다(서버도 다시 반올림).
    @discardableResult
    public func setPlace(kind: PlaceKind, name: String, coordinate: Coordinate, tz: String) async throws -> String {
        let c = coordinate.rounded2
        let body = try encode(SetPlaceParams(kind: kind.rawValue, name: name, lat: c.lat, lon: c.lon, tz: tz))
        return try decode(String.self, from: await send("POST", "/rest/v1/rpc/set_place", body: body))
    }

    // MARK: 여행

    /// 여행 저장. `id`가 nil이면 새로 만들고, 있으면 그 여행을 바꾼다. 날짜는 목적지 달력 날짜.
    /// 고칠 때 `destination`이 nil이면 목적지(좌표·시간대)는 그대로 둔다(앱은 좌표를 받지 않는다).
    @discardableResult
    public func setTrip(
        id: String? = nil,
        name: String,
        destination: (coordinate: Coordinate, tz: String)?,
        start: LocalDate,
        end: LocalDate
    ) async throws -> String {
        let c = destination?.coordinate.rounded2
        let params = SetTripParams(
            id: id, name: name, lat: c?.lat, lon: c?.lon, tz: destination?.tz, start: start, end: end
        )
        return try decode(String.self, from: await send("POST", "/rest/v1/rpc/set_trip", body: try encode(params)))
    }

    public func deleteTrip(id: String) async throws {
        _ = try await send("POST", "/rest/v1/rpc/delete_trip", body: try encode(["p_id": id]))
    }

    // MARK: 설정

    public func settings() async throws -> UserSettings? {
        let rows = try decode(
            [UserSettings].self,
            from: await send(
                "GET",
                "/rest/v1/user_settings",
                query: [("select", "tz,summary_enabled,summary_time,commute_time,commute_days,skip_holidays,threshold")]
            )
        )
        return rows.first
    }

    /// 설정 저장(없으면 만들고 있으면 덮어쓴다). user_id는 서버가 토큰으로 정한다.
    public func saveSettings(_ settings: UserSettings) async throws {
        _ = try await send(
            "POST",
            "/rest/v1/user_settings",
            query: [("on_conflict", "user_id")],
            body: try encode(settings.normalized),
            headers: ["prefer": "resolution=merge-duplicates,return=minimal"]
        )
    }

    // MARK: 기기·계정

    /// APNs 토큰 등록. 같은 토큰이 다른(이전) 사용자에게 있으면 서버가 지금 사용자로 옮긴다.
    public func registerDevice(
        apnsToken: String,
        environment: ApnsEnvironment,
        pushToStartToken: String?,
        appVersion: String?
    ) async throws {
        let params = RegisterDeviceParams(
            token: apnsToken.lowercased(),
            env: environment.rawValue,
            pushToStart: pushToStartToken?.lowercased(),
            appVersion: appVersion
        )
        _ = try await send("POST", "/rest/v1/rpc/register_device", body: try encode(params))
    }

    /// 계정과 모든 데이터를 지우고 저장된 세션도 버린다.
    public func deleteAccount() async throws {
        _ = try await send("POST", "/rest/v1/rpc/delete_my_account", body: Data("{}".utf8))
        await auth.signOut()
    }

    // MARK: 요청

    func send(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        body: Data? = nil,
        headers extra: [String: String] = [:]
    ) async throws -> HTTPResponse {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        let url = components.url!

        func request(_ session: AuthSession) -> HTTPRequest {
            var headers = [
                "apikey": config.publishableKey,
                "authorization": "Bearer \(session.accessToken)",
                "accept": "application/json",
            ]
            if body != nil { headers["content-type"] = "application/json" }
            headers.merge(extra) { _, new in new }
            return HTTPRequest(method: method, url: url, headers: headers, body: body)
        }

        var response = try await transport.send(request(try await auth.validSession()))
        if response.status == 401 {
            // 접근 토큰이 서버 쪽에서 만료·폐기된 경우 한 번만 새로 받아 다시 시도한다.
            response = try await transport.send(request(try await auth.forceRefresh()))
        }
        guard (200..<300).contains(response.status) else {
            throw SupabaseError.from(response)
        }
        return response
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw SupabaseError.decoding("\(T.self): \(error)")
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }
}

private struct SetPlaceParams: Encodable {
    let kind: String
    let name: String
    let lat: Double
    let lon: Double
    let tz: String

    enum CodingKeys: String, CodingKey {
        case kind = "p_kind"
        case name = "p_name"
        case lat = "p_lat"
        case lon = "p_lon"
        case tz = "p_tz"
    }
}

private struct SetTripParams: Encodable {
    let id: String?
    let name: String
    let lat: Double?
    let lon: Double?
    let tz: String?
    let start: LocalDate
    let end: LocalDate

    /// 좌표·시간대는 없어도 null로 보낸다(기본값이 없는 인자라 빠지면 서버가 함수를 찾지 못한다).
    /// p_id는 없으면 뺀다(서버 기본값 null).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encode(tz, forKey: .tz)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }

    enum CodingKeys: String, CodingKey {
        case id = "p_id"
        case name = "p_name"
        case lat = "p_lat"
        case lon = "p_lon"
        case tz = "p_tz"
        case start = "p_start"
        case end = "p_end"
    }
}

private struct RegisterDeviceParams: Encodable {
    let token: String
    let env: String
    let pushToStart: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case token = "p_token"
        case env = "p_env"
        case pushToStart = "p_push_to_start_token"
        case appVersion = "p_app_version"
    }
}
