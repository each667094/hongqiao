import SwiftUI
import AppKit
import AVFoundation
import CryptoKit
import HongqiaoCore

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
                    Button("连接手机") { Task { await model.connectPhone() } }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(model.connecting || !model.componentReady)
                    Button("首次连接帮助") { model.showConnectionGuide = true }
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
            do {
                let bundleIndex = arguments.firstIndex(of: "--bundle-root")
                let bundle = bundleIndex.flatMap { arguments.count > $0 + 1 ? URL(fileURLWithPath: arguments[$0 + 1]) : nil } ?? Bundle.main.bundleURL
                try renderPreviews(at: URL(fileURLWithPath: arguments[i + 1]), bundleURL: bundle); exit(0)
            } catch { fputs("\(error)\n", stderr); exit(1) }
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
    @MainActor static func renderPreviews(at directory: URL, bundleURL: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(bundleURL: bundleURL)
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("01-工作台.png"))
        model.destination = .settings
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("02-数据线连接.png"))
        model.connectionMethod = .wireless; model.resetConnectionChoices()
        try snapshot(RootView(model: model), to: directory.appendingPathComponent("03-无线连接.png"))
        try snapshot(ConnectionGuideView(), to: directory.appendingPathComponent("04-首次连接帮助.png"), size: NSSize(width: 684, height: 700))
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
    @MainActor static func snapshot<V: View>(_ view: V, to url: URL, size: NSSize = NSSize(width: 1240, height: 840)) throws {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw BridgeError("无法创建界面渲染") }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw BridgeError("无法导出界面") }
        try data.write(to: url)
    }
    @MainActor static func verify() async throws {
        var checks: [String] = []
        func check(_ passed: Bool, _ label: String) throws { guard passed else { throw BridgeError(label) }; checks.append(label) }
        let executable = try BundledHDC.resolve()
        try check(FileManager.default.isExecutableFile(atPath: executable.path), "应用内置可执行连接工具及校验清单")
        let result = try await ProcessRunner.run(executable, ["-v"])
        try check(result.status == 0 && result.output.contains("Ver:"), "内置连接工具与 USB 动态库可正常加载，仅执行版本查询")
        let model = AppModel()
        try check(model.componentReady && !model.connected && !model.connecting && model.image == nil, "应用启动仅检查内置组件，不发现或连接手机")
        try check(!model.controlEnabled && model.devices.isEmpty, "未连接时关闭控制且不生成设备")
        let report: [String: Any] = ["status": "passed", "version": "0.2.0", "checks": checks, "bundledToolVersion": result.output.trimmingCharacters(in: .whitespacesAndNewlines), "phoneUsed": false, "realDeviceVerified": false, "timestamp": ISO8601DateFormatter().string(from: Date())]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }
}
