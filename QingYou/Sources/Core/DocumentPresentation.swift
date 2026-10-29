import AppKit
import UniformTypeIdentifiers

enum DocumentPresentation {
    private static let menuIcons: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()
    static let officeExtensions: Set<String> = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "wps", "et", "dps"]
    static var wpsApplication: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kingsoft.wpsoffice.mac")
    }

    static func icon(for fileExtension: String) -> NSImage {
        let ext = fileExtension.lowercased()
        if let cached = menuIcons.object(forKey: ext as NSString) { return cached }
        let image = makeIcon(for: ext)
        menuIcons.setObject(image, forKey: ext as NSString)
        return image
    }

    private static func makeIcon(for ext: String) -> NSImage {
        let symbol: String
        let color: NSColor
        switch ext {
        case "doc", "docx", "wps": symbol = "doc.text.fill"; color = .systemBlue
        case "xls", "xlsx", "et", "csv": symbol = "tablecells.fill"; color = .systemGreen
        case "ppt", "pptx", "dps": symbol = "rectangle.on.rectangle"; color = .systemOrange
        default:
            return menuBitmap(NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data))
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        return menuBitmap(source)
    }

    private static func menuBitmap(_ source: NSImage?) -> NSImage {
        // 改 size 只缩小逻辑尺寸，系统图标仍可能携带 2048px 等大图。
        // 只保留菜单实际需要的 1x / 2x 位图，避免 Finder 跨进程传输整套图像。
        let image = NSImage(size: NSSize(width: 16, height: 16))
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: 16 * scale, pixelsHigh: 16 * scale, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            source?.draw(in: NSRect(x: 1, y: 1, width: 14, height: 14))
            NSGraphicsContext.restoreGraphicsState()
            bitmap.size = image.size
            image.addRepresentation(bitmap)
        }
        image.isTemplate = false
        return image
    }
}
