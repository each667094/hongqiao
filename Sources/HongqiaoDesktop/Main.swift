import SwiftUI
import AppKit
import AVFoundation
import CryptoKit
import HongqiaoCore
import HongqiaoPeer

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task { @MainActor in await model.disconnect(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct HongqiaoApplication: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("鸿桥 · 设备工作台") {
            RootView(model: model).onAppear { delegate.model = model; NSApp.activate(ignoringOtherApps: true) }
        }.defaultSize(width: 1240, height: 840).windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandMenu("设备") {
                    Button("开始本地体验") { Task { await model.startDemo() } }.keyboardShortcut("d", modifiers: [.command, .shift])
                    Button("断开连接") { Task { await model.disconnect() } }.disabled(!model.connected)
                    Divider()
                    Button("保存截图…") { model.saveScreenshot() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.image == nil)
                    Button("连接与诊断") { model.destination = .settings }
                }
            }
    }
}
@main enum Entry {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "--render-preview"), arguments.count > i + 1 {
            _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
            do { try renderPreviews(at: URL(fileURLWithPath: arguments[i + 1])); exit(0) } catch { fputs("\(error)\n", stderr); exit(1) }
        }
        if arguments.contains("--verify") {
            _ = NSApplication.shared; NSApp.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await verify(); exit(0) } catch { fputs("Verification failed: \(error)\n", stderr); exit(1) }
            }
            RunLoop.main.run(); return
        }
        HongqiaoApplication.main()
    }
    @MainActor static func renderPreviews(at directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel()
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("01-工作台.png"))
        model.device = Device(id: "demo", name: "本地演示设备", system: "本机模拟 · 非 HarmonyOS 真机", width: 390, height: 780, isDemo: true)
        model.image = DemoArtwork.image(); model.destination = .mirror; model.fps = 2; model.latency = 24; model.frames = 36
        model.notice = "本地演示已连接；所有手机内容均在这台 Mac 内模拟。"
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("02-实时投屏.png"))
        model.destination = .gallery
        model.files = (0..<4).map { RemoteFile(name: "示例相片-\($0 + 1).jpg", size: 18400) }
        for i in 0..<4 { model.photos["示例相片-\(i + 1).jpg"] = DemoArtwork.album(i) }
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("03-相册.png"))
        model.destination = .settings
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("04-连接与诊断.png"))
        let icon = NSImage(size: .init(width: 1024, height: 1024)); icon.lockFocus()
        NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.15, blue: 0.23, alpha: 1), NSColor(srgbRed: 0.08, green: 0.42, blue: 0.43, alpha: 1)])!.draw(in: NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 210, yRadius: 210), angle: 40)
        NSColor(srgbRed: 0.41, green: 0.94, blue: 0.81, alpha: 1).setStroke()
        let bridge = NSBezierPath(); bridge.lineWidth = 64; bridge.lineCapStyle = .round
        bridge.move(to: .init(x: 230, y: 300)); bridge.line(to: .init(x: 230, y: 650)); bridge.curve(to: .init(x: 794, y: 650), controlPoint1: .init(x: 380, y: 400), controlPoint2: .init(x: 644, y: 400)); bridge.line(to: .init(x: 794, y: 300)); bridge.stroke()
        let base = NSBezierPath(); base.lineWidth = 48; base.lineCapStyle = .round; base.move(to: .init(x: 230, y: 330)); base.line(to: .init(x: 794, y: 330)); base.stroke()
        icon.unlockFocus()
        let png = NSBitmapImageRep(data: icon.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("AppIcon.png"))
    }
    @MainActor static func snapshot<V: View>(_ view: V, to url: URL) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 1240, height: 840)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw BridgeError("无法创建界面渲染") }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw BridgeError("无法导出界面") }
        try data.write(to: url)
    }
    @MainActor static func verify() async throws {
        var checks: [String] = []
        func check(_ passed: Bool, _ label: String) throws { guard passed else { throw BridgeError(label) }; checks.append(label) }
        let server = DemoServer(); try await server.start(); defer { server.stop() }
        let peer = try PeerTransport(baseURL: server.baseURL, token: server.token)
        let info = try await peer.connect()
        try check(info.isDemo && info.width == 390, "演示设备识别正确且明确标注")
        let frame1 = try await peer.capture()
        let rep = NSBitmapImageRep(data: frame1.data)
        try check(rep != nil && rep!.pixelsWide == 390 && rep!.pixelsHigh == 780, "截图字节可解码且坐标尺寸一致")
        try await peer.control(ControlEvent("click", x: 50, y: 330))
        try check(server.interactions == 1 && server.page != "home", "点击经 HTTP 到达模拟设备并改变页面")
        try await peer.control(ControlEvent("text", text: "中文输入验证 ' $() ; &\n第二行"))
        let frame2 = try await peer.capture()
        try check(SHA256.hash(data: frame1.data) != SHA256.hash(data: frame2.data), "中文输入改变远端画面")
        try await peer.control(ControlEvent("swipe", x: 100, y: 600, endX: 100, endY: 200))
        try await peer.control(ControlEvent("longClick", x: 50, y: 300))
        try await peer.control(ControlEvent("back"))
        try check(server.page == "home" && server.interactions == 5, "滑动、长按、返回指令生效")
        let payload = Data((0..<1_048_576).map { UInt8($0 % 251) })
        try await peer.send(data: payload, path: "/传输验证 中文.bin")
        let received = try await peer.receive(path: "/传输验证 中文.bin")
        try check(SHA256.hash(data: payload) == SHA256.hash(data: received), "1 MB 中文文件名双向传输 SHA-256 一致")
        do { try await peer.send(data: payload, path: "/传输验证 中文.bin"); throw BridgeError("同名覆盖未被阻止") } catch let e as BridgeError { try check(e.message.contains("409"), "阻止同名覆盖") }
        try await peer.writeClipboard("双向中文剪贴板\n不写入 Mac 系统剪贴板")
        let clipboard = try await peer.readClipboard()
        try check(clipboard.hasPrefix("双向中文"), "伴侣剪贴板双向往返")
        let files = try await peer.files(at: "/")
        try check(files.filter(\.isImage).count == 4, "相册文件列表可读取")
        let photo = try await peer.receive(path: "/示例相片-1.jpg")
        try check(NSImage(data: photo) != nil, "相册原文件可解码")
        let unauthorized = try PeerTransport(baseURL: server.baseURL, token: "invalid")
        do { _ = try await unauthorized.connect(); throw BridgeError("无效令牌未被阻止") } catch let e as BridgeError { try check(e.message.contains("401"), "无效会话令牌被拒绝") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("hongqiao-verification-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }
        let recorder = MirrorRecorder(); try recorder.begin(at: output, width: 390, height: 780)
        for _ in 0..<4 { recorder.append(NSImage(data: frame2.data)!); try await Task.sleep(nanoseconds: 150_000_000) }
        try await recorder.finish()
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        try check(tracks.count == 1 && duration.seconds > 0 && recorder.frameCount >= 3, "录屏生成有效 H.264 MOV 视频轨与时长")
        // Verify UI session ownership and explicit action gates, without any phone or pasteboard access.
        let model = AppModel()
        await model.startDemo()
        try await Task.sleep(nanoseconds: 600_000_000)
        try check(model.connected && model.isDemo && model.frames > 0 && !model.controlEnabled, "原生状态模型完成本地连接并默认关闭控制")
        model.controlEnabled = true
        model.inputText = "状态模型输入测试"
        await model.sendInput()
        model.paused = true
        let pausedFrames = model.frames
        try await Task.sleep(nanoseconds: 600_000_000)
        try check(model.frames == pausedFrames, "暂停后不再更新画面")
        await model.disconnect()
        try check(!model.connected && model.image == nil && !model.controlEnabled, "断开清理画面、控制与会话")
        await model.startDemo()
        try await Task.sleep(nanoseconds: 200_000_000)
        try check(model.connected && model.isDemo && model.error == nil, "重新启动独立会话可用")
        await model.disconnect()
        await peer.disconnect()
        let report: [String: Any] = ["status": "passed", "checks": checks, "phoneUsed": false, "realDeviceVerified": false, "timestamp": ISO8601DateFormatter().string(from: Date())]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
