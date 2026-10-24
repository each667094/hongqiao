import Foundation

public final class HDCTransport: BridgeTransport {
    public let executable: URL
    public let target: String
    private let scratch: URL
    private let remoteScreenshot: String
    public let capabilities = Capabilities(clipboardRead: false, clipboardWrite: false, photoLibrary: false)
    public init(executable: URL, target: String) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("请选择官方 SDK 中可执行的 hdc 文件") }
        guard !target.isEmpty, !target.hasPrefix("-"), !target.contains("\n") else { throw BridgeError("设备标识无效") }
        self.executable = executable; self.target = target
        let id = UUID().uuidString.lowercased()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("hongqiao-\(id)", isDirectory: true)
        remoteScreenshot = "/data/local/tmp/hongqiao-\(id).jpeg"
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: scratch) }
    private func run(_ arguments: [String], timeout: TimeInterval = 12) async throws -> String {
        let result = try await ProcessRunner.run(executable, ["-t", target] + arguments, timeout: timeout)
        guard result.status == 0, !result.output.contains("[Fail]") else { throw BridgeError(String(result.output.prefix(1500))) }
        return result.output
    }
    private func shell(_ arguments: [String]) async throws -> String { try await run(["shell", Shell.command(arguments)]) }
    public static func discover(executable: URL) async throws -> [String] {
        let result = try await ProcessRunner.run(executable, ["list", "targets"])
        guard result.status == 0 else { throw BridgeError(result.output) }
        return result.output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.contains("[Empty]") && !$0.hasPrefix("[Info]") }
    }
    public static func connectWireless(executable: URL, endpoint: String) async throws {
        let parts = endpoint.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port), parts[0].split(separator: ".").count == 4,
            parts[0].split(separator: ".").allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { throw BridgeError("请输入 IPv4:端口，例如 192.168.1.8:41239") }
        let r = try await ProcessRunner.run(executable, ["tconn", endpoint])
        guard r.status == 0, !r.output.lowercased().contains("fail") else { throw BridgeError(r.output) }
    }
    public func connect() async throws -> Device {
        let ids = try await Self.discover(executable: executable)
        guard ids.contains(target) else { throw BridgeError("设备未连接或未授权，请先在手机确认调试授权") }
        let model = try await shell(["param", "get", "const.product.model"])
        let system = try await shell(["param", "get", "const.product.software.version"])
        return Device(id: target, name: model.trimmingCharacters(in: .whitespacesAndNewlines), system: system.trimmingCharacters(in: .whitespacesAndNewlines), width: 0, height: 0, isDemo: false)
    }
    public func capture() async throws -> Frame {
        let start = Date()
        _ = try await shell(["snapshot_display", "-f", remoteScreenshot])
        try Task.checkCancellation()
        let local = scratch.appendingPathComponent("frame.jpeg")
        _ = try await run(["file", "recv", remoteScreenshot, local.path])
        let data = try Data(contentsOf: local)
        guard !data.isEmpty else { throw BridgeError("设备未返回截图，可能是系统保护画面或尚未授权") }
        return Frame(data: data, elapsedMS: Date().timeIntervalSince(start) * 1000)
    }
    public func control(_ e: ControlEvent) async throws {
        func coordinate(_ value: Int?) throws -> String {
            guard let value, (0...32768).contains(value) else { throw BridgeError("无效的屏幕坐标") }
            return String(value)
        }
        var args = ["uitest", "uiInput"]
        switch e.kind {
        case "click", "longClick": args += [e.kind, try coordinate(e.x), try coordinate(e.y)]
        case "swipe", "drag": args += [e.kind, try coordinate(e.x), try coordinate(e.y), try coordinate(e.endX), try coordinate(e.endY), "600"]
        case "home": args += ["keyEvent", "Home"]
        case "back": args += ["keyEvent", "Back"]
        case "text":
            guard let text = e.text, text.utf8.count <= 8192, !text.contains("\0") else { throw BridgeError("文本过长或包含空字符") }
            args += ["text", text]
        default: throw BridgeError("不支持的控制动作")
        }
        do {
            let out = try await shell(args)
            guard !out.lowercased().contains("error"), !out.lowercased().contains("failed"), !out.contains("Permission denied") else { throw BridgeError("系统拒绝控制：\(out.prefix(700))") }
        } catch {
            if e.kind == "text" { throw BridgeError("设备文字输入失败，请检查输入框焦点、UITest 权限与系统版本（不保留输入命令的返回正文）") }
            throw error
        }
    }
    public func files(at path: String) async throws -> [RemoteFile] {
        let path = try Shell.safeRemotePath(path)
        let output = try await shell(["ls", "-la", path])
        guard !output.contains("Permission denied"), !output.contains("No such file") else { throw BridgeError(output) }
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(maxSplits: 7, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 8, ["-", "d"].contains(String(parts[0].prefix(1))) else { return nil }
            let name = String(parts[7])
            guard name != ".", name != ".." else { return nil }
            return RemoteFile(name: name, size: Int64(parts[4]) ?? 0, directory: parts[0].hasPrefix("d"))
        }
    }
    public func receive(path: String) async throws -> Data {
        let path = try Shell.safeRemotePath(path)
        let local = scratch.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: local) }
        _ = try await run(["file", "recv", path, local.path], timeout: 120)
        let size = try local.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1024 * 1024 else { throw BridgeError("当前版本单文件接收上限为 256 MB") }
        return try Data(contentsOf: local)
    }
    public func send(data: Data, path: String) async throws {
        let path = try Shell.safeRemotePath(path)
        guard data.count <= 256 * 1024 * 1024 else { throw BridgeError("当前版本单文件发送上限为 256 MB") }
        let local = scratch.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: local) }
        try data.write(to: local, options: .atomic)
        _ = try await run(["file", "send", local.path, path], timeout: 120)
    }
    public func readClipboard() async throws -> String { throw BridgeError("HDC 不提供公开的系统剪贴板读取接口，需手机伴侣应用配合") }
    public func writeClipboard(_ text: String) async throws { throw BridgeError("HDC 仅支持将文字输入当前焦点，不等同于写入手机剪贴板") }
    public func disconnect() async { _ = try? await shell(["rm", "-f", remoteScreenshot]) }
}
