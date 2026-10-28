import Foundation
import CryptoKit

public struct DeviceScan: Equatable {
    public var targets: [String]
    public var needsAuthorization: Bool
    public init(targets: [String], needsAuthorization: Bool = false) {
        self.targets = targets; self.needsAuthorization = needsAuthorization
    }
    public static func parse(_ output: String) throws -> DeviceScan {
        var targets: [String] = [], needsAuthorization = false
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if lower.contains("unauthor") || lower.contains("未授权") { needsAuthorization = true; continue }
            if lower.contains("[fail]") || lower.contains("error:") || lower.contains("version mismatch") { throw BridgeError("连接服务暂不可用，请关闭其他调试任务后重试；仍失败时可导出诊断。") }
            if line.isEmpty || line.hasPrefix("[") || lower.contains("server") || lower.contains("daemon") { continue }
            let columns = line.split(whereSeparator: \.isWhitespace)
            guard let first = columns.first, first.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]*$", options: .regularExpression) != nil else { continue }
            guard columns.count == 1 || columns.dropFirst().contains(where: { ["connected", "online"].contains($0.lowercased()) }) else { continue }
            let target = String(first)
            if !targets.contains(target) { targets.append(target) }
        }
        return DeviceScan(targets: targets, needsAuthorization: needsAuthorization)
    }
}
public enum ConnectionDecision: Equatable {
    case waitForDevice
    case waitForAuthorization
    case connect(String)
    case choose([String])
    public static func plan(_ scan: DeviceScan) -> ConnectionDecision {
        if scan.needsAuthorization {
            return scan.targets.isEmpty ? .waitForAuthorization : .choose(scan.targets)
        }
        if scan.targets.count == 1 { return .connect(scan.targets[0]) }
        if scan.targets.count > 1 { return .choose(scan.targets) }
        return scan.needsAuthorization ? .waitForAuthorization : .waitForDevice
    }
}
public enum WirelessAddress {
    public static func endpoint(host: String, port: String) throws -> String {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0).map { (0...255).contains($0) } == true }),
              !port.isEmpty, port.allSatisfy(\.isNumber), let number = Int(port), (1...65535).contains(number) else {
            throw BridgeError("请填写手机无线调试页面中的 IP 地址和端口。IP 为四组数字，端口为 1–65535 的数字。")
        }
        return "\(host):\(number)"
    }
}
public enum BundledHDC {
    public static func directory(in bundleURL: URL = Bundle.main.bundleURL) -> URL {
        bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
    }
    public static func resolve(in bundleURL: URL = Bundle.main.bundleURL) throws -> URL {
        let directory = directory(in: bundleURL)
        let executable = directory.appendingPathComponent("hdc")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("连接组件不完整。请重新解压并打开完整的“鸿桥.app”，无需另装开发工具。") }
        let manifest = bundleURL.appendingPathComponent("Contents/Resources/HDC/manifest.json")
        guard let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
              let expected = object["bundledSHA256"] as? [String: String], !expected.isEmpty, expected["hdc"] != nil else { throw BridgeError("连接组件缺少校验信息，请重新安装完整的鸿桥。") }
        for (name, checksum) in expected {
            _ = try Shell.safeName(name)
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard checksum == actual else { throw BridgeError("连接组件校验失败，请重新安装完整的鸿桥。") }
        }
        return executable
    }
}
