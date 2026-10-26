import AppKit
import CryptoKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum MediaTools {
    static func image(_ source: URL, jpeg: Bool, resize: Bool) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, Double(width) * Double(height) <= 150_000_000 else {
            throw FileOperationError.message("图片无法读取或像素数量过大。")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: resize ? min(1920, max(width, height)) : max(width, height)
        ]
        guard var cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw FileOperationError.message("图片解码失败。")
        }
        if jpeg {
            // JPEG 没有透明通道；先铺白底，避免透明区域在转换后变黑。
            guard let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw FileOperationError.message("无法创建图片画布。")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
            guard let flattened = context.makeImage() else { throw FileOperationError.message("图片合成失败。") }
            cgImage = flattened
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, (jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString, 1, nil
        ) else { throw FileOperationError.message("无法创建图片输出。") }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileOperationError.message("图片编码失败。") }
        let stem = source.deletingPathExtension().lastPathComponent
        return try FileOperations.createFile(in: source.deletingLastPathComponent(),
            filename: "\(stem)\(resize ? "-1920" : "-converted").\(jpeg ? "jpg" : "png")", data: data as Data)
    }

    static func recognizeText(_ source: URL) throws -> URL {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let available = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { available.contains($0) }
        let handler = VNImageRequestHandler(url: source)
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.isEmpty else { throw FileOperationError.message("这张图片中没有识别到文字。") }
        return try FileOperations.createFile(in: source.deletingLastPathComponent(),
            filename: source.deletingPathExtension().lastPathComponent + "-OCR.txt", data: Data((text + "\n").utf8))
    }

    static func mergePDFs(_ sources: [URL], in directory: URL, filename: String) throws -> URL {
        let output = PDFDocument()
        let ordered = sources.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        for source in ordered {
            guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else {
                throw FileOperationError.message("无法读取 PDF，或文件已加密：\(source.lastPathComponent)")
            }
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.copy() as? PDFPage else {
                    throw FileOperationError.message("无法读取第 \(index + 1) 页：\(source.lastPathComponent)")
                }
                output.insert(page, at: output.pageCount)
            }
        }
        guard output.pageCount > 0, let data = output.dataRepresentation() else {
            throw FileOperationError.message("PDF 合并失败。")
        }
        return try FileOperations.createFile(in: directory, filename: filename, data: data)
    }

    static func splitPDF(_ source: URL) throws -> URL {
        guard let document = PDFDocument(url: source), !document.isLocked, document.pageCount > 0 else {
            throw FileOperationError.message("PDF 无法读取、没有页面或已加密。")
        }
        let fm = FileManager.default
        let parent = source.deletingLastPathComponent()
        let target = try FileOperations.availableURL(in: parent, filename: source.deletingPathExtension().lastPathComponent + "-pages")
        let staging = parent.appendingPathComponent(".qingyou-pdf-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index)?.copy() as? PDFPage else {
                throw FileOperationError.message("无法读取第 \(index + 1) 页。")
            }
            let output = PDFDocument()
            output.insert(page, at: 0)
            guard let data = output.dataRepresentation() else { throw FileOperationError.message("页面导出失败。") }
            try data.write(to: staging.appendingPathComponent(String(format: "%04d.pdf", index + 1)), options: .withoutOverwriting)
        }
        try fm.moveItem(at: staging, to: target)
        return target
    }

    static func sha256(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw FileOperationError.message("校验功能仅支持普通文件。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
