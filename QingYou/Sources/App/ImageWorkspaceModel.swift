import AppKit
import PDFKit
import Combine
import UniformTypeIdentifiers

enum ImageWorkspaceMode: String {
    case resize, information, pdf
    var title: String { switch self { case .resize: return "调整图片"; case .information: return "图片信息"; case .pdf: return "图片合并为 PDF" } }
    var symbol: String { switch self { case .resize: return "arrow.up.left.and.arrow.down.right"; case .information: return "info.circle"; case .pdf: return "photo.on.rectangle" } }
}

final class ImageWorkspaceModel: ObservableObject, UtilitySession {
    let mode: ImageWorkspaceMode
    let directory: URL
    let work = LocalWorkState()
    @Published var files: [URL]
    @Published var selected: URL? { didSet { refresh() } }
    @Published var options = ImageAdjustment() { didSet { refresh() } }
    @Published var paper = ImagePDFOptions() { didSet { refresh() } }
    @Published private(set) var details: ImageDetails?
    @Published private(set) var image: NSImage?
    @Published private(set) var preview: NSImage?
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var message: String?
    @Published private(set) var preparing = false
    @Published private(set) var resultDimensions = ""
    private let queue = DispatchQueue(label: "io.github.qingyou.image-preview", qos: .userInitiated)
    private var token = WorkCancellation()
    private var generation = UUID()

    init(mode: ImageWorkspaceMode, urls: [URL], directory: URL) {
        self.mode = mode; self.files = urls; self.directory = directory
        self.selected = urls.first
        refresh()
    }
    func refresh() {
        guard !work.isWorking else { return }
        token.cancel(); token = WorkCancellation(); let cancellation = token
        let id = UUID(); generation = id
        let urls = files, source = selected ?? files.first, settings = options, paper = paper, mode = mode
        if details?.url != source { details = nil; image = nil }
        preparing = true; message = nil
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            let result = Result { () throws -> (ImageDetails?, NSImage?, NSImage?, PDFDocument?, String) in
                try cancellation.check()
                guard let source else { throw FileOperationError.message("请添加图片。") }
                if mode == .pdf {
                    let pdf = try PDFStudioOperations.imageDocument(urls, options: paper, cancellation: cancellation, progress: { _, _ in })
                    return (nil, nil, nil, pdf, "\(pdf.pageCount) 页")
                }
                let info = try ImageProcessing.details(source)
                let cgImage = try ImageProcessing.decoded(source, maxPixel: 1600, allowsMultiple: mode == .information)
                let original = NSImage(cgImage: cgImage, size: .zero)
                if mode == .information { return (info, original, nil, nil, "") }
                // 混合格式批处理也要在确认前校验全部源文件，不能只检查当前预览的一张。
                if settings.output == .original {
                    for url in urls {
                        try cancellation.check()
                        let item = url == source ? info : try ImageProcessing.details(url)
                        _ = try ImageProcessing.outputType(.original, original: item.type, filename: url.lastPathComponent)
                    }
                }
                let (w, h) = try settings.dimensions(width: info.width, height: info.height)
                var previewSettings = settings
                let factor = min(1, 1400.0 / Double(max(w, h)))
                previewSettings.sizing = .custom; previewSettings.keepRatio = false; previewSettings.allowUpscale = true
                previewSettings.width = max(1, Int(Double(w) * factor)); previewSettings.height = max(1, Int(Double(h) * factor))
                let result = try ImageProcessing.adjusted(cgImage, options: previewSettings)
                let type = try ImageProcessing.outputType(settings.output, original: info.type, filename: source.lastPathComponent)
                let rendered: NSImage
                if type == .jpeg || type == .heic, let encoded = NSImage(data: try ImageProcessing.encode(result, type: type, quality: settings.quality)) { rendered = encoded }
                else { rendered = NSImage(cgImage: result, size: .zero) }
                try cancellation.check()
                return (info, original, rendered, nil, "\(w) × \(h)")
            }
            DispatchQueue.main.async {
                guard let self, self.generation == id else { return }
                self.preparing = false
                switch result {
                case .success(let value):
                    self.details = value.0; self.image = value.1; self.preview = value.2; self.pdf = value.3; self.resultDimensions = value.4
                case .failure(let error) where error is CancellationError: break
                case .failure(let error):
                    self.message = error.localizedDescription; self.preview = nil; self.pdf = nil
                    self.resultDimensions = ""
                }
            }
        }
    }
    func move(_ index: Int, by delta: Int) {
        guard !work.isWorking, files.indices.contains(index), files.indices.contains(index + delta) else { return }
        files.swapAt(index, index + delta); refresh()
    }
    func move(from source: IndexSet, to destination: Int) { files.move(fromOffsets: source, toOffset: destination); refresh() }
    func move(_ id: String, to insertion: Int) {
        guard !work.isWorking, let from = files.firstIndex(where: { $0.absoluteString == id }), (0...files.count).contains(insertion) else { return }
        let to = insertion > from ? insertion - 1 : insertion
        guard to != from else { return }
        files.insert(files.remove(at: from), at: to); refresh()
    }
    func remove(_ url: URL) {
        guard !work.isWorking, files.count > 1 else { return }
        files.removeAll { $0 == url }
        if selected == url { selected = files.first } else { refresh() }
    }
    func addImages() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.directoryURL = directory; panel.prompt = "添加图片"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls where !files.contains(url) { files.append(url) }
            refresh()
        }
    }
    func export(removeLocationOnly: Bool = false) {
        guard !files.isEmpty, !preparing, message == nil else { return }
        let urls = mode == .information ? [selected ?? files[0]] : files
        let mode = mode, paper = paper, directory = directory
        var settings = options
        if removeLocationOnly {
            settings = ImageAdjustment(); settings.sizing = .percent; settings.percent = 100; settings.removeLocation = true
        }
        work.start(mode.title) { cancellation, progress in
            if mode == .pdf {
                let document = try PDFStudioOperations.imageDocument(urls, options: paper, cancellation: cancellation, progress: progress)
                guard let data = document.dataRepresentation() else { throw FileOperationError.message("PDF 生成失败。") }
                return try LocalOutputs.staged(in: directory, cancellation: cancellation) { staging in
                    let temp = staging.appendingPathComponent("output.pdf"); try data.write(to: temp)
                    return [(temp, "图片合并.pdf")]
                }
            }
            return try ImageProcessing.export(urls, options: settings, in: directory, suffix: removeLocationOnly ? "-无位置" : nil, cancellation: cancellation, progress: progress)
        }
    }
    func stopPreview() { token.cancel(); generation = UUID() }
}
