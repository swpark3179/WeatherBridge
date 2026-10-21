import Foundation
import WeatherCore

enum AppTab: Hashable {
    case today, compare, trips, settings
}

/// 앱 전체 상태: 로그인(익명), 집·회사, 설정, 오늘 예보, 여행, 기기 등록.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// 서버 접속 정보가 없는 빌드 (CI 시뮬레이터 빌드)
        case notConfigured
        case onboarding
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var places: [PlaceSummary] = []
    @Published private(set) var settings: UserSettings
    /// 서버에 설정이 한 번이라도 저장돼 있으면 true
    @Published private(set) var hasSavedSettings = false
    @Published private(set) var today: TodayResponse?
    /// 화면의 today가 저장해 둔 응답(네트워크로 새로 받지 못함)이면 true
    @Published private(set) var todayIsCached = false
    @Published private(set) var todayError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var trips: TripsResponse?
    /// 화면의 trips가 저장해 둔 응답이면 true
    @Published private(set) var tripsIsCached = false
    @Published private(set) var tripsError: String?
    @Published private(set) var isRefreshingTrips = false
    /// 잠깐 보여줄 안내 (저장 실패 등)
    @Published var notice: String?
    /// 오늘 화면에서 비교 탭으로 바로 갈 때 바꾼다
    @Published var selectedTab: AppTab = .today
    /// 비교 탭에서 보여줄 장소
    @Published var comparePlace: PlaceKind = .home

    let apnsEnvironment: ApnsEnvironment
    let appVersion: String
    private let api: SupabaseAPI?
    private var apnsToken: String?
    private var pushToStartToken: String?
    private var registered: (apns: String, pushToStart: String?)?
    private var registrationFailed = false
    /// 여행을 받는 중에 저장·삭제가 있었으면 끝나고 한 번 더 받는다
    private var tripsReloadPending = false

    init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        let config = AppConfig(infoDictionary: info)
        apnsEnvironment = ApnsEnvironment(rawValue: info["WBApnsEnv"] as? String ?? "") ?? .production
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        appVersion = "\(version) (\(build))"
        settings = UserSettings(tz: TimeZone.current.identifier)
        if config.isConfigured {
            let transport = URLSessionTransport()
            let auth = AuthClient(config: config, transport: transport, store: KeychainSessionStore())
            api = SupabaseAPI(config: config, transport: transport, auth: auth)
        } else {
            api = nil
        }
    }

    var home: PlaceSummary? { places.first { $0.kind == .home } }
    var office: PlaceSummary? { places.first { $0.kind == .office } }

    /// 지금 시간부터 `hours`시간 안의 출근 시각 (장소 시간대 기준). 공휴일은 아직 빼지 않는다.
    func commuteTimes(tz: String, now: Int, hours: Int = 24) -> [Int] {
        LocalClock(tz: tz).occurrences(
            of: settings.commuteTime,
            days: settings.commuteDays,
            from: now - now % 3600,
            to: now + hours * 3600
        )
    }

    /// 비교 탭의 그 장소로 바로 간다
    func openCompare(_ kind: PlaceKind) {
        comparePlace = kind
        selectedTab = .compare
    }

    // MARK: 시작

    func start() async {
        guard let api else {
            phase = .notConfigured
            return
        }
        phase = .loading
        if today == nil, let cached = ResponseCache.today.load() {
            today = cached
            todayIsCached = true
        }
        if trips == nil, let cached = ResponseCache.trips.load() {
            trips = cached
            tripsIsCached = true
        }
        do {
            async let loadedPlaces = api.places()
            async let loadedSettings = api.settings()
            places = try await loadedPlaces
            if let saved = try await loadedSettings {
                settings = saved
                hasSavedSettings = true
            }
            if await api.auth.didStartOver {
                notice = "로그인 정보가 만료되어 새로 시작합니다. 집·회사를 다시 등록해 주세요."
            }
            phase = home != nil && office != nil ? .ready : .onboarding
            await registerDeviceIfNeeded()
            if phase == .ready {
                await refreshAll()
            }
        } catch {
            if today != nil {
                // 오프라인 등: 저장해 둔 예보를 보여주고 다음 새로고침 때 다시 시도한다
                phase = .ready
                todayError = Self.describe(error)
            } else {
                phase = .failed(Self.describe(error))
            }
        }
    }

    // MARK: 장소·설정

    func savePlace(kind: PlaceKind, name: String, coordinate: Coordinate) async throws {
        guard let api else { throw SupabaseError.notConfigured }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try await api.setPlace(kind: kind, name: trimmed, coordinate: coordinate, tz: TimeZone.current.identifier)
        places = try await api.places()
        if phase == .ready {
            await refreshToday()
            // 여행의 "지금"은 집 최근 3일이라 집이 바뀌면 다시 받는다
            if kind == .home { await refreshTrips() }
        }
    }

    func saveSettings(_ new: UserSettings) async throws {
        guard let api else { throw SupabaseError.notConfigured }
        var s = new
        s.tz = TimeZone.current.identifier
        try await api.saveSettings(s)
        settings = s.normalized
        hasSavedSettings = true
    }

    /// 설정 화면처럼 바로바로 저장하는 곳에서 쓴다. 실패하면 안내만 띄운다.
    func saveSettingsQuietly(_ new: UserSettings) {
        Task {
            do {
                try await saveSettings(new)
            } catch {
                notice = "설정을 저장하지 못했습니다: \(Self.describe(error))"
            }
        }
    }

    func finishOnboarding() {
        phase = .ready
        Task { await refreshAll() }
    }

    // MARK: 예보

    /// 오늘과 여행을 함께 받는다
    func refreshAll() async {
        async let todayDone: Void = refreshToday()
        async let tripsDone: Void = refreshTrips()
        _ = await (todayDone, tripsDone)
    }

    func refreshToday() async {
        guard let api, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await api.today()
            today = fresh
            todayIsCached = false
            todayError = nil
            ResponseCache.today.save(fresh)
        } catch SupabaseError.noPlaces {
            phase = .onboarding
        } catch {
            todayError = Self.describe(error)
        }
    }

    // MARK: 여행

    func refreshTrips() async {
        guard let api else { return }
        if isRefreshingTrips {
            tripsReloadPending = true
            return
        }
        isRefreshingTrips = true
        defer { isRefreshingTrips = false }
        repeat {
            tripsReloadPending = false
            do {
                let fresh = try await api.trips()
                trips = fresh
                tripsIsCached = false
                tripsError = nil
                ResponseCache.trips.save(fresh)
            } catch {
                tripsError = Self.describe(error)
            }
        } while tripsReloadPending
    }

    /// 여행 저장. `id`가 nil이면 새 여행. 고칠 때 `destination`이 nil이면 목적지는 그대로 둔다.
    @discardableResult
    func saveTrip(
        id: String?,
        name: String,
        destination: (coordinate: Coordinate, tz: String)?,
        start: LocalDate,
        end: LocalDate
    ) async throws -> String {
        guard let api else { throw SupabaseError.notConfigured }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30))
        let saved = try await api.setTrip(id: id, name: trimmed, destination: destination, start: start, end: end)
        await refreshTrips()
        return saved
    }

    func deleteTrip(id: String) async throws {
        guard let api else { throw SupabaseError.notConfigured }
        try await api.deleteTrip(id: id)
        trips?.trips.removeAll { $0.id == id }
        await refreshTrips()
    }

    // MARK: 기기 등록

    /// 앱이 다시 앞으로 나올 때. 등록에 실패했었다면 다음 실행까지 기다리지 않고 다시 시도한다.
    func didBecomeActive() async {
        await registerDeviceIfNeeded()
        if phase == .ready {
            await refreshAll()
        }
    }

    func updateTokens(apns: String?, pushToStart: String?) {
        apnsToken = apns
        pushToStartToken = pushToStart
        Task { await registerDeviceIfNeeded() }
    }

    private func registerDeviceIfNeeded() async {
        guard let api, let apnsToken, phase != .loading, phase != .notConfigured else { return }
        if let registered, registered.apns == apnsToken, registered.pushToStart == pushToStartToken {
            return
        }
        do {
            try await api.registerDevice(
                apnsToken: apnsToken,
                environment: apnsEnvironment,
                pushToStartToken: pushToStartToken,
                appVersion: appVersion
            )
            registered = (apnsToken, pushToStartToken)
            registrationFailed = false
        } catch {
            // 앱이 다시 앞으로 나올 때, 다음 실행, 토큰 변경 때 다시 시도한다. 안내는 처음 실패했을 때만 띄운다.
            if !registrationFailed {
                notice = "알림 기기 등록에 실패했습니다: \(Self.describe(error))"
            }
            registrationFailed = true
        }
    }

    // MARK: 계정

    func deleteAccount() async {
        guard let api else { return }
        do {
            try await api.deleteAccount()
            places = []
            today = nil
            trips = nil
            ResponseCache.today.clear()
            ResponseCache.trips.clear()
            registered = nil
            settings = UserSettings(tz: TimeZone.current.identifier)
            hasSavedSettings = false
            phase = .onboarding
            // 새 익명 사용자로 기기를 다시 등록한다
            await registerDeviceIfNeeded()
        } catch {
            notice = "계정을 삭제하지 못했습니다: \(Self.describe(error))"
        }
    }

    // MARK: 오류 문구

    static func describe(_ error: Error) -> String {
        switch error {
        case SupabaseError.notConfigured:
            return "이 빌드에는 서버 접속 정보가 없습니다."
        case SupabaseError.noPlaces:
            return "집·회사를 먼저 등록해 주세요."
        case let SupabaseError.http(status, code, message):
            if status == 429 { return "요청이 많아 잠시 후 다시 시도해 주세요." }
            if code == "anonymous_provider_disabled" { return "서버에서 익명 로그인이 꺼져 있습니다." }
            return "서버 오류(\(status)): \(message ?? code ?? "알 수 없음")"
        case SupabaseError.decoding:
            return "서버 응답 형식이 앱과 맞지 않습니다. 앱을 업데이트해 주세요."
        case let error as URLError where error.code == .notConnectedToInternet:
            return "인터넷에 연결되어 있지 않습니다."
        default:
            return error.localizedDescription
        }
    }
}
