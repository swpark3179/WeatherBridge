import Foundation

/// Supabase Auth 세션. 익명 로그인 사용자도 같은 형식이다.
public struct AuthSession: Codable, Hashable, Sendable {
    public var accessToken: String
    /// 한 번 쓰면 바뀐다. 갱신에 성공하면 새 값을 바로 저장해야 한다.
    public var refreshToken: String
    /// 접근 토큰 만료 시각 (epoch 초)
    public var expiresAt: Int
    public var userId: String

    public init(accessToken: String, refreshToken: String, expiresAt: Int, userId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userId = userId
    }
}

/// 세션 저장소. 앱은 키체인, 테스트는 메모리.
public protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession)
    func clear()
}

public final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    public init(_ session: AuthSession? = nil) {
        self.session = session
    }

    public func load() -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    public func save(_ session: AuthSession) {
        lock.lock()
        defer { lock.unlock() }
        self.session = session
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        session = nil
    }
}

public enum SupabaseError: Error, Equatable, Sendable {
    /// 앱에 서버 접속 정보가 들어 있지 않다
    case notConfigured
    /// 서버가 2xx가 아닌 응답을 돌려줬다
    case http(status: Int, code: String?, message: String?)
    /// 응답 형식이 계약과 다르다
    case decoding(String)
    /// 집·회사가 아직 등록되지 않았다 (today 404)
    case noPlaces
}

/// 익명 로그인과 토큰 갱신.
///
/// - 저장된 세션이 없으면 익명 사용자를 만든다.
/// - 접근 토큰이 1분 안에 만료되면 갱신한다. 갱신 토큰은 한 번만 쓸 수 있으므로
///   동시에 여러 곳에서 요청해도 갱신은 한 번만 하고, 새 토큰을 먼저 저장한다.
/// - 갱신 토큰이 거부되면(다른 기기에서 쓰였거나 만료) 새 익명 사용자로 다시 시작한다.
public actor AuthClient {
    private let config: AppConfig
    private let transport: HTTPTransport
    private let store: SessionStore
    private let now: @Sendable () -> Date
    private var session: AuthSession?
    private var loaded = false
    private var pending: Task<AuthSession, Error>?
    /// 갱신에 실패해 새 사용자로 바뀐 적이 있으면 true (앱이 온보딩을 다시 보여준다)
    public private(set) var didStartOver = false

    public init(
        config: AppConfig,
        transport: HTTPTransport,
        store: SessionStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.transport = transport
        self.store = store
        self.now = now
    }

    /// 현재 사용자 ID (세션이 없으면 nil)
    public var userId: String? {
        loadIfNeeded()
        return session?.userId
    }

    /// 쓸 수 있는 세션. 필요하면 익명 가입이나 갱신을 한다.
    public func validSession() async throws -> AuthSession {
        loadIfNeeded()
        if let pending {
            return try await pending.value
        }
        if let session, session.expiresAt - 60 > Int(now().timeIntervalSince1970) {
            return session
        }
        let current = session
        let task = Task { try await self.obtain(current: current) }
        pending = task
        do {
            let result = try await task.value
            pending = nil
            return result
        } catch {
            pending = nil
            throw error
        }
    }

    /// 서버가 401을 돌려줬을 때: 접근 토큰을 버리고 다시 받는다.
    public func forceRefresh() async throws -> AuthSession {
        loadIfNeeded()
        if pending == nil, var expired = session {
            expired.expiresAt = 0
            session = expired
        }
        return try await validSession()
    }

    /// 계정 삭제 후 등: 저장된 세션을 지운다.
    public func signOut() {
        session = nil
        loaded = true
        store.clear()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        session = store.load()
        loaded = true
    }

    private func obtain(current: AuthSession?) async throws -> AuthSession {
        guard config.isConfigured else { throw SupabaseError.notConfigured }
        if let current {
            do {
                return try await refresh(current)
            } catch SupabaseError.http(let status, _, _) where (400..<500).contains(status) && status != 429 {
                // 갱신 토큰이 더는 유효하지 않다 → 새 익명 사용자
                didStartOver = true
            }
        }
        return try await signUpAnonymously()
    }

    private func signUpAnonymously() async throws -> AuthSession {
        let result = try await tokenRequest(path: "/auth/v1/signup", body: Data("{}".utf8))
        return result
    }

    private func refresh(_ current: AuthSession) async throws -> AuthSession {
        let body = try JSONEncoder().encode(["refresh_token": current.refreshToken])
        return try await tokenRequest(path: "/auth/v1/token", query: "grant_type=refresh_token", body: body)
    }

    private func tokenRequest(path: String, query: String? = nil, body: Data) async throws -> AuthSession {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.query = query
        let request = HTTPRequest(
            method: "POST",
            url: components.url!,
            headers: ["apikey": config.publishableKey, "content-type": "application/json"],
            body: body
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.status) else {
            throw SupabaseError.from(response)
        }
        let token: TokenResponse
        do {
            token = try JSONDecoder().decode(TokenResponse.self, from: response.body)
        } catch {
            throw SupabaseError.decoding("auth: \(error)")
        }
        let nowSec = Int(now().timeIntervalSince1970)
        let fresh = AuthSession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiresAt ?? nowSec + (token.expiresIn ?? 3600),
            userId: token.user.id
        )
        // 새 갱신 토큰을 먼저 저장한다(앱이 이 사이에 종료돼도 다음 실행에서 쓸 수 있게).
        store.save(fresh)
        session = fresh
        return fresh
    }
}

private struct TokenResponse: Decodable {
    struct User: Decodable {
        let id: String
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expiresAt: Int?
    let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

extension SupabaseError {
    /// Auth(`code`, `msg`), PostgREST(`code`, `message`), 함수(`code`, `error`) 오류 본문을 모두 읽는다.
    static func from(_ response: HTTPResponse) -> SupabaseError {
        struct Body: Decodable {
            var code: String?
            var errorCode: String?
            var msg: String?
            var message: String?
            var error: String?

            enum CodingKeys: String, CodingKey {
                case code, msg, message, error
                case errorCode = "error_code"
            }

            // Auth는 code가 숫자(HTTP 상태)일 때가 있어 필드마다 따로 읽고, 문자열이 아니면 버린다.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                code = try? c.decodeIfPresent(String.self, forKey: .code)
                errorCode = try? c.decodeIfPresent(String.self, forKey: .errorCode)
                msg = try? c.decodeIfPresent(String.self, forKey: .msg)
                message = try? c.decodeIfPresent(String.self, forKey: .message)
                error = try? c.decodeIfPresent(String.self, forKey: .error)
            }
        }
        let body = try? JSONDecoder().decode(Body.self, from: response.body)
        return .http(
            status: response.status,
            code: body?.errorCode ?? body?.code,
            message: body?.msg ?? body?.message ?? body?.error
        )
    }
}
