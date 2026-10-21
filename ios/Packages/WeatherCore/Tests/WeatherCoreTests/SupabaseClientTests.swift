import Foundation
import Testing
@testable import WeatherCore

/// 경로별로 정해 둔 응답을 돌려주고 요청을 기록하는 가짜 전송 계층
actor FakeTransport: HTTPTransport {
    typealias Handler = @Sendable (HTTPRequest) -> HTTPResponse

    private var routes: [(String, Handler)] = []
    private(set) var requests: [HTTPRequest] = []
    private let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func on(_ path: String, _ handler: @escaping Handler) {
        routes.append((path, handler))
    }

    func on(_ path: String, status: Int = 200, json: String) {
        routes.append((path, { _ in HTTPResponse(status: status, body: Data(json.utf8)) }))
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        guard let route = routes.last(where: { request.url.path == $0.0 }) else {
            return HTTPResponse(status: 599, body: Data("{\"message\":\"no route \(request.url.path)\"}".utf8))
        }
        return route.1(request)
    }

    func count(_ path: String) -> Int {
        requests.filter { $0.url.path == path }.count
    }
}

private let config = AppConfig(projectRef: "abcdefgh", publishableKey: "sb_publishable_test")
private let now = Date(timeIntervalSince1970: 1_792_444_200)

private func tokenJSON(access: String, refresh: String, user: String = "user-1", expiresIn: Int = 3600) -> String {
    """
    {"access_token":"\(access)","token_type":"bearer","expires_in":\(expiresIn),
     "refresh_token":"\(refresh)","user":{"id":"\(user)","is_anonymous":true}}
    """
}

private func client(_ transport: FakeTransport, store: SessionStore) -> (AuthClient, SupabaseAPI) {
    let auth = AuthClient(config: config, transport: transport, store: store, now: { now })
    return (auth, SupabaseAPI(config: config, transport: transport, auth: auth))
}

@Suite struct AuthClientTests {
    @Test func signsUpAnonymouslyWhenThereIsNoSession() async throws {
        let transport = FakeTransport()
        await transport.on("/auth/v1/signup", json: tokenJSON(access: "a1", refresh: "r1"))
        let store = MemorySessionStore()
        let (auth, _) = client(transport, store: store)

        let session = try await auth.validSession()

        #expect(session.accessToken == "a1")
        #expect(session.userId == "user-1")
        #expect(session.expiresAt == Int(now.timeIntervalSince1970) + 3600)
        #expect(store.load() == session)
        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == "https://abcdefgh.supabase.co/auth/v1/signup")
        #expect(request.headers["apikey"] == "sb_publishable_test")
        #expect(request.headers["authorization"] == nil)
    }

    @Test func reusesAFreshSessionWithoutNetwork() async throws {
        let transport = FakeTransport()
        let fresh = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Int(now.timeIntervalSince1970) + 600, userId: "u")
        let (auth, _) = client(transport, store: MemorySessionStore(fresh))
        #expect(try await auth.validSession() == fresh)
        #expect(await transport.requests.isEmpty)
    }

    @Test func refreshesOnceForConcurrentCallers() async throws {
        let transport = FakeTransport(delay: .milliseconds(50))
        await transport.on("/auth/v1/token", json: tokenJSON(access: "a2", refresh: "r2"))
        let expired = AuthSession(accessToken: "a1", refreshToken: "r1", expiresAt: Int(now.timeIntervalSince1970) + 30, userId: "user-1")
        let store = MemorySessionStore(expired)
        let (auth, _) = client(transport, store: store)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await auth.validSession().accessToken }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(tokens == Array(repeating: "a2", count: 5))
        #expect(await transport.count("/auth/v1/token") == 1)
        let request = try #require(await transport.requests.first)
        #expect(request.url.query == "grant_type=refresh_token")
        let body = try JSONDecoder().decode([String: String].self, from: request.body ?? Data())
        #expect(body == ["refresh_token": "r1"])
        #expect(store.load()?.refreshToken == "r2")
    }

    @Test func startsOverWhenTheRefreshTokenIsRejected() async throws {
        let transport = FakeTransport()
        await transport.on("/auth/v1/token", status: 400, json: #"{"code":400,"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#)
        await transport.on("/auth/v1/signup", json: tokenJSON(access: "new", refresh: "rn", user: "user-2"))
        let expired = AuthSession(accessToken: "old", refreshToken: "used", expiresAt: 0, userId: "user-1")
        let (auth, _) = client(transport, store: MemorySessionStore(expired))

        let session = try await auth.validSession()

        #expect(session.userId == "user-2")
        #expect(await auth.didStartOver)
    }

    @Test func keepsTheSessionOnServerErrors() async throws {
        let transport = FakeTransport()
        await transport.on("/auth/v1/token", status: 503, json: #"{"msg":"unavailable"}"#)
        let expired = AuthSession(accessToken: "old", refreshToken: "r1", expiresAt: 0, userId: "user-1")
        let store = MemorySessionStore(expired)
        let (auth, _) = client(transport, store: store)

        await #expect(throws: SupabaseError.http(status: 503, code: nil, message: "unavailable")) {
            try await auth.validSession()
        }
        #expect(await transport.count("/auth/v1/signup") == 0)
        #expect(store.load()?.refreshToken == "r1")
    }

    @Test func refusesToRunWithoutConfiguration() async throws {
        let auth = AuthClient(
            config: AppConfig(projectRef: "", publishableKey: ""),
            transport: FakeTransport(),
            store: MemorySessionStore()
        )
        await #expect(throws: SupabaseError.notConfigured) {
            try await auth.validSession()
        }
    }
}

private struct SetPlaceBody: Decodable, Equatable {
    let p_kind: String
    let p_name: String
    let p_lat: Double
    let p_lon: Double
    let p_tz: String
}

private struct SetTripBody: Decodable, Equatable {
    let p_id: String?
    let p_name: String
    let p_lat: Double
    let p_lon: Double
    let p_tz: String
    let p_start: String
    let p_end: String
}

private struct UpdateTripBody: Decodable {
    let p_id: String
    let p_end: String
}

@Suite struct SupabaseAPITests {
    private func signedIn() async -> (FakeTransport, AuthClient, SupabaseAPI) {
        let transport = FakeTransport()
        let session = AuthSession(accessToken: "tok", refreshToken: "r", expiresAt: Int(now.timeIntervalSince1970) + 3600, userId: "u")
        let (auth, api) = client(transport, store: MemorySessionStore(session))
        return (transport, auth, api)
    }

    @Test func todayDecodesTheContractFixture() async throws {
        let (transport, _, api) = await signedIn()
        let url = try #require(Bundle.module.url(forResource: "today_response", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try Data(contentsOf: url)
        await transport.on("/functions/v1/today") { _ in HTTPResponse(status: 200, body: fixture) }

        let today = try await api.today()

        #expect(today.places.map(\.name) == ["집", "회사"])
        let request = try #require(await transport.requests.first)
        #expect(request.method == "GET")
        #expect(request.headers["authorization"] == "Bearer tok")
        #expect(request.headers["apikey"] == "sb_publishable_test")
    }

    @Test func todayReportsMissingPlaces() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/functions/v1/today", status: 404, json: #"{"error":"집·회사를 먼저 등록해 주세요","code":"no_places"}"#)
        await #expect(throws: SupabaseError.noPlaces) {
            try await api.today()
        }
    }

    @Test func retriesOnceWithAFreshTokenAfter401() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/auth/v1/token", json: tokenJSON(access: "tok2", refresh: "r2"))
        await transport.on("/rest/v1/places") { request in
            request.headers["authorization"] == "Bearer tok2"
                ? HTTPResponse(status: 200, body: Data(#"[{"id":"p1","kind":"home","name":"집","tz":"Asia/Seoul"}]"#.utf8))
                : HTTPResponse(status: 401, body: Data(#"{"message":"JWT expired"}"#.utf8))
        }

        let places = try await api.places()

        #expect(places == [PlaceSummary(id: "p1", kind: .home, name: "집", tz: "Asia/Seoul")])
        #expect(await transport.count("/rest/v1/places") == 2)
        #expect(await transport.count("/auth/v1/token") == 1)
    }

    @Test func setPlaceSendsRoundedCoordinates() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/rest/v1/rpc/set_place", json: #""8f3c""#)

        let id = try await api.setPlace(
            kind: .office,
            name: "회사",
            coordinate: Coordinate(lat: 37.56654, lon: 126.97796),
            tz: "Asia/Seoul"
        )

        #expect(id == "8f3c")
        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST")
        let body = try JSONDecoder().decode(SetPlaceBody.self, from: request.body ?? Data())
        #expect(body == SetPlaceBody(p_kind: "office", p_name: "회사", p_lat: 37.57, p_lon: 126.98, p_tz: "Asia/Seoul"))
    }

    @Test func settingsRoundTripUsesPostgresShapes() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on(
            "/rest/v1/user_settings",
            json: #"[{"tz":"Asia/Seoul","summary_enabled":true,"summary_time":"07:30:00","commute_time":"08:45:00","commute_days":[1,2,3,4,5],"skip_holidays":true,"threshold":30}]"#
        )

        let settings = try #require(try await api.settings())
        #expect(settings.summaryTime == ClockTime(hour: 7, minute: 30))
        #expect(settings.commuteTime == ClockTime(hour: 8, minute: 45))

        var changed = settings
        changed.threshold = 5
        changed.commuteDays = [6, 1, 1, 9]
        await transport.on("/rest/v1/user_settings", status: 201, json: "")
        try await api.saveSettings(changed)

        let save = try #require(await transport.requests.last)
        #expect(save.method == "POST")
        #expect(save.url.query?.contains("on_conflict=user_id") == true)
        #expect(save.headers["prefer"] == "resolution=merge-duplicates,return=minimal")
        let saved = try JSONDecoder().decode(UserSettings.self, from: save.body ?? Data())
        #expect(saved.summaryTime == ClockTime(hour: 7, minute: 30))
        #expect(saved.threshold == 10)
        #expect(saved.commuteDays == [1, 6])
        let raw = String(decoding: save.body ?? Data(), as: UTF8.self)
        #expect(raw.contains(#""summary_time":"07:30""#))
        #expect(!raw.contains("user_id"))
    }

    @Test func registerDeviceSendsLowercaseTokensAndEnvironment() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/rest/v1/rpc/register_device", status: 204, json: "")

        try await api.registerDevice(apnsToken: "ABCD12", environment: .production, pushToStartToken: nil, appVersion: "0.1.0 (7.1)")

        let body = try JSONDecoder().decode([String: String].self, from: (await transport.requests.first)?.body ?? Data())
        #expect(body["p_token"] == "abcd12")
        #expect(body["p_env"] == "production")
        #expect(body["p_app_version"] == "0.1.0 (7.1)")
        #expect(body["p_push_to_start_token"] == nil)
    }

    @Test func deleteAccountSignsOut() async throws {
        let (transport, auth, api) = await signedIn()
        await transport.on("/rest/v1/rpc/delete_my_account", status: 204, json: "")
        try await api.deleteAccount()
        #expect(await auth.userId == nil)
    }

    @Test func tripsDecodesTheContractFixture() async throws {
        let (transport, _, api) = await signedIn()
        let url = try #require(Bundle.module.url(forResource: "trips_response", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try Data(contentsOf: url)
        await transport.on("/functions/v1/trips") { _ in HTTPResponse(status: 200, body: fixture) }

        let trips = try await api.trips()

        #expect(trips.trips.map(\.name) == ["콜카타", "삿포로", "파리", "제주"])
        let request = try #require(await transport.requests.first)
        #expect(request.method == "GET")
        #expect(request.headers["authorization"] == "Bearer tok")
    }

    @Test func setTripSendsDatesAndRoundedCoordinates() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/rest/v1/rpc/set_trip", json: #""t1""#)

        let id = try await api.setTrip(
            name: "삿포로",
            destination: (Coordinate(lat: 43.06417, lon: 141.34694), "Asia/Tokyo"),
            start: LocalDate(year: 2026, month: 10, day: 23),
            end: LocalDate(year: 2026, month: 10, day: 24)
        )

        #expect(id == "t1")
        let created = try #require(await transport.requests.first)
        let body = try JSONDecoder().decode(SetTripBody.self, from: created.body ?? Data())
        #expect(body == SetTripBody(
            p_id: nil, p_name: "삿포로", p_lat: 43.06, p_lon: 141.35, p_tz: "Asia/Tokyo",
            p_start: "2026-10-23", p_end: "2026-10-24"
        ))
        // 새 여행이면 p_id를 보내지 않는다(서버 기본값 null)
        #expect(!String(decoding: created.body ?? Data(), as: UTF8.self).contains("p_id"))

        // 목적지는 그대로 두고 날짜만 고치면 좌표·시간대를 null로 보낸다
        try await api.setTrip(
            id: "t1", name: "삿포로", destination: nil,
            start: LocalDate(year: 2026, month: 10, day: 24), end: LocalDate(year: 2026, month: 10, day: 26)
        )
        let updateBody = await transport.requests.last?.body ?? Data()
        let updated = try JSONDecoder().decode(UpdateTripBody.self, from: updateBody)
        #expect(updated.p_id == "t1")
        #expect(updated.p_end == "2026-10-26")
        let raw = try #require(try JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        #expect(raw["p_lat"] is NSNull && raw["p_lon"] is NSNull && raw["p_tz"] is NSNull)
    }

    @Test func deleteTripSendsTheId() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/rest/v1/rpc/delete_trip", status: 204, json: "")
        try await api.deleteTrip(id: "t1")
        let request = try #require(await transport.requests.first)
        #expect(request.method == "POST")
        #expect(try JSONDecoder().decode([String: String].self, from: request.body ?? Data()) == ["p_id": "t1"])
    }

    @Test func surfacesPostgrestErrors() async throws {
        let (transport, _, api) = await signedIn()
        await transport.on("/rest/v1/rpc/set_place", status: 400, json: #"{"code":"22023","message":"이름은 1~30자여야 합니다"}"#)
        await #expect(throws: SupabaseError.http(status: 400, code: "22023", message: "이름은 1~30자여야 합니다")) {
            try await api.setPlace(kind: .home, name: "", coordinate: Coordinate(lat: 37, lon: 127), tz: "Asia/Seoul")
        }
    }
}

@Suite struct UserModelTests {
    @Test func clockTimeParsesAndFormats() {
        #expect(ClockTime(string: "07:05:00") == ClockTime(hour: 7, minute: 5))
        #expect(ClockTime(string: "7:05")?.description == "07:05")
        #expect(ClockTime(string: "24:00") == nil)
        #expect(ClockTime(string: "soon") == nil)
        #expect(ClockTime(hour: 7, minute: 0) < ClockTime(hour: 7, minute: 1))
    }

    @Test func coordinatesRoundToAboutOneKilometer() {
        #expect(Coordinate(lat: 37.56654, lon: 126.97796).rounded2 == Coordinate(lat: 37.57, lon: 126.98))
        #expect(Coordinate(lat: -33.8688, lon: 151.2093).rounded2 == Coordinate(lat: -33.87, lon: 151.21))
        #expect(!Coordinate(lat: 91, lon: 0).isValid)
    }

    @Test func configRequiresAPublishableKey() {
        #expect(AppConfig(projectRef: "abc123", publishableKey: "sb_publishable_x").isConfigured)
        #expect(!AppConfig(projectRef: "abc123", publishableKey: "sb_secret_x").isConfigured)
        #expect(!AppConfig(projectRef: "", publishableKey: "sb_publishable_x").isConfigured)
        #expect(!AppConfig(infoDictionary: [:]).isConfigured)
        let fromPlist = AppConfig(infoDictionary: ["WBSupabaseProjectRef": " abc123 ", "WBSupabasePublishableKey": "sb_publishable_x"])
        #expect(fromPlist.baseURL.absoluteString == "https://abc123.supabase.co")
    }
}
