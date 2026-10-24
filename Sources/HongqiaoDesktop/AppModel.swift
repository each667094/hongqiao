import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HongqiaoCore
import HongqiaoPeer

enum Destination: String, CaseIterable, Identifiable {
    case overview = "工作台", mirror = "实时投屏", files = "文件互传", clipboard = "剪贴板", gallery = "相册", camera = "手机摄像头", settings = "连接与诊断"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: return "square.grid.2x2"; case .mirror: return "rectangle.on.rectangle"; case .files: return "folder"; case .clipboard: return "doc.on.clipboard"; case .gallery: return "photo.on.rectangle.angled"; case .camera: return "video"; case .settings: return "slider.horizontal.3" }
    }
    var description: String {
        switch self {
        case .overview: return "把两块屏幕，连接成一个工作流。"
        case .mirror: return "看见手机，也能用鼠标和键盘操作。"
        case .files: return "双向传输，文件留在自己的设备之间。"
        case .clipboard: return "一段文字，在两端继续。"
        case .gallery: return "浏览图片，按需保存原文件。"
        case .camera: return "系统摄像头扩展需要独立签名与手机媒体源。"
        case .settings: return "选择连接方式，查看真实状态与运行记录。"
        }
    }
}
@MainActor final class AppModel: ObservableObject {
    @Published var destination: Destination = .overview
    @Published var device: Device?
    @Published var image: NSImage?
    @Published var busy = false
    @Published var connecting = false
    @Published var controlEnabled = false
    @Published var paused = false
    @Published var recording = false
    @Published var latency = 0.0
    @Published var fps = 0.0
    @Published var frames = 0
    @Published var files: [RemoteFile] = []
    @Published var photos: [String: NSImage] = [:]
    @Published var currentPath = "/"
    @Published var clipboardText = ""
    @Published var inputText = ""
    @Published var hdcPath = UserDefaults.standard.string(forKey: "hdcPath") ?? ""
    @Published var devices: [String] = []
    @Published var selectedTarget = ""
    @Published var wirelessEndpoint = ""
    @Published var error: String?
    @Published var notice = "尚未连接设备。可先体验本地演示。"
    @Published var logs: [String] = []
    @Published var transfers: [String] = []
    @Published var frameInterval = 0.5
    private var transport: (any BridgeTransport)?
    private var peer: DemoServer?
    private var captureTask: Task<Void, Never>?
    private var generation = UUID()
    private var fileGeneration = UUID()
    private let recorder = MirrorRecorder()
    var isDemo: Bool { device?.isDemo ?? false }
    var connected: Bool { device != nil }
    var canReadClipboard: Bool { transport?.capabilities.clipboardRead ?? false }
    var photoFiles: [RemoteFile] { files.filter { $0.isImage && !$0.directory } }
    func log(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("\(time)  \(text)", at: 0); if logs.count > 150 { logs.removeLast() }
    }
    func report(_ e: Error) { error = e.localizedDescription; log("失败：\(e.localizedDescription.prefix(350))") }
    func startDemo() async {
        guard !connecting else { return }; connecting = true; defer { connecting = false }
        await disconnect()
        do {
            let peer = DemoServer(); try await peer.start(); self.peer = peer
            let bridge = try PeerTransport(baseURL: peer.baseURL, token: peer.token)
            try await attach(bridge)
            notice = "本地演示已连接；所有手机内容均在这台 Mac 内模拟。"
            log("本地演示会话启动，仅监听回环地址；未搜索或连接手机")
        } catch { peer?.stop(); peer = nil; report(error) }
    }
    func chooseHDC() {
        let panel = NSOpenPanel(); panel.title = "选择官方 HarmonyOS SDK 的 hdc"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { hdcPath = url.path; UserDefaults.standard.set(hdcPath, forKey: "hdcPath") }
    }
    func discoverDevices() async {
        guard !hdcPath.isEmpty else { error = "请先选择官方 SDK 中的 hdc 工具"; return }
        busy = true; defer { busy = false }
        do { devices = try await HDCTransport.discover(executable: URL(fileURLWithPath: hdcPath)); selectedTarget = devices.first ?? ""; notice = devices.isEmpty ? "未发现已授权设备" : "发现 \(devices.count) 台设备"; log("已执行用户发起的 HDC 设备发现") } catch { report(error) }
    }
    func wirelessConnect() async {
        busy = true; defer { busy = false }
        do { try await HDCTransport.connectWireless(executable: URL(fileURLWithPath: hdcPath), endpoint: wirelessEndpoint); devices = try await HDCTransport.discover(executable: URL(fileURLWithPath: hdcPath)); selectedTarget = devices.first ?? ""; log("无线调试连接命令已完成") } catch { report(error) }
    }
    func connectHDC() async {
        guard !connecting else { return }; connecting = true; defer { connecting = false }
        await disconnect()
        do { let bridge = try HDCTransport(executable: URL(fileURLWithPath: hdcPath), target: selectedTarget); try await attach(bridge); currentPath = "/data/local/tmp"; notice = "HDC 已连接。当前为截图刷新，非视频流；帧率取决于设备。"; log("HDC 会话启动；尚未开启控制"); await refreshFiles() } catch { report(error) }
    }
    private func attach(_ bridge: any BridgeTransport) async throws {
        let info = try await bridge.connect(); device = info; transport = bridge
        generation = UUID(); frames = 0; paused = false; controlEnabled = false; currentPath = info.isDemo ? "/" : "/data/local/tmp"; files = []; photos = [:]
        let id = generation
        captureTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, self.generation == id else { return }
                if self.paused { try? await Task.sleep(nanoseconds: 200_000_000); continue }
                let start = Date()
                do {
                    let frame = try await bridge.capture()
                    guard !Task.isCancelled, self.generation == id else { return }
                    guard let bitmap = NSBitmapImageRep(data: frame.data), let newImage = NSImage(data: frame.data) else { throw BridgeError("返回数据不是有效图像") }
                    self.image = newImage; self.latency = frame.elapsedMS; self.frames += 1
                    self.device?.width = bitmap.pixelsWide; self.device?.height = bitmap.pixelsHigh
                    self.recorder.append(newImage); failures = 0
                    self.fps = 1 / max(self.frameInterval, Date().timeIntervalSince(start))
                } catch {
                    guard !Task.isCancelled, self.generation == id else { return }
                    failures += 1
                    if failures == 1 { self.log("画面读取失败：\(error.localizedDescription.prefix(160))") }
                    if failures >= 3 {
                        self.paused = true; self.controlEnabled = false
                        if self.recording { await self.stopRecording() }
                        self.error = "连续三次无法获取画面。请检查连接与授权，恢复后点击继续。"
                        failures = 0
                    }
                }
                let rest = max(0.03, self.frameInterval - Date().timeIntervalSince(start))
                try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000))
            }
        }
        await refreshFiles()
    }
    func disconnect() async {
        generation = UUID(); let oldTask = captureTask; oldTask?.cancel(); captureTask = nil
        let old = transport; transport = nil; device = nil; image = nil; files = []; photos = [:]; controlEnabled = false; paused = false
        // Cancel local HTTP reads before waiting; finish HDC screenshot work before remote cleanup.
        if old is PeerTransport { await old?.disconnect() }
        peer?.stop(); peer = nil
        await oldTask?.value
        if recording { await stopRecording() }
        if !(old is PeerTransport) { await old?.disconnect() }
        notice = "已断开连接"; log("会话已结束")
    }
    func control(_ event: ControlEvent) async {
        guard controlEnabled, !paused, let transport else { return }
        do { try await transport.control(event); log("操作已提交：\(event.kind)（不记录文字内容）") } catch { controlEnabled = false; report(error) }
    }
    func sendInput() async {
        guard !inputText.isEmpty else { return }
        let value = inputText; await control(ControlEvent("text", text: value))
    }
    func refreshFiles() async {
        guard let transport else { return }
        let id = generation, request = UUID(), path = currentPath
        fileGeneration = request
        do {
            let listing = try await transport.files(at: path)
            guard generation == id, fileGeneration == request else { return }; files = listing; photos = [:]
            for f in listing.filter({ $0.isImage && $0.size <= 16 * 1024 * 1024 }).prefix(40) {
                if Task.isCancelled || generation != id || fileGeneration != request { return }
                if let data = try? await transport.receive(path: (path as NSString).appendingPathComponent(f.name)), let image = NSImage(data: data) {
                    guard generation == id, fileGeneration == request, !Task.isCancelled else { return }
                    photos[f.name] = image
                }
            }
        } catch { guard generation == id, fileGeneration == request else { return }; report(error) }
    }
    func remotePath(_ name: String) -> String { (currentPath as NSString).appendingPathComponent(name) }
    func chooseSendFiles() async {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        if panel.runModal() == .OK { await sendFiles(panel.urls) }
    }
    func sendFiles(_ urls: [URL]) async {
        guard let transport, !busy else { return }
        busy = true; defer { busy = false }
        let id = generation, path = currentPath
        for url in urls {
            do {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey])
                let limit = isDemo ? 16 * 1024 * 1024 : 256 * 1024 * 1024
                guard attributes.isDirectory == false, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= limit else { throw BridgeError("仅支持普通文件；演示上限 16 MB，HDC 上限 256 MB") }
                let name = try Shell.safeName(url.lastPathComponent)
                if files.contains(where: { $0.name == name }) { throw BridgeError("同名文件已存在，请重命名后发送") }
                let data = try Data(contentsOf: url)
                guard id == generation else { return }
                try await transport.send(data: data, path: (path as NSString).appendingPathComponent(name))
                transfers.insert("已发送 · \(name) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))", at: 0)
                log("文件发送完成（\(data.count) 字节）")
            } catch { report(error) }
        }
        if id == generation { await refreshFiles() }
    }
    func saveFile(_ file: RemoteFile) async {
        guard !file.directory, let transport, !busy else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = file.name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; defer { busy = false }
        do {
            let data = try await transport.receive(path: remotePath(file.name)); try data.write(to: url, options: .atomic)
            transfers.insert("已接收 · \(file.name)", at: 0); log("文件保存完成（\(data.count) 字节）")
        } catch { report(error) }
    }
    func readClipboard() async {
        guard let transport else { return }
        let id = generation
        do { let text = try await transport.readClipboard(); guard generation == id else { return }; clipboardText = text; notice = "已读取设备侧文字，尚未覆盖 Mac 剪贴板"; log("已读取伴侣剪贴板（不记录内容）") } catch { if generation == id { report(error) } }
    }
    func writeClipboard() async {
        guard let transport else { return }
        do { try await transport.writeClipboard(clipboardText); notice = "已写入伴侣剪贴板"; log("已写入伴侣剪贴板（不记录内容）") } catch { report(error) }
    }
    func copyToMac() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(clipboardText, forType: .string); notice = "已复制到 Mac 剪贴板" }
    func readMacClipboard() { clipboardText = NSPasteboard.general.string(forType: .string) ?? ""; notice = "已手动读取 Mac 剪贴板" }
    func saveScreenshot() {
        guard let image, let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = isDemo ? "鸿桥-演示截图.png" : "鸿桥-截图.png"
        if panel.runModal() == .OK, let url = panel.url { do { try png.write(to: url, options: .atomic); log("截图已保存") } catch { report(error) } }
    }
    func startRecording() {
        guard let device, image != nil else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.quickTimeMovie]; panel.nameFieldStringValue = isDemo ? "鸿桥-演示录屏.mov" : "鸿桥-录屏.mov"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try recorder.begin(at: url, width: device.width, height: device.height); recording = true; if let image { recorder.append(image) }; log("开始录制当前画面（无音频）")
            } catch { report(error) }
        }
    }
    func stopRecording() async {
        recording = false
        do { try await recorder.finish(); log("录屏文件已完成") } catch { report(error) }
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "鸿桥-诊断.txt"; panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "鸿桥 0.1.0\n模式：\(isDemo ? "本地演示" : connected ? "HDC" : "未连接")\n画面：\(device?.width ?? 0)×\(device?.height ?? 0)\n会话帧数：\(frames)\n无手机真机验证；不包含令牌、输入文字、剪贴板或画面。\n\n" + logs.joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8); notice = "诊断已保存到你选择的位置" } catch { report(error) }
    }
    func shutdown() { captureTask?.cancel(); peer?.stop() }
}
