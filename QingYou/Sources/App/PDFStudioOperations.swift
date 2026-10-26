import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers

enum PDFCompression: String, CaseIterable, Identifiable {
    case quality, screen, smaller
    var id: String { rawValue }
    var title: String { switch self { case .quality: return "清晰优先"; case .screen: return "屏幕阅读"; case .smaller: return "体积优先" } }
    var detail: String { switch self {
    case .quality: return "转换嵌入图片的编码，保持图片分辨率。"
    case .screen: return "按屏幕阅读优化图片，保留原有文字与矢量。"
    case .smaller: return "同时优化图片分辨率与编码，导出前可比较效果。"
    } }
}
enum ImagePDFPaper: String, CaseIterable, Identifiable {
    case a4, letter, original
    var id: String { rawValue }
    var title: String { switch self { case .a4: return "A4"; case .letter: return "US Letter"; case .original: return "随图片尺寸" } }
}
struct ImagePDFOptions: Equatable {
    var paper: ImagePDFPaper = .a4
    var margin = 20.0
    var landscape = false
}
struct PDFPageChoice: Identifiable {
    let id = UUID()
    let source: URL
    let index: Int
    var rotation = 0
    var thumbnail: NSImage?
    var label: String { "\(source.lastPathComponent) · 第 \(index + 1) 页" }
}
enum PDFImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg
    var id: String { rawValue }
    var title: String { self == .png ? "PNG" : "JPEG" }
}

enum PDFStudioOperations {
    static func imageDocument(_ urls: [URL], options: ImagePDFOptions, cancellation: WorkCancellation,
                              progress: (Int, Int) -> Void) throws -> PDFDocument {
        guard !urls.isEmpty else { throw FileOperationError.message("请添加至少一张图片。") }
        guard options.margin.isFinite, (0...100).contains(options.margin) else { throw FileOperationError.message("页边距应在 0–100 pt 之间。") }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw FileOperationError.message("无法创建 PDF 画布。")
        }
        for (index, url) in urls.enumerated() {
            try cancellation.check()
            try autoreleasepool {
                let image = try ImageProcessing.decoded(url, maxPixel: 3200)
                var size: CGSize
                switch options.paper { case .a4: size = CGSize(width: 595.28, height: 841.89)
                case .letter: size = CGSize(width: 612, height: 792)
                case .original: size = CGSize(width: image.width, height: image.height) }
                if options.landscape && options.paper != .original { size = CGSize(width: size.height, height: size.width) }
                let margin = options.paper == .original ? 0 : options.margin
                let area = CGRect(x: margin, y: margin, width: size.width - margin * 2, height: size.height - margin * 2)
                guard area.width > 0, area.height > 0 else { throw FileOperationError.message("页边距超过纸张尺寸。") }
                var rect = CGRect(origin: .zero, size: size)
                let box = NSData(bytes: &rect, length: MemoryLayout<CGRect>.size)
                ctx.beginPDFPage([kCGPDFContextMediaBox as String: box] as CFDictionary)
                ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(rect)
                let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
                let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                ctx.interpolationQuality = .high
                ctx.draw(image, in: CGRect(x: area.midX - drawSize.width / 2, y: area.midY - drawSize.height / 2, width: drawSize.width, height: drawSize.height))
                ctx.endPDFPage()
            }
            progress(index + 1, urls.count)
        }
        ctx.closePDF()
        try cancellation.check()
        guard let document = PDFDocument(data: data as Data) else { throw FileOperationError.message("图片 PDF 生成失败。") }
        return document
    }

    static func compressed(_ source: URL, mode: PDFCompression, cancellation: WorkCancellation) throws -> Data {
        try cancellation.check()
        let document = try PDFOperations.read(source)
        guard #available(macOS 13.4, *) else { throw FileOperationError.message("系统 PDF 图片优化需要 macOS 13.4 或更新版本。") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("QingYou-compress-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let options: [PDFDocumentWriteOption: Any] = [
            .saveImagesAsJPEGOption: mode != .screen,
            .optimizeImagesForScreenOption: mode != .quality
        ]
        guard document.write(to: temporary, withOptions: options) else { throw FileOperationError.message("系统未能优化这份 PDF。") }
        try cancellation.check()
        let data = try Data(contentsOf: temporary)
        guard let check = PDFDocument(data: data), check.pageCount == document.pageCount else { throw FileOperationError.message("优化后的 PDF 校验失败。") }
        return data
    }

    static func pageChoices(_ url: URL) throws -> [PDFPageChoice] {
        let document = try PDFOperations.read(url)
        guard document.pageCount <= 5000 else { throw FileOperationError.message("请先拆分文档，页面整理单次最多处理 5000 页。") }
        return (0..<document.pageCount).map { index in
            PDFPageChoice(source: url, index: index, thumbnail: document.page(at: index)?.thumbnail(of: NSSize(width: 80, height: 100), for: .cropBox))
        }
    }

    static func organized(_ pages: [PDFPageChoice], cancellation: WorkCancellation) throws -> PDFDocument {
        guard !pages.isEmpty else { throw FileOperationError.message("至少保留一页。") }
        let output = PDFDocument()
        var documents: [URL: PDFDocument] = [:]
        for choice in pages {
            try cancellation.check()
            let document: PDFDocument
            if let cached = documents[choice.source] { document = cached }
            else { document = try PDFOperations.read(choice.source); documents[choice.source] = document }
            guard let page = document.page(at: choice.index)?.copy() as? PDFPage else { throw FileOperationError.message("页面已失效，请重新添加文档。") }
            page.rotation = ((page.rotation + choice.rotation) % 360 + 360) % 360
            output.insert(page, at: output.pageCount)
        }
        return output
    }

    static func render(_ page: PDFPage, dpi: Double) throws -> CGImage {
        guard dpi.isFinite, (36...600).contains(dpi), let reference = page.pageRef else { throw FileOperationError.message("PDF 页面或分辨率无效。") }
        let box = page.bounds(for: .cropBox)
        let rotated = abs(page.rotation) % 180 == 90
        let width = (rotated ? box.height : box.width) * dpi / 72
        let height = (rotated ? box.width : box.height) * dpi / 72
        guard width.isFinite, height.isFinite, width > 0, height > 0, width * height <= 100_000_000 else {
            throw FileOperationError.message("该页输出像素过大，请降低分辨率。")
        }
        let w = max(1, Int(width.rounded())), h = max(1, Int(height.rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw FileOperationError.message("无法创建页面图片。") }
        let target = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(target)
        ctx.concatenate(reference.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(reference)
        guard let image = ctx.makeImage() else { throw FileOperationError.message("页面渲染失败。") }
        return image
    }

    static func exportImages(_ source: URL, range: String, format: PDFImageFormat, dpi: Double,
                             in directory: URL, cancellation: WorkCancellation, progress: (Int, Int) -> Void) throws -> [URL] {
        let document = try PDFOperations.read(source)
        let pages = try PDFOperations.pages(range, count: document.pageCount)
        return try LocalOutputs.staged(in: directory, cancellation: cancellation) { staging in
            let folder = staging.appendingPathComponent("pages", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            for (offset, index) in pages.enumerated() {
                try cancellation.check()
                try autoreleasepool {
                    guard let page = document.page(at: index) else { throw FileOperationError.message("页面读取失败。") }
                    let data = try ImageProcessing.encode(render(page, dpi: dpi), type: format == .png ? .png : .jpeg, quality: 0.9)
                    // 前缀记录导出顺序，后缀保留原页码；Finder 按名称排序也与预览一致。
                    let filename = String(format: "%04d", offset + 1) + "-原第\(index + 1)页." + (format == .png ? "png" : "jpg")
                    try data.write(to: folder.appendingPathComponent(filename), options: .withoutOverwriting)
                }
                progress(offset + 1, pages.count)
            }
            return [(folder, source.deletingPathExtension().lastPathComponent + "-页面图片")]
        }
    }

    static func extractText(_ source: URL, range: String, recognizeScans: Bool, cancellation: WorkCancellation,
                            progress: (Int, Int) -> Void) throws -> String {
        let document = try PDFOperations.read(source)
        let pages = try PDFOperations.pages(range, count: document.pageCount)
        var sections: [String] = []
        for (offset, index) in pages.enumerated() {
            try cancellation.check()
            let text: String = try autoreleasepool {
                guard let page = document.page(at: index) else { throw FileOperationError.message("页面读取失败。") }
                let selectable = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !selectable.isEmpty || !recognizeScans { return selectable }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate; request.automaticallyDetectsLanguage = true
                let available = try request.supportedRecognitionLanguages()
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { available.contains($0) }
                try VNImageRequestHandler(cgImage: render(page, dpi: 150)).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            sections.append("—— 第 \(index + 1) 页 ——\n" + text)
            progress(offset + 1, pages.count)
        }
        try cancellation.check()
        return sections.joined(separator: "\n\n") + "\n"
    }
}
