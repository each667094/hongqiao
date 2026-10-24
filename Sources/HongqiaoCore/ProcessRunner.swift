import Foundation

public struct ProcessResult { public let output: String; public let status: Int32 }
public enum ProcessRunner {
    public static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 12) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = output
                var data = Data()
                let dataLock = NSLock()
                output.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    dataLock.lock(); if data.count < 8 * 1024 * 1024 { data.append(chunk) }; dataLock.unlock()
                }
                do { try process.run() } catch {
                    output.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error); return
                }
                let completed = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in completed.signal() }
                // terminationHandler also runs when attached after a very short process exits.
                if !process.isRunning { completed.signal() }
                let timedOut = completed.wait(timeout: .now() + timeout) == .timedOut
                if timedOut {
                    process.terminate()
                    if completed.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
                }
                output.fileHandleForReading.readabilityHandler = nil
                let tail = output.fileHandleForReading.readDataToEndOfFile()
                dataLock.lock(); data.append(tail); let text = String(decoding: data, as: UTF8.self); dataLock.unlock()
                if timedOut { continuation.resume(throwing: BridgeError("命令超时（\(Int(timeout)) 秒），进程已终止")) }
                else { continuation.resume(returning: ProcessResult(output: text, status: process.terminationStatus)) }
            }
        }
    }
}
