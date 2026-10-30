import Foundation

public enum ControlFailureKind: String, Codable { case permission, disconnected, busy, unsupported, operation }
public struct ControlFailure: LocalizedError {
    public let kind: ControlFailureKind
    public let detail: String
    public init(_ kind: ControlFailureKind, _ detail: String) { self.kind = kind; self.detail = detail }
    public var errorDescription: String? { detail }
    public var shouldDisableControl: Bool { kind == .permission || kind == .disconnected }
}
public enum ControlValidation {
    public static func validate(status: Int32, output: String) throws {
        // UITest 7 returns exactly "No Error" for successful operations.
        // Remove only exact success lines; a substring match on "error" rejects valid responses.
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let diagnostic = lines.filter { !["no error", "no error.", "success", "success.", "ok"].contains($0.lowercased()) }.joined(separator: "\n")
        let lower = diagnostic.lowercased()
        if ["permission denied", "not permitted", "unauthorized", "auth failed", "permission is denied"].contains(where: lower.contains) {
            throw ControlFailure(.permission, "手机未允许这次控制，请检查调试授权与锁屏状态。\n" + String(diagnostic.prefix(500)))
        }
        if ["device not found", "target not found", "device offline", "connect server failed", "no connected target"].contains(where: lower.contains) {
            throw ControlFailure(.disconnected, "手机连接已断开，请重新连接。")
        }
        if ["already running", "another uitest", "busy", "connection to uitest", "initialize ui test", "init uitest"].contains(where: lower.contains) {
            throw ControlFailure(.busy, "手机控制服务正忙，请稍后重试。")
        }
        if ["unknown command", "not supported", "inaccessible or not found", "missing parameter", "usage:"].contains(where: lower.contains) {
            throw ControlFailure(.unsupported, "手机当前系统不支持这项操作。\n" + String(diagnostic.prefix(350)))
        }
        if status != 0 || lower.contains("[fail]") || lower.range(of: #"\b(error|failed|failure)\b"#, options: .regularExpression) != nil {
            throw ControlFailure(.operation, "这次操作未完成。\n" + String(diagnostic.prefix(500)))
        }
    }
}

// Actor methods are reentrant across await, so an explicit FIFO gate is needed.
public actor AsyncCommandGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    public init() {}
    public func acquire() async {
        if !occupied { occupied = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    public func release() {
        if waiters.isEmpty { occupied = false } else { waiters.removeFirst().resume() }
    }
}
