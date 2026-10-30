import Foundation
import HongqiaoCore

/// Opt-in, user-authorized device check. Default offline checks never invoke this path.
enum LiveChecks {
    static func run(target: String) async throws {
        let executable = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/HDC/hdc")
        let transport = try HDCTransport(executable: executable, target: target)
        do {
            let device = try await transport.connect()
            // Return to launcher. Further taps are deliberately on its empty wallpaper, not app icons.
            try await transport.control(ControlEvent("home"))
            let first = try await transport.capture()
            guard let width = first.sourceWidth, let height = first.sourceHeight, width > 0, height > 0 else { throw BridgeError("未返回手机原始坐标尺寸") }
            let start = Date(); var count = 0; var latencies: [Double] = []
            for _ in 0..<24 {
                let frame = try await transport.capture()
                guard !frame.data.isEmpty else { throw BridgeError("空画面") }
                count += 1; latencies.append(frame.elapsedMS)
            }
            let elapsed = Date().timeIntervalSince(start)
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<3 {
                    group.addTask { try await transport.control(ControlEvent("click", x: width / 2, y: height * 45 / 100)) }
                }
                try await group.waitForAll()
            }
            try await transport.control(ControlEvent("home"))
            let pausedAt = Date()
            await transport.setCapturePaused(true)
            try await Task.sleep(nanoseconds: 700_000_000)
            await transport.setCapturePaused(false)
            let resumed = try await transport.capture()
            guard resumed.capturedAt > pausedAt else { throw BridgeError("恢复后返回旧画面") }
            await transport.disconnect()
            let report: [String: Any] = ["status":"passed","version":"0.2.1","phoneUsed":true,"realDeviceVerified":true,"system":device.system,"originalSize":[width,height],"previewFrames":count,"sampleSeconds":elapsed,"measuredFPS":Double(count)/elapsed,"meanCaptureAndTransferMS":latencies.reduce(0,+)/Double(latencies.count),"controlsCompleted":5,"controlResult":"No Error accepted, queued wallpaper taps and Home completed","pauseResume":"fresh frame verified","timestamp":ISO8601DateFormatter().string(from:Date())]
            print(String(decoding:try JSONSerialization.data(withJSONObject: report, options:[.prettyPrinted,.sortedKeys]),as:UTF8.self))
        } catch { await transport.disconnect(); throw error }
    }
}
