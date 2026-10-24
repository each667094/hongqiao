import AppKit
import Network
import HongqiaoCore
import Security

// Only binds to loopback. This is a local simulator, never a real-phone discovery server.
@MainActor public final class DemoServer {
    public private(set) var port: UInt16 = 0
    public private(set) var token: String = ""
    public private(set) var interactions = 0
    public private(set) var page = "home"
    public private(set) var clipboard = "来自本地演示设备的文字。可复制到 Mac，或从 Mac 写入这里。"
    private var input = ""
    private var listener: NWListener?
    private var root: URL?
    private var connections: [UUID: NWConnection] = [:]
    public init() {}
    public var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
    public func start() async throws {
        guard listener == nil else { return }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BridgeError("无法生成会话令牌") }
        token = bytes.map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hongqiao-demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        root = directory
        try Data("# 鸿桥示例文档\n\n此文件由本机演示伴侣生成，不来自任何手机。\n拖入文件可测试真实字节传输。\n".utf8).write(to: directory.appendingPathComponent("欢迎使用.md"))
        try Data("项目,状态\n实时画面,本地演示\n反向控制,本地演示\n文件互传,本地字节传输\n".utf8).write(to: directory.appendingPathComponent("功能清单.csv"))
        for i in 0..<4 { try DemoArtwork.jpeg(DemoArtwork.album(i)).write(to: directory.appendingPathComponent("示例相片-\(i + 1).jpg")) }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard !resumed else { return }
                    switch state {
                    case .ready:
                        resumed = true; self?.port = listener.port?.rawValue ?? 0; continuation.resume()
                    case .failed(let error): resumed = true; continuation.resume(throwing: error)
                    default: break
                    }
                }
            }
            listener.start(queue: DispatchQueue(label: "hongqiao.demo.listener"))
        }
    }
    public func stop() {
        listener?.cancel(); listener = nil
        for c in connections.values { c.cancel() }; connections.removeAll()
        if let root { try? FileManager.default.removeItem(at: root) }; root = nil; token = ""; port = 0
    }
    private func accept(_ connection: NWConnection) {
        let id = UUID(); connections[id] = connection
        connection.start(queue: DispatchQueue(label: "hongqiao.demo.connection"))
        receive(connection, id: id, accumulated: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] bytes, _, complete, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                var data = accumulated; if let bytes { data.append(bytes) }
                guard data.count <= 24 * 1024 * 1024 else { self.respond(connection, id, status: 413, body: Data()); return }
                if let separator = data.range(of: Data("\r\n\r\n".utf8)) {
                    let header = String(decoding: data[..<separator.lowerBound], as: UTF8.self)
                    guard separator.lowerBound <= 8192 else { self.respond(connection, id, status: 431, body: Data()); return }
                    let lines = header.components(separatedBy: "\r\n")
                    var headers: [String: String] = [:]
                    for line in lines.dropFirst() {
                        if let colon = line.firstIndex(of: ":") { headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
                    }
                    guard headers["authorization"] == "Bearer \(self.token)" else { self.jsonError(connection, id, 401, "会话令牌无效"); return }
                    guard headers["transfer-encoding"] == nil, let length = Int(headers["content-length"] ?? "0"), (0...23 * 1024 * 1024).contains(length) else { self.jsonError(connection, id, 400, "无效请求长度"); return }
                    if data.count >= separator.upperBound + length {
                        let body = Data(data[separator.upperBound..<(separator.upperBound + length)])
                        self.route(connection, id, line: lines.first ?? "", body: body); return
                    }
                } else if data.count > 8192 { self.respond(connection, id, status: 431, body: Data()); return }
                if complete || error != nil { self.connections.removeValue(forKey: id); connection.cancel() }
                else { self.receive(connection, id: id, accumulated: data) }
            }
        }
        // Bounded idle time, also covers clients that send an incomplete header/body.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, let c = self.connections.removeValue(forKey: id) else { return }; c.cancel()
        }
    }
    private func route(_ c: NWConnection, _ id: UUID, line: String, body: Data) {
        let parts = line.split(separator: " ")
        guard parts.count == 3, let url = URLComponents(string: "http://localhost" + parts[1]) else { jsonError(c, id, 400, "请求无效"); return }
        let method = String(parts[0]), path = url.path
        do {
            switch (method, path) {
            case ("GET", "/v1/info"):
                let device = Device(id: "local-demo", name: "本地演示设备", system: "本机模拟 · 非 HarmonyOS 真机", width: 390, height: 780, isDemo: true)
                respond(c, id, body: try JSONEncoder().encode(device))
            case ("GET", "/v1/frame"):
                respond(c, id, contentType: "image/jpeg", body: DemoArtwork.jpeg(DemoArtwork.image(page: page, text: input, interactions: interactions)))
            case ("POST", "/v1/control"):
                let event = try JSONDecoder().decode(ControlEvent.self, from: body)
                switch event.kind {
                case "home", "back": page = "home"; input = ""
                case "text":
                    guard let text = event.text, text.utf8.count <= 8192, !text.contains("\0") else { throw BridgeError("文本超出范围") }
                    page = "备忘录"; input = text
                case "click", "longClick", "swipe", "drag":
                    guard let x = event.x, let y = event.y, (0..<390).contains(x), (0..<780).contains(y) else { throw BridgeError("坐标超出屏幕范围") }
                    if event.kind == "swipe" || event.kind == "drag" {
                        guard let x2 = event.endX, let y2 = event.endY, (0..<390).contains(x2), (0..<780).contains(y2) else { throw BridgeError("滑动终点无效") }
                    }
                    if page == "home" {
                        let apps = ["备忘录", "文件", "图库", "设置", "浏览器", "日历", "邮件", "计算器"]
                        let column = min(3, max(0, (x - 20) / 90)), row = y > 400 ? 1 : 0
                        page = apps[row * 4 + column]
                    }
                default: throw BridgeError("未知控制指令")
                }
                interactions += 1; respond(c, id, body: Data("{\"ok\":true}".utf8))
            case ("GET", "/v1/files"):
                let files = try FileManager.default.contentsOfDirectory(at: root!, includingPropertiesForKeys: [.fileSizeKey]).sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
                    RemoteFile(name: url.lastPathComponent, size: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                }
                respond(c, id, body: try JSONEncoder().encode(files))
            case ("GET", "/v1/file"):
                let name = try Shell.safeName(url.queryItems?.first(where: { $0.name == "name" })?.value ?? "")
                let data = try Data(contentsOf: root!.appendingPathComponent(name))
                respond(c, id, contentType: "application/octet-stream", body: data)
            case ("POST", "/v1/file"):
                guard let object = try JSONSerialization.jsonObject(with: body) as? [String: String], let name = object["name"], let b64 = object["base64"], let data = Data(base64Encoded: b64), data.count <= 16 * 1024 * 1024 else { throw BridgeError("演示单文件上限 16 MB，或文件格式无效") }
                let safe = try Shell.safeName(name)
                let destination = root!.appendingPathComponent(safe)
                guard !FileManager.default.fileExists(atPath: destination.path) else { jsonError(c, id, 409, "同名文件已存在，请重命名后发送"); return }
                let staging = root!.appendingPathComponent(".upload-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: staging) }
                try data.write(to: staging, options: .atomic)
                try FileManager.default.moveItem(at: staging, to: destination)
                respond(c, id, body: Data("{\"ok\":true}".utf8))
            case ("GET", "/v1/clipboard"):
                respond(c, id, body: try JSONSerialization.data(withJSONObject: ["text": clipboard]))
            case ("PUT", "/v1/clipboard"):
                guard let object = try JSONSerialization.jsonObject(with: body) as? [String: String], let text = object["text"], text.utf8.count <= 65536 else { throw BridgeError("剪贴板文本无效或超出 64 KB") }
                clipboard = text; respond(c, id, body: Data("{\"ok\":true}".utf8))
            default: jsonError(c, id, 404, "接口不存在")
            }
        } catch { jsonError(c, id, 400, error.localizedDescription) }
    }
    private func jsonError(_ c: NWConnection, _ id: UUID, _ status: Int, _ message: String) { respond(c, id, status: status, body: (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data()) }
    private func respond(_ connection: NWConnection, _ id: UUID, status: Int = 200, contentType: String = "application/json", body: Data) {
        let reason = status == 200 ? "OK" : "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [weak self] _ in
            connection.cancel(); Task { @MainActor in self?.connections.removeValue(forKey: id) }
        })
    }
}
