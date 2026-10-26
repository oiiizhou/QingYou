import AppKit
import Foundation

// 只渲染 README 的矢量插画，不修改应用图标或实机截图。
let assets = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/assets", isDirectory: true)

func render(_ source: String, output: String, scale: CGFloat) throws {
    let url = assets.appendingPathComponent(source)
    guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
        throw NSError(domain: "QingYou.Readme", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "无法读取矢量图：\(source)"])
    }
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        throw NSError(domain: "QingYou.Readme", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "无法创建插画画布"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "QingYou.Readme", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "无法导出 PNG"])
    }
    try data.write(to: assets.appendingPathComponent(output), options: .atomic)
    print("已生成 \(output) · \(Int(size.width)) × \(Int(size.height))")
}

try render("hero.svg", output: "hero.png", scale: 2)
try render("workflow.svg", output: "workflow.png", scale: 2)
try render("hero.svg", output: "social-preview.png", scale: 1)
