import AppKit
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import CoreText

private struct WorkspaceFailure: Error { let message: String }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw WorkspaceFailure(message: message) }
}
private func rejected(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw WorkspaceFailure(message: "应拒绝的输入被接受")
}
private func spin(_ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(20)
    while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    try check(condition(), "后台处理超时")
}

@main struct WorkspaceTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingYou-workspaces-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var passed = 0
        func test(_ title: String, _ body: () throws -> Void) throws {
            try body(); passed += 1; print("✓ \(title)"); fflush(stdout)
        }
        func fixture(_ name: String, width: Int = 800, height: Int = 600,
                     color: NSColor = .red, properties: [String: Any] = [:], transparent: Bool = false) throws -> URL {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if !transparent { context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
            let image = context.makeImage()!
            let url = root.appendingPathComponent(name)
            // 独立夹具保留指定方向，测试读取和重编码时是否正确归一化。
            let data = NSMutableData()
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw WorkspaceFailure(message: "夹具生成失败") }
            try (data as Data).write(to: url)
            return url
        }
        let red = try fixture("红色.jpg")
        let blue = try fixture("蓝色.jpg", color: .blue)
        let metadata = try fixture("有方向与位置.jpg", properties: [
            kCGImagePropertyOrientation as String: 6,
            kCGImagePropertyGPSDictionary as String: ["Latitude": 37.3, "LatitudeRef": "N", "Longitude": 122.0, "LongitudeRef": "W"],
            kCGImagePropertyExifDictionary as String: ["DateTimeOriginal": "2026:10:25 12:00:00", "FNumber": 2.8],
            kCGImagePropertyTIFFDictionary as String: ["Model": "QingYou Test Camera"],
            kCGImagePropertyIPTCDictionary as String: ["City": "示例地点", "CopyrightNotice": "QingYou Test Rights"]
        ])
        let pdfURL = root.appendingPathComponent("原始文档.pdf")
        let pdfData = NSMutableData()
        let consumer = CGDataConsumer(data: pdfData)!
        let pdfContext = CGContext(consumer: consumer, mediaBox: nil, nil)!
        for index in 1...3 {
            pdfContext.beginPDFPage(nil)
            let attributed = NSAttributedString(string: "LOCAL PAGE \(index)", attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black])
            let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
            pdfContext.textPosition = CGPoint(x: 30, y: 300); CTLineDraw(line, pdfContext)
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF(); try (pdfData as Data).write(to: pdfURL)

        try test("图片尺寸支持范围、百分比、自定义拉伸与不放大") {
            var options = ImageAdjustment(); options.width = 300; options.height = 300
            let fit = try options.dimensions(width: 800, height: 600)
            try check(fit.0 == 300 && fit.1 == 225, "范围缩放失真")
            options.sizing = .percent; options.percent = 50
            let percentage = try options.dimensions(width: 800, height: 600)
            try check(percentage.0 == 400 && percentage.1 == 300, "百分比错误")
            options.percent = 200
            let noUpscale = try options.dimensions(width: 800, height: 600)
            try check(noUpscale.0 == 800 && noUpscale.1 == 600, "未经允许放大")
            options.sizing = .custom; options.keepRatio = false
            let custom = try options.dimensions(width: 800, height: 600)
            try check(custom.0 == 300 && custom.1 == 300, "自定义尺寸未独立设置")
            options.keepRatio = true; options.height = 10
            let linked = try options.dimensions(width: 800, height: 600)
            try check(linked.0 == 300 && linked.1 == 225, "锁定比例的自定义尺寸未按宽度缩放")
        }
        try test("无效或过大像素在创建画布之前拒绝") {
            var options = ImageAdjustment(); options.width = 0
            try rejected { _ = try options.dimensions(width: 800, height: 600) }
            options.width = 30_000; options.height = 30_000; options.allowUpscale = true
            try rejected { _ = try options.dimensions(width: 800, height: 600) }
        }
        try test("图片信息区分 EXIF 方向、拍摄时间与 GPS 符号") {
            let info = try ImageProcessing.details(metadata)
            try check(info.width == 600 && info.height == 800, "方向未反映在显示像素中")
            try check(info.latitude == 37.3 && info.longitude == -122, "GPS 经度符号错误")
            try check(info.rows.contains { $0.0 == "拍摄时间" && $0.1.contains("未记录时区") }, "拍摄时区被推测")
            let missing = try ImageProcessing.details(red)
            try check(missing.mapURL == nil, "无 GPS 图片产生了地图位置")
        }
        try test("方向归一化后实际输出像素正确，位置删除不影响原件") {
            var options = ImageAdjustment(); options.sizing = .percent; options.percent = 100; options.removeLocation = true
            let original = try Data(contentsOf: metadata)
            let outputs = try ImageProcessing.export([metadata], options: options, in: root, cancellation: WorkCancellation(), progress: { _, _ in })
            let info = try ImageProcessing.details(outputs[0])
            try check(info.width == 600 && info.height == 800 && info.latitude == nil && info.longitude == nil, "副本像素或位置不正确")
            let destination = CGImageSourceCreateWithURL(outputs[0] as CFURL, nil)!
            let properties = CGImageSourceCopyPropertiesAtIndex(destination, 0, nil) as! [String: Any]
            let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
            try check(iptc["City"] == nil && iptc["CopyrightNotice"] as? String == "QingYou Test Rights", "位置删除误删了版权或仍保留地点")
            let unchanged = try Data(contentsOf: metadata)
            try check(original == unchanged, "原始照片被修改")
        }
        try test("JPEG 将透明像素铺白，PNG 保留透明通道") {
            let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let image = ctx.makeImage()!
            let jpeg = try ImageProcessing.encode(image, type: .jpeg, quality: 0.9)
            let rep = NSBitmapImageRep(data: jpeg)!
            let color = rep.colorAt(x: 8, y: 8)!.usingColorSpace(.deviceRGB)!
            try check(color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95, "透明 JPEG 变黑")
            let png = NSBitmapImageRep(data: try ImageProcessing.encode(image, type: .png, quality: 1))!
            try check(png.colorAt(x: 8, y: 8)!.alphaComponent < 0.01, "PNG 失去透明通道")
        }
        try test("混合图片原格式不静默转换，明确选择 PNG 后可导出") {
            let bmp = root.appendingPathComponent("不同格式.bmp")
            try ImageProcessing.encode(ImageProcessing.decoded(red), type: .bmp, quality: 1).write(to: bmp)
            let bmpDetails = try ImageProcessing.details(bmp)
            try check(bmpDetails.type == .bmp, "未按实际文件内容识别格式")
            let before = Set(try fm.contentsOfDirectory(atPath: root.path))
            try rejected { _ = try ImageProcessing.export([red, bmp], options: ImageAdjustment(), in: root, cancellation: WorkCancellation(), progress: { _, _ in }) }
            let after = Set(try fm.contentsOfDirectory(atPath: root.path))
            try check(after == before, "格式被静默转换或留下半套输出")
            let model = ImageWorkspaceModel(mode: .resize, urls: [red, bmp], directory: root)
            try spin { !model.preparing }
            try check(model.message?.contains("不同格式.bmp") == true && model.preview == nil, "未在确认前告知混合图片格式限制")
            model.options.output = .png; try spin { !model.preparing }
            try check(model.message == nil && model.preview != nil, "明确选择格式后未恢复")
            let outputs = try ImageProcessing.export([bmp], options: model.options, in: root, cancellation: WorkCancellation(), progress: { _, _ in })
            let pngDetails = try ImageProcessing.details(outputs[0])
            try check(pngDetails.type == .png, "实际输出格式不符")
            model.stopPreview()
        }
        try test("图片批处理取消不留下半套文件，同名结果保留两份") {
            var options = ImageAdjustment(); options.width = 100; options.height = 100
            let before = Set(try fm.contentsOfDirectory(atPath: root.path))
            let token = WorkCancellation()
            try rejected { _ = try ImageProcessing.export([red, blue], options: options, in: root, cancellation: token, progress: { _, _ in token.cancel() }) }
            let after = Set(try fm.contentsOfDirectory(atPath: root.path))
            try check(before == after, "取消后残留输出或暂存目录")
            let a = try ImageProcessing.export([red], options: options, in: root, cancellation: WorkCancellation(), progress: { _, _ in })
            let b = try ImageProcessing.export([red], options: options, in: root, cancellation: WorkCancellation(), progress: { _, _ in })
            try check(a[0] != b[0], "同名图片被覆盖")
        }
        try test("剪贴板文字和图片保存为真实文件，不改变剪贴板") {
            let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
            board.setString("中文与 emoji 📝\n第二行", forType: .string)
            let count = board.changeCount
            let textURL = try ClipboardFile.read(board).save(in: root)
            let string = try String(contentsOf: textURL, encoding: .utf8)
            try check(string == "中文与 emoji 📝\n第二行" && board.changeCount == count, "文字或剪贴板被修改")
            board.clearContents(); board.setData(try Data(contentsOf: red), forType: .tiff)
            let imageURL = try ClipboardFile.read(board).save(in: root)
            let image = try ImageProcessing.details(imageURL)
            try check(imageURL.pathExtension == "png" && image.width == 800 && image.height == 600, "未生成有效 PNG")
            board.setString("# Markdown 标题", forType: .string)
            let markdown = try ClipboardFile.read(board, textOnly: true).save(in: root, markdown: true)
            let markdownText = try String(contentsOf: markdown, encoding: .utf8)
            try check(markdown.pathExtension == "md" && markdownText == "# Markdown 标题", "显式 Markdown 选择仍保存了图片")
            board.clearContents(); board.writeObjects([red as NSURL])
            try check(!ClipboardFile.canRead(board), "已有文件不应走粘贴为文件")
            try rejected { _ = try ClipboardFile.read(board) }
        }
        try test("图片生成 PDF 保留顺序、纸张和图片比例") {
            let doc = try PDFStudioOperations.imageDocument([red, blue], options: ImagePDFOptions(), cancellation: WorkCancellation(), progress: { _, _ in })
            try check(doc.pageCount == 2, "图片 PDF 页数错误")
            let box = doc.page(at: 0)!.bounds(for: .mediaBox)
            try check(abs(box.width - 595.28) < 1 && abs(box.height - 841.89) < 1, "A4 纸张错误")
            for (index, redExpected) in [(0, true), (1, false)] {
                let cgImage = try PDFStudioOperations.render(doc.page(at: index)!, dpi: 72)
                let rep = NSBitmapImageRep(cgImage: cgImage)
                let color = rep.colorAt(x: cgImage.width / 2, y: cgImage.height / 2)!.usingColorSpace(.deviceRGB)!
                try check(redExpected ? color.redComponent > 0.8 : color.blueComponent > 0.8, "PDF 图片顺序被更改")
            }
        }
        try test("PDF 页面重排、删除和旋转保留文字与原件") {
            let originalData = try Data(contentsOf: pdfURL)
            var choices = try PDFStudioOperations.pageChoices(pdfURL)
            choices[2].rotation = 90
            let document = try PDFStudioOperations.organized([choices[2], choices[0]], cancellation: WorkCancellation())
            try check(document.pageCount == 2 && document.page(at: 0)!.rotation == 90, "顺序、删除或旋转未生效")
            try check(document.page(at: 0)!.string?.contains("LOCAL PAGE 3") == true && document.page(at: 1)!.string?.contains("LOCAL PAGE 1") == true, "文字或页序丢失")
            let dataAfter = try Data(contentsOf: pdfURL)
            try check(dataAfter == originalData, "原 PDF 被修改")
        }
        try test("系统压缩保留页数与可选择的文字") {
            if #available(macOS 13.4, *) {
                let data = try PDFStudioOperations.compressed(pdfURL, mode: .smaller, cancellation: WorkCancellation())
                let document = PDFDocument(data: data)!
                try check(document.pageCount == 3 && document.page(at: 1)!.string?.contains("LOCAL PAGE 2") == true, "压缩将文字栅格化或丢页")
            }
        }
        try test("PDF 按范围导出页面图片，分辨率和文件夹命名有效") {
            let outputs = try PDFStudioOperations.exportImages(pdfURL, range: "3,1", format: .png, dpi: 144, in: root, cancellation: WorkCancellation(), progress: { _, _ in })
            let names = Set(try fm.contentsOfDirectory(atPath: outputs[0].path))
            try check(names == ["0001-原第3页.png", "0002-原第1页.png"], "导出范围或文件排序错误")
            let info = try ImageProcessing.details(outputs[0].appendingPathComponent("0002-原第1页.png"))
            let page = try PDFOperations.read(pdfURL).page(at: 0)!.bounds(for: .cropBox)
            try check(abs(Double(info.width) - page.width * 2) < 2, "导出 DPI 不正确")
            let source = try PDFOperations.read(pdfURL)
            for (name, index) in [("0001-原第3页.png", 2), ("0002-原第1页.png", 0)] {
                let actual = NSBitmapImageRep(cgImage: try ImageProcessing.decoded(outputs[0].appendingPathComponent(name)))
                let expected = NSBitmapImageRep(cgImage: try PDFStudioOperations.render(source.page(at: index)!, dpi: 144))
                // 对比文字所在区域的像素，确保文件名与实际页面对应。
                for y in stride(from: 950, to: 1000, by: 3) {
                    for x in stride(from: 60, to: 450, by: 3) {
                        let a = actual.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        let b = expected.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        try check(abs(a.redComponent - b.redComponent) < 0.02, "导出文件内容与页码不对应")
                    }
                }
            }
        }
        try test("PDF 文字范围与顺序正确，不选择 OCR 时不调用识别") {
            let text = try PDFStudioOperations.extractText(pdfURL, range: "3,1", recognizeScans: false, cancellation: WorkCancellation(), progress: { _, _ in })
            try check(text.contains("LOCAL PAGE 3") && text.contains("LOCAL PAGE 1") && !text.contains("LOCAL PAGE 2"), "文字范围错误")
            try check(text.range(of: "LOCAL PAGE 3")!.lowerBound < text.range(of: "LOCAL PAGE 1")!.lowerBound, "文字顺序错误")
        }
        try test("工作台过期预览不能覆盖新参数，错误参数可修正") {
            let model = ImageWorkspaceModel(mode: .resize, urls: [red], directory: root)
            model.options.width = 600; model.options.height = 600
            model.options.width = 200; model.options.height = 200
            try spin { !model.preparing }
            try check(model.resultDimensions == "200 × 150", "旧预览覆盖最新参数")
            model.options.width = 0; try spin { !model.preparing }
            try check(model.message != nil, "无效尺寸没有行内错误")
            model.options.width = 400; try spin { !model.preparing }
            try check(model.message == nil && model.resultDimensions == "267 × 200", "修正后没有恢复预览")
            model.stopPreview()
        }
        try test("长任务取消平衡忙碌状态，且不会提交输出") {
            let state = LocalWorkState(); var busy: [Bool] = []; var exported = false
            state.onBusy = { busy.append($0) }; state.onExport = { _ in exported = true }
            state.start("取消测试") { token, progress in
                for index in 0..<100 { try token.check(); progress(index, 100); Thread.sleep(forTimeInterval: 0.001) }
                return [red]
            }
            state.cancel(); try spin { !state.isWorking }
            try check(busy == [true, false] && !exported && state.status.contains("已取消"), "取消状态或回调不正确")
        }
        try test("原生插入位置正确映射页面与图片的导出顺序") {
            let pdf = PDFStudioModel(mode: .organize, source: pdfURL, directory: root)
            try spin { !pdf.loading && !pdf.preparing }
            let id = pdf.pages[0].id.uuidString
            pdf.move(id, to: 3); try spin { !pdf.preparing }
            try check(pdf.pages.map(\.index) == [1, 2, 0] && pdf.preview?.page(at: 0)?.string?.contains("LOCAL PAGE 2") == true, "页面拖动位置未反映到预览")
            pdf.move(id, to: 0); try spin { !pdf.preparing }
            try check(pdf.pages.map(\.index) == [0, 1, 2], "向上移动位置错误")
            let images = ImageWorkspaceModel(mode: .pdf, urls: [red, blue], directory: root)
            try spin { !images.preparing }
            images.move(red.absoluteString, to: 2); try spin { !images.preparing }
            try check(images.files == [blue, red] && images.pdf?.pageCount == 2, "图片拖动位置未反映到 PDF")
            pdf.stopPreview(); images.stopPreview()
        }
        try test("右键请求进入独立工具窗口，不提前处理文件") {
            let store = AppStore(configurationURL: root.appendingPathComponent("settings.json"), historyURL: root.appendingPathComponent("history.json"), integratesWithFinder: false, pasteboard: NSPasteboard.withUniqueName())
            var images: [ImageWorkspaceMode] = []; var pdfs: [PDFStudioMode] = []
            store.presentImages = { mode, _, _ in images.append(mode) }
            store.presentPDFStudio = { mode, _, _ in pdfs.append(mode) }
            for action in [ActionKind.imageResize, .imageInfo, .imagesPDF] { store.perform(.init(action: action, paths: [red.path], directory: root.path)) }
            for action in [ActionKind.pdfCompress, .pdfOrganize, .pdfImages, .pdfText] { store.perform(.init(action: action, paths: [pdfURL.path], directory: root.path)) }
            try check(images == [.resize, .information, .pdf] && pdfs == [.compress, .organize, .images, .text] && store.pendingTasks == 0, "请求没有正确进入工具窗口")
            store.pasteboard.releaseGlobally()
        }
        print("\n工作台测试：\(passed) 项通过，0 项失败。")
    }
}
