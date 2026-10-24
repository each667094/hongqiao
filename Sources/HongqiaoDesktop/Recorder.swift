import AppKit
import AVFoundation
import HongqiaoCore

@MainActor final class MirrorRecorder {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var start: Date?
    private var lastTime: CMTime = .invalid
    private(set) var frameCount = 0
    private var width = 0
    private var height = 0
    var active: Bool { writer != nil }
    func begin(at url: URL, width: Int, height: Int) throws {
        guard writer == nil, width > 0, height > 0 else { throw BridgeError("请先取得有效画面") }
        self.width = width / 2 * 2; self.height = height / 2 * 2
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: self.width, AVVideoHeightKey: self.height])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: self.width, kCVPixelBufferHeightKey as String: self.height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw BridgeError("视频编码器不可用") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? BridgeError("无法创建录屏文件") }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer; self.input = input; self.adaptor = adaptor; self.start = Date(); frameCount = 0; lastTime = .invalid
    }
    func append(_ image: NSImage) {
        guard let writer, writer.status == .writing, let input, input.isReadyForMoreMediaData, let adaptor, let start,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixel)
        guard let pixel else { return }
        CVPixelBufferLockBaseAddress(pixel, [])
        if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
            ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let ratio = min(CGFloat(width) / CGFloat(cgImage.width), CGFloat(height) / CGFloat(cgImage.height))
            let w = CGFloat(cgImage.width) * ratio, h = CGFloat(cgImage.height) * ratio
            ctx.draw(cgImage, in: CGRect(x: (CGFloat(width) - w) / 2, y: (CGFloat(height) - h) / 2, width: w, height: h))
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var time = CMTime(seconds: Date().timeIntervalSince(start), preferredTimescale: 600)
        if lastTime.isValid && CMTimeCompare(time, lastTime) <= 0 { time = CMTimeAdd(lastTime, CMTime(value: 1, timescale: 600)) }
        if adaptor.append(pixel, withPresentationTime: time) { frameCount += 1; lastTime = time }
    }
    func finish() async throws {
        guard let writer, let input else { return }
        self.writer = nil; self.input = nil; self.adaptor = nil; self.start = nil
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? BridgeError("录屏未完成") }
    }
}
