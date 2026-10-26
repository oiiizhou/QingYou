import AppKit
import ImageIO

enum ClipboardFile {
    case text(String)
    case image(Data)

    static func canRead(_ board: NSPasteboard) -> Bool {
        guard board.types?.contains(.fileURL) != true else { return false }
        return board.availableType(from: [.png, .tiff, .string, .rtf]) != nil
    }

    static func read(_ board: NSPasteboard, textOnly: Bool = false) throws -> ClipboardFile {
        guard board.types?.contains(.fileURL) != true else {
            throw FileOperationError.message("剪贴板中已有文件，请使用“粘贴文件到此处”。")
        }
        if textOnly {
            if let text = board.string(forType: .string), !text.isEmpty { return .text(text) }
            if let data = board.data(forType: .rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string, !text.isEmpty { return .text(text) }
            throw FileOperationError.message("请先复制需要保存为 Markdown 的文字。")
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = board.data(forType: type) {
                guard data.count <= 200_000_000 else { throw FileOperationError.message("剪贴板图片过大，请先保存原图。") }
                return .image(data)
            }
        }
        if let text = board.string(forType: .string), !text.isEmpty { return .text(text) }
        if let data = board.data(forType: .rtf), let string = NSAttributedString(rtf: data, documentAttributes: nil)?.string, !string.isEmpty { return .text(string) }
        throw FileOperationError.message("请先复制一段文字或一张图片。")
    }

    func save(in directory: URL, markdown: Bool = false) throws -> URL {
        switch self {
        case .text(let string):
            return try FileOperations.createFile(in: directory, filename: markdown ? "未命名.md" : "未命名.txt", data: Data(string.utf8))
        case .image(let data):
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let w = properties[kCGImagePropertyPixelWidth as String] as? Int,
                  let h = properties[kCGImagePropertyPixelHeight as String] as? Int,
                  w > 0, h > 0, Double(w) * Double(h) <= 100_000_000,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(w, h)
                  ] as CFDictionary) else { throw FileOperationError.message("剪贴板图片无法读取或像素过大。") }
            return try FileOperations.createFile(in: directory, filename: "未命名.png", data: ImageProcessing.encode(image, type: .png, quality: 1))
        }
    }
}
