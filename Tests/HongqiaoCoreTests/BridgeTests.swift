import Foundation
import HongqiaoCore
import CryptoKit

final class BridgeTests {
    var assertions = 0
    var failures: [String] = []
    func XCTAssertTrue(_ value: Bool, _ message: String = "expected true") { assertions += 1; if !value { failures.append(message) } }
    func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "equality assertion") { assertions += 1; if a != b { failures.append(message + ": \(a) != \(b)") } }
    func XCTAssertNil<T>(_ a: T?, _ message: String = "expected nil") { assertions += 1; if a != nil { failures.append(message) } }
    func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: String = "expected error") { assertions += 1; do { _ = try expression(); failures.append(message) } catch {} }
    func XCTAssertLessThan(_ a: Double, _ b: Double) { assertions += 1; if a >= b { failures.append("time limit exceeded") } }
    func XCTFail(_ message: String = "expected failure") { failures.append(message) }

    func testAspectFitMappingRejectsLetterbox() {
        XCTAssertNil(ScreenGeometry.map(x: 5, y: 100, viewWidth: 800, viewHeight: 800, screenWidth: 400, screenHeight: 800))
        let center = ScreenGeometry.map(x: 400, y: 400, viewWidth: 800, viewHeight: 800, screenWidth: 400, screenHeight: 800)
        XCTAssertEqual(center?.0, 200); XCTAssertEqual(center?.1, 400)
        XCTAssertNil(ScreenGeometry.map(x: 600, y: 800, viewWidth: 800, viewHeight: 800, screenWidth: 400, screenHeight: 800))
    }
    func testLandscapeAndBounds() {
        let point = ScreenGeometry.map(x: 499, y: 249, viewWidth: 500, viewHeight: 250, screenWidth: 2000, screenHeight: 1000)
        XCTAssertEqual(point?.0, 1996); XCTAssertEqual(point?.1, 996)
        XCTAssertNil(ScreenGeometry.map(x: 0, y: 0, viewWidth: 0, viewHeight: 0, screenWidth: 1, screenHeight: 1))
    }
    func testShellQuotingSurvivesHostileText() async throws {
        // Validate against an actual shell, without executing the supplied text.
        let text = "中文 ' ; $(touch /tmp/hongqiao-should-not-exist) `whoami` &\n第二行"
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf %s " + Shell.quote(text)])
        XCTAssertEqual(result.output, text)
    }
    func testFileNameAndPathValidation() throws {
        for name in ["", ".", "..", "../secret", "a/b", "a\\b", "a\n.txt", "a\0b"] { XCTAssertThrowsError(try Shell.safeName(name), name) }
        XCTAssertEqual(try Shell.safeName("研究 数据's.csv"), "研究 数据's.csv")
        for path in ["relative", "/data/../secret", "/data/a\n.txt"] { XCTAssertThrowsError(try Shell.safeRemotePath(path)) }
        XCTAssertEqual(try Shell.safeRemotePath("/data/local/tmp/研究 数据.csv"), "/data/local/tmp/研究 数据.csv")
    }
    func testDeviceDiscoveryAndSelection() throws {
        XCTAssertEqual(try DeviceScan.parse("[Empty]\n").targets, [])
        XCTAssertEqual(try DeviceScan.parse("[Info] server started\nUSB123\nUSB123\n").targets, ["USB123"])
        XCTAssertEqual(try DeviceScan.parse("USB123 connected\n192.168.1.8:12345\n").targets, ["USB123", "192.168.1.8:12345"])
        XCTAssertEqual(try DeviceScan.parse("USB123 Unauthorized\n").needsAuthorization, true)
        XCTAssertThrowsError(try DeviceScan.parse("[Fail] server error"))
        XCTAssertEqual(ConnectionDecision.plan(DeviceScan(targets: [])), .waitForDevice)
        XCTAssertEqual(ConnectionDecision.plan(DeviceScan(targets: [], needsAuthorization: true)), .waitForAuthorization)
        XCTAssertEqual(ConnectionDecision.plan(DeviceScan(targets: ["one"])), .connect("one"))
        XCTAssertEqual(ConnectionDecision.plan(DeviceScan(targets: ["one", "two"])), .choose(["one", "two"]))
        XCTAssertEqual(ConnectionDecision.plan(DeviceScan(targets: ["one"], needsAuthorization: true)), .choose(["one"]))
    }
    func testWirelessValidation() throws {
        XCTAssertEqual(try WirelessAddress.endpoint(host: " 192.168.1.8 ", port: " 41329 "), "192.168.1.8:41329")
        for (host, port) in [("", "123"), ("192.168.1.256", "123"), ("192.168..1", "123"), ("localhost", "123"), ("127.0.0.1;echo", "123"), ("192.168.1.2", "0"), ("192.168.1.2", "65536"), ("192.168.1.2", "$(id)")] {
            XCTAssertThrowsError(try WirelessAddress.endpoint(host: host, port: port))
        }
    }
    func testBundledToolIntegrity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("app")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = BundledHDC.directory(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try BundledHDC.resolve(in: root))
        let executable = folder.appendingPathComponent("hdc")
        let bytes = Data("#!/bin/sh\nexit 0\n".utf8)
        try bytes.write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertThrowsError(try BundledHDC.resolve(in: root))
        let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let metadata = try JSONSerialization.data(withJSONObject: ["bundledSHA256": ["hdc": checksum]])
        let manifest = root.appendingPathComponent("Contents/Resources/HDC/manifest.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try metadata.write(to: manifest)
        XCTAssertEqual(try BundledHDC.resolve(in: root), executable)
        try Data("modified".utf8).write(to: executable)
        XCTAssertThrowsError(try BundledHDC.resolve(in: root))
    }
    func testProcessTimeout() async throws {
        let start = Date()
        do { _ = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["5"], timeout: 0.15); XCTFail("timeout expected") }
        catch { XCTAssertTrue(error.localizedDescription.contains("超时")) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }
    func testHDCArgumentsWithFakeExecutable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fake-hdc")
        let log = root.appendingPathComponent("arguments")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > " + Shell.quote(log.path) + "\ncase \"$*\" in *'list targets'*) printf 'local-test\\n';; esac\n"
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let targets = try await HDCTransport.discover(executable: executable)
        XCTAssertEqual(targets, ["local-test"])
        let transport = try HDCTransport(executable: executable, target: "local-test")
        let payload = "'; echo injected; #"
        try await transport.control(ControlEvent("text", text: payload))
        let captured = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(captured.contains("-t\nlocal-test\nshell\n"))
        XCTAssertTrue(captured.contains(Shell.quote(payload)))
        XCTAssertThrowsError(try HDCTransport(executable: executable, target: "-malicious"))
        do { try await transport.control(ControlEvent("click", x: -1, y: 20)); XCTFail() } catch {}
    }
    func testControlResponses() throws {
        for response in ["No Error", "No Error\n", " No Error \r\n", "", "Success", "OK"] {
            do { try ControlValidation.validate(status: 0, output: response); XCTAssertTrue(true) }
            catch { XCTFail("successful control rejected") }
        }
        for response in ["Error: action failed", "No Error\nPermission denied", "[Fail] operation", "unknown command"] {
            XCTAssertThrowsError(try ControlValidation.validate(status: 0, output: response))
        }
        do { try ControlValidation.validate(status: 0, output: "Permission denied"); XCTFail() }
        catch let error as ControlFailure { XCTAssertTrue(error.shouldDisableControl) }
        do { try ControlValidation.validate(status: 0, output: "another uitest is already running"); XCTFail() }
        catch let error as ControlFailure { XCTAssertTrue(!error.shouldDisableControl) }
    }
    func testFrameBufferAndGeometry() async throws {
        let buffer = LatestFrameBuffer()
        let first = Frame(data: Data([1]), elapsedMS: 1, capturedAt: Date(timeIntervalSince1970: 1))
        let newest = Frame(data: Data([3]), elapsedMS: 1, capturedAt: Date(timeIntervalSince1970: 3))
        await buffer.offer(first); await buffer.offer(newest); await buffer.offer(first)
        let result = try await buffer.next(); XCTAssertEqual(result.data, Data([3]))
        let waiting = Task { try await buffer.next() }; waiting.cancel()
        do { _ = try await waiting.value; XCTFail() } catch is CancellationError { XCTAssertTrue(true) }
        await buffer.report(BridgeError("temporary capture error"))
        do { _ = try await buffer.next(); XCTFail() } catch { XCTAssertTrue(true) }
        await buffer.discard(before: Date(timeIntervalSince1970: 5))
        await buffer.offer(newest)
        await buffer.offer(Frame(data: Data([6]), elapsedMS: 1, capturedAt: Date(timeIntervalSince1970: 6)))
        let recovered = try await buffer.next(); XCTAssertEqual(recovered.data, Data([6]))
        let a = PreviewSize.dimensions(width: 1128, height: 2444)
        XCTAssertEqual(a.0, 720); XCTAssertEqual(a.1, 1560)
        let b = PreviewSize.dimensions(width: 2444, height: 1128)
        XCTAssertEqual(b.0, 1560); XCTAssertEqual(b.1, 720)
        let physical = ScreenGeometry.map(x: 360, y: 780, viewWidth: 720, viewHeight: 1560, screenWidth: 1128, screenHeight: 2444)
        XCTAssertTrue(abs((physical?.0 ?? 0) - 564) <= 1); XCTAssertTrue(abs((physical?.1 ?? 0) - 1222) <= 1)
        var meter = FrameRateMeter(); _ = meter.record(at: 1); _ = meter.record(at: 1.1)
        XCTAssertTrue(abs(meter.record(at: 1.2) - 10) < 0.01)
    }

}

@main struct CheckRunner {
    static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--device"), CommandLine.arguments.count > index + 1 {
            do { try await LiveChecks.run(target: CommandLine.arguments[index + 1]); exit(0) }
            catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
        }
        let suite = BridgeTests()
        do {
            suite.testAspectFitMappingRejectsLetterbox()
            suite.testLandscapeAndBounds()
            try await suite.testShellQuotingSurvivesHostileText()
            try suite.testFileNameAndPathValidation()
            try suite.testDeviceDiscoveryAndSelection()
            try suite.testWirelessValidation()
            try suite.testBundledToolIntegrity()
            try await suite.testProcessTimeout()
            try await suite.testHDCArgumentsWithFakeExecutable()
            try suite.testControlResponses()
            try await suite.testFrameBufferAndGeometry()
        } catch { suite.failures.append(error.localizedDescription) }
        let report: [String: Any] = ["status": suite.failures.isEmpty ? "passed" : "failed", "assertions": suite.assertions, "failures": suite.failures, "phoneUsed": false, "testSuites": 11]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        exit(suite.failures.isEmpty ? 0 : 1)
    }
}
