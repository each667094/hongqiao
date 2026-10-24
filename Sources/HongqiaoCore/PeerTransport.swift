import Foundation

public final class PeerTransport: BridgeTransport {
    public let baseURL: URL
    private let token: String
    private let session: URLSession
    public let capabilities = Capabilities(clipboardRead: true, clipboardWrite: true, photoLibrary: true)
    public init(baseURL: URL, token: String) throws {
        guard baseURL.scheme == "http", ["127.0.0.1", "localhost", "::1", "[::1]"].contains(baseURL.host ?? ""), baseURL.user == nil, baseURL.password == nil,
            baseURL.query == nil, baseURL.fragment == nil, baseURL.path.isEmpty || baseURL.path == "/", !token.isEmpty else { throw BridgeError("本地伴侣接口只允许回环地址和有效令牌，禁止明文连接局域网") }
        self.baseURL = baseURL; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12; config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false; config.urlCache = nil
        self.session = URLSession(configuration: config)
    }
    private func request(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BridgeError("伴侣没有返回 HTTP 响应") }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "接口请求失败"
            throw BridgeError("HTTP \(http.statusCode)：\(detail)")
        }
        return data
    }
    public func connect() async throws -> Device { try JSONDecoder().decode(Device.self, from: await request("v1/info")) }
    public func capture() async throws -> Frame {
        let start = Date(); let data = try await request("v1/frame")
        return Frame(data: data, elapsedMS: Date().timeIntervalSince(start) * 1000)
    }
    public func control(_ event: ControlEvent) async throws { _ = try await request("v1/control", method: "POST", body: JSONEncoder().encode(event)) }
    public func files(at path: String) async throws -> [RemoteFile] { try JSONDecoder().decode([RemoteFile].self, from: await request("v1/files")) }
    public func receive(path: String) async throws -> Data {
        let name = try Shell.safeName((path as NSString).lastPathComponent)
        return try await request("v1/file", query: [URLQueryItem(name: "name", value: name)])
    }
    public func send(data: Data, path: String) async throws {
        let name = try Shell.safeName((path as NSString).lastPathComponent)
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "base64": data.base64EncodedString()])
        _ = try await request("v1/file", method: "POST", body: body)
    }
    public func readClipboard() async throws -> String {
        let data = try await request("v1/clipboard")
        return (try JSONSerialization.jsonObject(with: data) as? [String: String])?["text"] ?? ""
    }
    public func writeClipboard(_ text: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["text": text])
        _ = try await request("v1/clipboard", method: "PUT", body: data)
    }
    public func disconnect() async { session.invalidateAndCancel() }
}
