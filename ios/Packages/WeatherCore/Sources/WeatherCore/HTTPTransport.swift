import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP 요청 한 건. 테스트에서 가짜 전송 계층으로 바꿔 끼울 수 있게 URLRequest 대신 쓴다.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data = Data()) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// URLSession 전송 계층 (앱에서 사용)
public struct URLSessionTransport: HTTPTransport {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 20) {
        self.timeout = timeout
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: HTTPResponse(status: status, body: data ?? Data()))
            }.resume()
        }
    }
}

/// 서버 접속 정보. 저장소에 넣지 않고 빌드할 때 Info.plist로 주입한다(docs/decisions.md D15).
public struct AppConfig: Sendable, Equatable {
    public var projectRef: String
    public var publishableKey: String

    public init(projectRef: String, publishableKey: String) {
        self.projectRef = projectRef.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publishableKey = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Info.plist 값(`WBSupabaseProjectRef`, `WBSupabasePublishableKey`)으로 만든다.
    public init(infoDictionary: [String: Any]) {
        self.init(
            projectRef: infoDictionary["WBSupabaseProjectRef"] as? String ?? "",
            publishableKey: infoDictionary["WBSupabasePublishableKey"] as? String ?? ""
        )
    }

    /// CI 시뮬레이터 빌드처럼 값이 비어 있으면 false
    public var isConfigured: Bool {
        !projectRef.isEmpty && publishableKey.hasPrefix("sb_publishable_")
            && projectRef.allSatisfy { $0.isLetter || $0.isNumber }
    }

    public var baseURL: URL {
        URL(string: "https://\(projectRef).supabase.co")!
    }
}
