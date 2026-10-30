import Foundation

/// Single-slot mailbox: late frames and frames rendered obsolete by newer captures are dropped.
public actor LatestFrameBuffer {
    private var latest: Frame?
    private var waiter: (UUID, CheckedContinuation<Frame, Error>)?
    private var failure: Error?
    private var transientFailure: Error?
    private var newest = Date.distantPast
    public init() {}
    public func offer(_ frame: Frame) {
        guard failure == nil, frame.capturedAt >= newest else { return }
        transientFailure = nil
        newest = frame.capturedAt
        if let waiter { self.waiter = nil; waiter.1.resume(returning: frame) }
        else { latest = frame }
    }
    public func next() async throws -> Frame {
        try Task.checkCancellation()
        if let latest { self.latest = nil; return latest }
        if let failure { throw failure }
        if let transientFailure { self.transientFailure = nil; throw transientFailure }
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                guard waiter == nil else { continuation.resume(throwing: BridgeError("画面读取已在进行中")); return }
                waiter = (id, continuation)
            }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    private func cancel(_ id: UUID) {
        guard let waiter, waiter.0 == id else { return }
        self.waiter = nil; waiter.1.resume(throwing: CancellationError())
    }
    public func discard(before date: Date? = nil) {
        latest = nil
        transientFailure = nil
        if let date { newest = max(newest, date) }
    }
    public func report(_ error: Error) {
        guard failure == nil else { return }
        if let waiter { self.waiter = nil; waiter.1.resume(throwing: error) }
        else { transientFailure = error }
    }
    public func finish(_ error: Error = CancellationError()) {
        failure = error; latest = nil; waiter?.1.resume(throwing: error); waiter = nil
    }
}
public enum PreviewSize {
    public static func dimensions(width: Int, height: Int, shortSide: Int = 720) -> (Int, Int) {
        guard width > 0, height > 0 else { return (width, height) }
        let scale = min(1, Double(shortSide) / Double(min(width, height)))
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }
}
public struct FrameRateMeter {
    private var moments: [TimeInterval] = []
    public init() {}
    public mutating func record(at time: TimeInterval) -> Double {
        moments.append(time)
        if moments.count > 16 { moments.removeFirst() }
        guard let first = moments.first, moments.count > 1, time > first else { return 0 }
        return Double(moments.count - 1) / (time - first)
    }
}
