import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HongqiaoCore

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
        case .settings: return "按提示连接手机，查看连接状态。"
        }
    }
}
enum ConnectionMethod: String, CaseIterable, Identifiable {
    case usb = "数据线连接", wireless = "无线连接"
    var id: String { rawValue }
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
    @Published var connectionMethod: ConnectionMethod = .usb
    @Published var connectionTitle = "准备连接手机"
    @Published var connectionDetail = "用数据线连接手机，开启 USB 调试，并在手机上确认允许连接。"
    @Published var showConnectionGuide = false
    let hdcExecutable: URL?
    let componentStatus: String
    var componentReady: Bool { hdcExecutable != nil }
    @Published var devices: [String] = []
    @Published var selectedTarget = ""
    @Published var wirelessHost = ""
    @Published var wirelessPort = ""
    @Published var error: String?
    @Published var notice = "用数据线连接手机后，点击“连接手机”。"
    @Published var logs: [String] = []
    @Published var transfers: [String] = []
    @Published var frameInterval = 0.5
    private var transport: (any BridgeTransport)?
    private var captureTask: Task<Void, Never>?
    private var generation = UUID()
    private var fileGeneration = UUID()
    private let recorder = MirrorRecorder()
    var connected: Bool { device != nil }
    var canReadClipboard: Bool { transport?.capabilities.clipboardRead ?? false }
    var photoFiles: [RemoteFile] { files.filter { $0.isImage && !$0.directory } }
    func log(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.insert("\(time)  \(text)", at: 0); if logs.count > 150 { logs.removeLast() }
    }
    func report(_ e: Error) { error = e.localizedDescription; log("失败：\(e.localizedDescription.prefix(350))") }
    init(bundleURL: URL = Bundle.main.bundleURL) {
        do {
            hdcExecutable = try BundledHDC.resolve(in: bundleURL)
            componentStatus = "连接组件已内置 · 无需下载安装"
        } catch {
            hdcExecutable = nil
            componentStatus = error.localizedDescription
        }
    }
    func resetConnectionChoices() {
        guard !connecting else { return }
        devices = []; selectedTarget = ""
        connectionTitle = "准备连接手机"
        connectionDetail = connectionMethod == .usb ? "用数据线连接手机，开启 USB 调试，并在手机上确认允许连接。" : "将手机与 Mac 接入同一 Wi-Fi，填写手机无线调试页面显示的地址与端口。"
    }
    func connectPhone() async {
        guard !connecting, !busy else { return }
        guard let executable = hdcExecutable else { error = componentStatus; return }
        connecting = true; defer { connecting = false }
        error = nil; devices = []; selectedTarget = ""
        connectionTitle = "正在查找手机…"
        connectionDetail = "请保持手机解锁，并确认手机上的连接授权提示。"
        do {
            var endpoint: String?
            if connectionMethod == .wireless {
                endpoint = try WirelessAddress.endpoint(host: wirelessHost, port: wirelessPort)
                try await HDCTransport.connectWireless(executable: executable, endpoint: endpoint!)
            }
            let all = try await HDCTransport.scan(executable: executable)
            let eligible = endpoint.map { address in all.targets.filter { $0 == address } } ?? all.targets.filter { !$0.contains(":") }
            let scan = DeviceScan(targets: eligible, needsAuthorization: all.needsAuthorization)
            switch ConnectionDecision.plan(scan) {
            case .waitForDevice:
                connectionTitle = connectionMethod == .usb ? "还没有发现手机" : "无线连接尚未就绪"
                connectionDetail = connectionMethod == .usb ? "检查数据线是否支持传输数据，确认手机已开启 USB 调试，然后点击重试。" : "确认两台设备在同一 Wi-Fi、无线调试已开启，并核对手机当前显示的地址与端口。"
                notice = connectionDetail
            case .waitForAuthorization:
                connectionTitle = "请在手机上允许连接"
                connectionDetail = "保持手机解锁，在弹出的调试授权窗口中点击允许，然后再次点击“连接手机”。"
                notice = connectionDetail
            case .connect(let target):
                selectedTarget = target
                try await connectTarget(target, executable: executable)
            case .choose(let targets):
                devices = targets; selectedTarget = targets[0]
                connectionTitle = "发现多台设备，请选择手机"
                connectionDetail = "为避免连接到其他设备，请选择要连接的手机，再点击“连接选中手机”。"
                notice = connectionDetail
            }
        } catch {
            connectionTitle = "暂时无法连接"
            connectionDetail = error.localizedDescription
            report(error)
        }
    }
    func connectSelectedPhone() async {
        guard !connecting, !busy, let executable = hdcExecutable, devices.contains(selectedTarget) else { return }
        connecting = true; defer { connecting = false }
        do { try await connectTarget(selectedTarget, executable: executable) }
        catch { connectionTitle = "暂时无法连接"; connectionDetail = error.localizedDescription; report(error) }
    }
    private func connectTarget(_ target: String, executable: URL) async throws {
        await disconnect()
        connectionTitle = "正在连接手机…"
        let bridge = try HDCTransport(executable: executable, target: target)
        try await attach(bridge)
        connectionTitle = "手机已连接"
        connectionDetail = "可以开始投屏；需要操作手机时，在投屏页开启反向控制。"
        notice = connectionDetail; devices = []; selectedTarget = ""
        log("手机连接完成；控制默认关闭")
        destination = .mirror
    }
    private func attach(_ bridge: any BridgeTransport) async throws {
        let info = try await bridge.connect(); device = info; transport = bridge
        generation = UUID(); frames = 0; paused = false; controlEnabled = false; currentPath = "/data/local/tmp"; files = []; photos = [:]
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
        await oldTask?.value
        if recording { await stopRecording() }
        await old?.disconnect()
        connectionTitle = "准备连接手机"
        connectionDetail = "用数据线连接手机后，点击“连接手机”。"
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
                let limit = 256 * 1024 * 1024
                guard attributes.isDirectory == false, attributes.isSymbolicLink != true, (attributes.fileSize ?? Int.max) <= limit else { throw BridgeError("仅支持普通文件，单文件上限为 256 MB") }
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
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "鸿桥-截图.png"
        if panel.runModal() == .OK, let url = panel.url { do { try png.write(to: url, options: .atomic); log("截图已保存") } catch { report(error) } }
    }
    func startRecording() {
        guard let device, image != nil else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.quickTimeMovie]; panel.nameFieldStringValue = "鸿桥-录屏.mov"
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
        let text = "鸿桥 0.2.0\n连接状态：\(connected ? "已连接" : "未连接")\n画面：\(device?.width ?? 0)×\(device?.height ?? 0)\n会话帧数：\(frames)\n诊断不包含输入文字、剪贴板正文或画面。\n\n" + logs.joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8); notice = "诊断已保存到你选择的位置" } catch { report(error) }
    }
    func shutdown() { captureTask?.cancel() }
}
