import AppKit

// 轻右的 Q：一条打开的环形丝带，尾端朝右延伸。所有尺寸直接由矢量生成。
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 188, yRadius: 188)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0.01, 0.12, 0.15, 0.3)
        shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set(); color(0.04, 0.15, 0.18).setFill(); tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [color(0.035, 0.12, 0.16), color(0.08, 0.24, 0.27), color(0.16, 0.34, 0.35)])!
            .draw(in: tile, angle: 70)
        color(0.69, 0.97, 0.88, 0.22).setStroke(); tile.lineWidth = 2; tile.stroke()

        let ring = NSBezierPath()
        ring.windingRule = .evenOdd
        ring.appendOval(in: NSRect(x: 256, y: 272, width: 512, height: 512))
        ring.appendOval(in: NSRect(x: 365, y: 381, width: 294, height: 294))
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color(0.25, 0.92, 0.73, 0.22)
        glow.shadowBlurRadius = 30; glow.shadowOffset = .zero; glow.set()
        color(0.59, 0.96, 0.78).setFill(); ring.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [color(0.22, 0.74, 0.64), color(0.58, 0.94, 0.75), color(0.86, 1, 0.88)])!
            .draw(in: ring, angle: 75)

        // 尾部从圆环里自然折出；暗侧面体现厚度，仍保持小图标的简洁轮廓。
        let side = NSBezierPath()
        side.move(to: NSPoint(x: 548, y: 398)); side.line(to: NSPoint(x: 692, y: 242))
        side.line(to: NSPoint(x: 803, y: 242)); side.line(to: NSPoint(x: 651, y: 410)); side.close()
        color(0.12, 0.48, 0.44).setFill(); side.fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 536, y: 444))
        tail.curve(to: NSPoint(x: 568, y: 452), controlPoint1: NSPoint(x: 544, y: 458), controlPoint2: NSPoint(x: 558, y: 461))
        tail.line(to: NSPoint(x: 794, y: 281))
        tail.curve(to: NSPoint(x: 789, y: 257), controlPoint1: NSPoint(x: 806, y: 271), controlPoint2: NSPoint(x: 802, y: 257))
        tail.line(to: NSPoint(x: 700, y: 257))
        tail.curve(to: NSPoint(x: 674, y: 269), controlPoint1: NSPoint(x: 690, y: 257), controlPoint2: NSPoint(x: 682, y: 261))
        tail.line(to: NSPoint(x: 535, y: 413))
        tail.curve(to: NSPoint(x: 536, y: 444), controlPoint1: NSPoint(x: 526, y: 422), controlPoint2: NSPoint(x: 528, y: 433))
        tail.close()
        NSGradient(starting: color(0.49, 0.88, 0.74), ending: color(0.88, 1, 0.91))!.draw(in: tail, angle: 110)
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
