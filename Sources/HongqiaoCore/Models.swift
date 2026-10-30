import Foundation

public struct BridgeError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct Device: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var system: String
    public var width: Int
    public var height: Int
    public init(id: String, name: String, system: String, width: Int, height: Int) {
        self.id = id; self.name = name; self.system = system; self.width = width; self.height = height
    }
}
public struct RemoteFile: Codable, Identifiable, Equatable {
    public var name: String
    public var size: Int64
    public var directory: Bool
    public var id: String { name }
    public init(name: String, size: Int64, directory: Bool = false) { self.name = name; self.size = size; self.directory = directory }
    public var isImage: Bool { ["jpg", "jpeg", "png", "heic", "webp"].contains((name as NSString).pathExtension.lowercased()) }
}
public struct ControlEvent: Codable, Equatable {
    public var kind: String
    public var x: Int?
    public var y: Int?
    public var endX: Int?
    public var endY: Int?
    public var text: String?
    public init(_ kind: String, x: Int? = nil, y: Int? = nil, endX: Int? = nil, endY: Int? = nil, text: String? = nil) {
        self.kind = kind; self.x = x; self.y = y; self.endX = endX; self.endY = endY; self.text = text
    }
}
public struct Frame: Sendable {
    public let data: Data
    public let elapsedMS: Double
    public let sourceWidth: Int?
    public let sourceHeight: Int?
    public let capturedAt: Date
    public init(data: Data, elapsedMS: Double, sourceWidth: Int? = nil, sourceHeight: Int? = nil, capturedAt: Date = Date()) {
        self.data = data; self.elapsedMS = elapsedMS; self.sourceWidth = sourceWidth; self.sourceHeight = sourceHeight; self.capturedAt = capturedAt
    }
}
public struct Capabilities: Sendable {
    public var clipboardRead: Bool
    public var clipboardWrite: Bool
    public var photoLibrary: Bool
    public init(clipboardRead: Bool, clipboardWrite: Bool, photoLibrary: Bool) {
        self.clipboardRead = clipboardRead; self.clipboardWrite = clipboardWrite; self.photoLibrary = photoLibrary
    }
}
public protocol BridgeTransport: AnyObject {
    var capabilities: Capabilities { get }
    func connect() async throws -> Device
    func capture() async throws -> Frame
    func setCapturePaused(_ paused: Bool) async
    func control(_ event: ControlEvent) async throws
    func files(at path: String) async throws -> [RemoteFile]
    func receive(path: String) async throws -> Data
    func send(data: Data, path: String) async throws
    func readClipboard() async throws -> String
    func writeClipboard(_ text: String) async throws
    func disconnect() async
}
public enum Shell {
    // Every remote argument is quoted. Process is invoked directly, never through a local shell.
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public static func command(_ arguments: [String]) -> String { arguments.map(quote).joined(separator: " ") }
    public static func safeName(_ value: String) throws -> String {
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.contains("\\"), !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }), value.utf8.count <= 240 else { throw BridgeError("文件名不合法") }
        return value
    }
    public static func safeRemotePath(_ value: String) throws -> String {
        guard value.hasPrefix("/"), !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }), !value.split(separator: "/").contains("..") else { throw BridgeError("请输入不含 .. 的绝对路径") }
        return value
    }
}
public enum ScreenGeometry {
    // x/y are view points, top-left origin. Letterboxing is excluded, not stretched.
    public static func map(x: Double, y: Double, viewWidth: Double, viewHeight: Double, screenWidth: Int, screenHeight: Int) -> (Int, Int)? {
        guard viewWidth > 0, viewHeight > 0, screenWidth > 0, screenHeight > 0 else { return nil }
        let scale = min(viewWidth / Double(screenWidth), viewHeight / Double(screenHeight))
        let left = (viewWidth - Double(screenWidth) * scale) / 2
        let top = (viewHeight - Double(screenHeight) * scale) / 2
        guard x >= left, y >= top, x < viewWidth - left, y < viewHeight - top else { return nil }
        return (min(screenWidth - 1, max(0, Int((x - left) / scale))), min(screenHeight - 1, max(0, Int((y - top) / scale))))
    }
}

public extension BridgeTransport { func setCapturePaused(_ paused: Bool) async {} }
