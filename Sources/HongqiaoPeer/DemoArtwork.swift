import AppKit

public enum DemoArtwork {
    public static func image(page: String = "home", text: String = "", interactions: Int = 0, landscape: Bool = false) -> NSImage {
        let size = landscape ? NSSize(width: 780, height: 390) : NSSize(width: 390, height: 780)
        let image = NSImage(size: size)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let rect = NSRect(origin: .zero, size: size)
        NSGradient(colors: [NSColor(srgbRed: 0.06, green: 0.11, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.12, green: 0.32, blue: 0.48, alpha: 1), NSColor(srgbRed: 0.22, green: 0.64, blue: 0.62, alpha: 1)])!.draw(in: rect, angle: -50)
        NSColor.white.withAlphaComponent(0.07).setFill()
        NSBezierPath(ovalIn: NSRect(x: -120, y: 80, width: 500, height: 500)).fill()
        NSBezierPath(ovalIn: NSRect(x: 150, y: 280, width: 390, height: 390)).fill()
        func label(_ value: String, _ x: CGFloat, _ y: CGFloat, _ font: CGFloat, color: NSColor = .white, weight: NSFont.Weight = .regular) {
            (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: font, weight: weight), .foregroundColor: color])
        }
        label("9:41", 27, size.height - 39, 15, weight: .semibold)
        label("•••  ▰", size.width - 75, size.height - 39, 14)
        let island = NSBezierPath(roundedRect: NSRect(x: size.width / 2 - 40, y: size.height - 35, width: 80, height: 18), xRadius: 9, yRadius: 9)
        NSColor.black.withAlphaComponent(0.75).setFill(); island.fill()
        if page == "home" {
            label("09:41", 26, size.height - 160, 56, weight: .thin)
            label("10 月 24 日  星期六", 29, size.height - 190, 16, color: .white.withAlphaComponent(0.8))
            label("让两块屏幕，自然相连", 29, size.height - 230, 15, color: .white.withAlphaComponent(0.65))
            let names = ["备忘录", "文件", "图库", "设置", "浏览器", "日历", "邮件", "计算器"]
            let symbols = ["note.text", "folder.fill", "photo.on.rectangle", "gearshape.fill", "safari.fill", "calendar", "envelope.fill", "plus.forwardslash.minus"]
            let colors: [NSColor] = [.systemOrange, .systemBlue, .systemPink, .systemGray, .systemCyan, .systemRed, .systemIndigo, .systemTeal]
            for i in 0..<8 {
                let x = CGFloat(27 + (i % 4) * 90), y = size.height - 350 - CGFloat(i / 4) * 112
                colors[i].withAlphaComponent(0.94).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 62, height: 62), xRadius: 17, yRadius: 17).fill()
                if let symbol = NSImage(systemSymbolName: symbols[i], accessibilityDescription: nil) {
                    let styled = symbol.withSymbolConfiguration(.init(pointSize: 27, weight: .medium))!
                    styled.draw(in: NSRect(x: x + 15, y: y + 15, width: 32, height: 32))
                }
                label(names[i], x + 9, y - 25, 13)
            }
            NSColor.white.withAlphaComponent(0.10).setFill(); NSBezierPath(roundedRect: NSRect(x: 25, y: 70, width: size.width - 50, height: 92), xRadius: 25, yRadius: 25).fill()
            label("鸿桥 · 本地演示设备", 45, 123, 17, weight: .semibold)
            label("点击图标，体验鼠标反向操作", 45, 96, 13, color: .white.withAlphaComponent(0.75))
        } else {
            NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 14, y: 65, width: size.width - 28, height: size.height - 125), xRadius: 24, yRadius: 24).fill()
            label(page, 36, size.height - 115, 28, color: NSColor.darkGray, weight: .bold)
            label("这是本机模拟页面", 36, size.height - 146, 14, color: .secondaryLabelColor)
            let body = text.isEmpty ? "欢迎使用鸿桥。\n\n在右侧输入文字后，点击发送。\n也可以拖动画面、长按或返回。\n\n交互次数：\(interactions)" : text
            (body as NSString).draw(in: NSRect(x: 36, y: 120, width: size.width - 72, height: size.height - 310), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
        }
        label("LOCAL DEMO · 非手机画面", 99, 38, 11, color: .white.withAlphaComponent(0.75))
        NSColor.white.withAlphaComponent(0.85).setFill(); NSBezierPath(roundedRect: NSRect(x: size.width / 2 - 53, y: 14, width: 106, height: 5), xRadius: 3, yRadius: 3).fill()
        NSGraphicsContext.restoreGraphicsState(); image.addRepresentation(bitmap); return image
    }
    public static func album(_ index: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 640, height: 420))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 420, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let schemes: [[NSColor]] = [[.systemTeal, .systemBlue], [.systemOrange, .systemPink], [.systemIndigo, .systemPurple], [.systemGreen, .systemTeal]]
        let colors = schemes[index % schemes.count]
        NSGradient(colors: colors)!.draw(in: NSRect(x: 0, y: 0, width: 640, height: 420), angle: 35)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: NSRect(x: 360, y: 180, width: 200, height: 200)).fill()
        let hill = NSBezierPath(); hill.move(to: .init(x: 0, y: 0)); hill.line(to: .init(x: 150, y: 240)); hill.line(to: .init(x: 340, y: 70)); hill.line(to: .init(x: 490, y: 190)); hill.line(to: .init(x: 640, y: 0)); hill.close(); hill.fill()
        ("\(String(format: "%02d", index + 1)) / 鸿桥示例图" as NSString).draw(at: NSPoint(x: 35, y: 32), withAttributes: [.font: NSFont.systemFont(ofSize: 23, weight: .medium), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState(); image.addRepresentation(bitmap); return image
    }
    public static func jpeg(_ image: NSImage) -> Data {
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.78])!
    }
}
