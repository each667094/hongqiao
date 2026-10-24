import SwiftUI
import AppKit
import HongqiaoCore

struct InteractiveScreen: NSViewRepresentable {
    var image: NSImage?
    var screenWidth: Int
    var screenHeight: Int
    var enabled: Bool
    var action: (ControlEvent) -> Void
    func makeNSView(context: Context) -> ScreenView { ScreenView() }
    func updateNSView(_ view: ScreenView, context: Context) {
        view.image = image; view.screenWidth = screenWidth; view.screenHeight = screenHeight; view.enabled = enabled; view.action = action; view.needsDisplay = true
    }
}
final class ScreenView: NSView {
    var image: NSImage?
    var screenWidth = 0, screenHeight = 0
    var enabled = false
    var action: ((ControlEvent) -> Void)?
    private var down: (Int, Int)?
    private var downTime = Date()
    private var lastScroll = Date.distantPast
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.025, green: 0.035, blue: 0.055, alpha: 1).setFill(); bounds.fill()
        guard let image else { return }
        let ratio = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let w = image.size.width * ratio, h = image.size.height * ratio
        image.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    private func point(_ event: NSEvent) -> (Int, Int)? {
        let p = convert(event.locationInWindow, from: nil)
        return ScreenGeometry.map(x: p.x, y: p.y, viewWidth: bounds.width, viewHeight: bounds.height, screenWidth: screenWidth, screenHeight: screenHeight)
    }
    override func mouseDown(with event: NSEvent) { guard enabled else { return }; window?.makeFirstResponder(self); down = point(event); downTime = Date() }
    override func mouseUp(with event: NSEvent) {
        guard enabled, let start = down, let end = point(event) else { down = nil; return }; down = nil
        let distance = hypot(Double(end.0 - start.0), Double(end.1 - start.1))
        if distance > 12 { action?(ControlEvent("swipe", x: start.0, y: start.1, endX: end.0, endY: end.1)) }
        else { action?(ControlEvent(Date().timeIntervalSince(downTime) > 0.5 ? "longClick" : "click", x: end.0, y: end.1)) }
    }
    override func rightMouseUp(with event: NSEvent) { guard enabled else { return }; action?(ControlEvent("back")) }
    override func scrollWheel(with event: NSEvent) {
        guard enabled, Date().timeIntervalSince(lastScroll) > 0.35, let p = point(event), abs(event.scrollingDeltaY) + abs(event.scrollingDeltaX) > 0.2 else { return }
        lastScroll = Date()
        let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        let delta = horizontal ? event.scrollingDeltaX : event.scrollingDeltaY
        let distance = Int(Double(horizontal ? screenWidth : screenHeight) * 0.22) * (delta > 0 ? 1 : -1)
        let x2 = horizontal ? max(0, min(screenWidth - 1, p.0 + distance)) : p.0
        let y2 = horizontal ? p.1 : max(0, min(screenHeight - 1, p.1 + distance))
        action?(ControlEvent("swipe", x: p.0, y: p.1, endX: x2, endY: y2))
    }
    override func keyDown(with event: NSEvent) { if enabled && event.keyCode == 53 { action?(ControlEvent("back")) } else { super.keyDown(with: event) } }
}
