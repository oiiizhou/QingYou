import AppKit
import UniformTypeIdentifiers

enum DocumentPresentation {
    static let officeExtensions: Set<String> = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "wps", "et", "dps"]
    static var wpsApplication: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.kingsoft.wpsoffice.mac")
    }

    static func icon(for fileExtension: String) -> NSImage {
        let ext = fileExtension.lowercased()
        let symbol: String
        let color: NSColor
        switch ext {
        case "doc", "docx", "wps": symbol = "doc.text.fill"; color = .systemBlue
        case "xls", "xlsx", "et", "csv": symbol = "tablecells.fill"; color = .systemGreen
        case "ppt", "pptx", "dps": symbol = "rectangle.on.rectangle"; color = .systemOrange
        default:
            let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data).copy() as! NSImage
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let source = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        // 转为普通图像，Finder 跨进程代理菜单时仍能保留类型颜色。
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        source?.draw(in: NSRect(x: 1, y: 1, width: 14, height: 14))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
