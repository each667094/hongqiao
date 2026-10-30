import Foundation
import ImageIO

public actor HDCTransport: BridgeTransport {
    public let executable: URL
    public let target: String
    private let scratch: URL
    private let remoteScreenshot: String
    private let controlGate = AsyncCommandGate()
    private var closed = false
    private var capturePaused = false
    private var sourceWidth = 0, sourceHeight = 0
    private var geometryUpdatedAt = Date.distantPast
    private var frameBuffer: LatestFrameBuffer?
    private var producers: [Task<Void, Never>] = []
    public nonisolated let capabilities = Capabilities(clipboardRead: false, clipboardWrite: false, photoLibrary: false)
    public init(executable: URL, target: String) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("内置连接组件不可用，请重新安装完整的鸿桥") }
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
    public static func scan(executable: URL) async throws -> DeviceScan {
        let result = try await ProcessRunner.run(executable, ["list", "targets"])
        guard result.status == 0 else { throw BridgeError("未能启动连接服务，请重新打开鸿桥后重试。") }
        return try DeviceScan.parse(result.output)
    }
    public static func discover(executable: URL) async throws -> [String] { try await scan(executable: executable).targets }
    public static func connectWireless(executable: URL, endpoint: String) async throws {
        let parts = endpoint.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw BridgeError("请检查手机 IP 地址与端口") }
        _ = try WirelessAddress.endpoint(host: String(parts[0]), port: String(parts[1]))
        let r = try await ProcessRunner.run(executable, ["tconn", endpoint])
        guard r.status == 0, !r.output.lowercased().contains("fail") else { throw BridgeError("无线连接未成功。请检查两台设备是否在同一 Wi-Fi、手机当前地址与端口是否正确，并在手机确认授权。") }
    }
    public func connect() async throws -> Device {
        let ids = try await Self.discover(executable: executable)
        guard ids.contains(target) else { throw BridgeError("设备未连接或未授权，请先在手机确认调试授权") }
        let model = try await shell(["param", "get", "const.product.model"])
        let system = try await shell(["param", "get", "const.product.software.version"])
        return Device(id: target, name: model.trimmingCharacters(in: .whitespacesAndNewlines), system: system.trimmingCharacters(in: .whitespacesAndNewlines), width: 0, height: 0)
    }
    public func capture() async throws -> Frame {
        if let frameBuffer { return try await frameBuffer.next() }
        guard !closed else { throw CancellationError() }
        let first = try await captureSingle(slot: 4, native: true)
        let buffer = LatestFrameBuffer(); frameBuffer = buffer
        for slot in 0..<(target.contains(":") ? 2 : 4) {
            producers.append(Task { [weak self] in
                // Avoid bursts of near-simultaneous captures from every worker.
                try? await Task.sleep(nanoseconds: UInt64(slot) * 120_000_000)
                var failures = 0
                while !Task.isCancelled {
                    guard let self else { return }
                    if await self.closed { return }
                    if await self.capturePaused { try? await Task.sleep(nanoseconds: 100_000_000); continue }
                    do {
                        let frame = try await self.captureSingle(slot: slot, native: false)
                        guard !Task.isCancelled else { return }
                        if await self.capturePaused { continue }
                        await buffer.offer(frame); failures = 0
                    } catch {
                        if Task.isCancelled { return }
                        failures += 1
                        if failures >= 3 { await buffer.report(error); failures = 0 }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
            })
        }
        return first
    }
    public func setCapturePaused(_ paused: Bool) async {
        capturePaused = paused
        // A capture started before pausing must not reappear after resuming.
        await frameBuffer?.discard(before: Date())
    }
    private func captureSingle(slot: Int, native: Bool) async throws -> Frame {
        let start = Date()
        let remote = remoteScreenshot.replacingOccurrences(of: ".jpeg", with: "-\(slot).jpeg")
        let size = PreviewSize.dimensions(width: sourceWidth, height: sourceHeight)
        let arguments = ["snapshot_display", "-f", remote] + (native || size.0 == 0 ? [] : ["-w", "\(size.0)", "-h", "\(size.1)"])
        let output = try await shell(arguments)
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        let regex = try NSRegularExpression(pattern: #"width:\s*(\d+),\s*height:\s*(\d+)"#)
        let ns = output as NSString
        let metadata = regex.firstMatch(in: output, range: NSRange(location: 0, length: ns.length))
        let width = metadata.flatMap { Int(ns.substring(with: $0.range(at: 1))) } ?? sourceWidth
        let height = metadata.flatMap { Int(ns.substring(with: $0.range(at: 2))) } ?? sourceHeight
        if width > 0 && height > 0 && start >= geometryUpdatedAt { sourceWidth = width; sourceHeight = height; geometryUpdatedAt = start }
        let local = scratch.appendingPathComponent("frame-\(slot).jpeg")
        // Never display a previous successful file when a new capture fails.
        try? FileManager.default.removeItem(at: local)
        guard !output.lowercased().contains("error:"), !output.contains("Permission denied") else { throw BridgeError("手机截图未完成：\(output.prefix(300))") }
        _ = try await run(["file", "recv", remote, local.path])
        let data = try Data(contentsOf: local)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw BridgeError("手机未返回有效画面") }
        if native, width == 0, let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            sourceWidth = info[kCGImagePropertyPixelWidth] as? Int ?? 0
            sourceHeight = info[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        // Rotation: discard a frame sized for the old orientation. Next capture uses the new ratio.
        if !native, (size.0 > size.1) != (width > height) { throw BridgeError("手机方向已变化，正在更新画面尺寸") }
        return Frame(data: data, elapsedMS: Date().timeIntervalSince(start) * 1000, sourceWidth: width > 0 ? width : sourceWidth, sourceHeight: height > 0 ? height : sourceHeight, capturedAt: start)
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
        await controlGate.acquire()
        do {
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            let result = try await ProcessRunner.run(executable, ["-t", target, "shell", Shell.command(args)])
            do { try ControlValidation.validate(status: result.status, output: result.output) }
            catch let failure as ControlFailure {
                if e.kind == "text" { throw ControlFailure(failure.kind, "设备文字输入未完成，请检查输入框焦点与手机授权（不保留命令返回正文）。") }
                throw failure
            }
            await controlGate.release()
        } catch {
            await controlGate.release()
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
    public func disconnect() async {
        closed = true
        for task in producers { task.cancel() }
        await frameBuffer?.finish()
        for task in producers { await task.value }
        producers.removeAll(); frameBuffer = nil
        let paths = (0..<5).map { remoteScreenshot.replacingOccurrences(of: ".jpeg", with: "-\($0).jpeg") }
        _ = try? await shell(["rm", "-f"] + paths)
    }
}
