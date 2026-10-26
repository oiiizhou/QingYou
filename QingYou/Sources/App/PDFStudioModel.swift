import AppKit
import PDFKit
import Combine

enum PDFStudioMode: String {
    case compress, organize, images, text
    var title: String { switch self { case .compress: return "压缩 PDF"; case .organize: return "整理 PDF 页面"; case .images: return "PDF 导出图片"; case .text: return "提取 PDF 文字" } }
    var symbol: String { switch self { case .compress: return "arrow.down.doc"; case .organize: return "square.grid.2x2"; case .images: return "photo"; case .text: return "text.viewfinder" } }
}

final class PDFStudioModel: ObservableObject, UtilitySession {
    let mode: PDFStudioMode
    let source: URL
    let directory: URL
    let work = LocalWorkState()
    @Published var compression: PDFCompression = .screen { didSet { refresh() } }
    @Published var pages: [PDFPageChoice] = []
    @Published var selected: UUID?
    @Published var range = "" { didSet { if !loading { refresh() } } }
    @Published var format: PDFImageFormat = .png
    @Published var dpi = 144.0
    @Published var recognizeScans = true
    @Published private(set) var original: PDFDocument?
    @Published private(set) var preview: PDFDocument?
    @Published private(set) var previewText = ""
    @Published private(set) var originalBytes: Int64 = 0
    @Published private(set) var compressedBytes = 0
    @Published private(set) var loading = true
    @Published private(set) var preparing = false
    @Published private(set) var message: String?
    @Published private(set) var pageCount = 0
    private var compressedData: Data?
    private let queue = DispatchQueue(label: "io.github.qingyou.pdf-studio", qos: .userInitiated)
    private var cancellation = WorkCancellation()
    private var generation = UUID()

    init(mode: PDFStudioMode, source: URL, directory: URL) {
        self.mode = mode; self.source = source; self.directory = directory
        queue.async { [weak self] in
            let result = Result { () throws -> (PDFDocument, [PDFPageChoice], Int64) in
                let document = try PDFOperations.read(source)
                let pages = mode == .organize ? try PDFStudioOperations.pageChoices(source) : []
                let bytes = ((try FileManager.default.attributesOfItem(atPath: source.path))[.size] as? NSNumber)?.int64Value ?? 0
                return (document, pages, bytes)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let value):
                    self.original = value.0; self.pages = value.1; self.originalBytes = value.2
                    self.pageCount = value.0.pageCount; self.range = "1-\(value.0.pageCount)"; self.selected = value.1.first?.id
                    self.loading = false; self.refresh()
                case .failure(let error): self.loading = false; self.message = error.localizedDescription
                }
            }
        }
    }
    var canExport: Bool { !loading && !preparing && !work.isWorking && message == nil && (mode != .compress || compressedData != nil) }
    var sizeNote: String {
        guard compressedBytes > 0 else { return "正在计算实际体积…" }
        if Int64(compressedBytes) >= originalBytes { return "这份文档没有变小，可以更换优化方式，或保留原件。" }
        let saved = 100 * (1 - Double(compressedBytes) / Double(max(1, originalBytes)))
        return String(format: "体积减少 %.1f%%，原有文字与矢量保留。", saved)
    }
    func refresh() {
        guard !loading, !work.isWorking, original != nil else { return }
        cancellation.cancel(); cancellation = WorkCancellation(); let token = cancellation
        generation = UUID(); let id = generation
        let source = source, mode = mode, compression = compression, choices = pages, range = range
        preparing = true; message = nil
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            let result = Result { () throws -> (PDFDocument?, Data?, String) in
                try token.check()
                switch mode {
                case .compress:
                    let data = try PDFStudioOperations.compressed(source, mode: compression, cancellation: token)
                    return (PDFDocument(data: data), data, "")
                case .organize: return (try PDFStudioOperations.organized(choices, cancellation: token), nil, "")
                case .images, .text:
                    let document = try PDFOperations.read(source)
                    let indexes = try PDFOperations.pages(range, count: document.pageCount)
                    let extracted = try PDFOperations.extract(document, pages: indexes)
                    let text = mode == .text ? indexes.compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n") : ""
                    return (extracted, nil, text)
                }
            }
            DispatchQueue.main.async {
                guard let self, self.generation == id else { return }
                self.preparing = false
                switch result {
                case .success(let value): self.preview = value.0; self.compressedData = value.1; self.compressedBytes = value.1?.count ?? 0; self.previewText = value.2
                case .failure(let error) where error is CancellationError: break
                case .failure(let error): self.message = error.localizedDescription; self.preview = nil; self.compressedData = nil
                }
            }
        }
    }
    func move(_ id: UUID, by delta: Int) {
        guard !work.isWorking, let index = pages.firstIndex(where: { $0.id == id }), pages.indices.contains(index + delta) else { return }
        pages.swapAt(index, index + delta); refresh()
    }
    func move(from source: IndexSet, to destination: Int) { pages.move(fromOffsets: source, toOffset: destination); refresh() }
    func move(_ id: String, to insertion: Int) {
        guard !work.isWorking, let from = pages.firstIndex(where: { $0.id.uuidString == id }), (0...pages.count).contains(insertion) else { return }
        let to = insertion > from ? insertion - 1 : insertion
        guard from != to else { return }
        pages.insert(pages.remove(at: from), at: to); refresh()
    }
    func rotate(_ id: UUID) {
        guard !work.isWorking, let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].rotation = (pages[index].rotation + 90) % 360; refresh()
    }
    func remove(_ id: UUID) {
        guard !work.isWorking, pages.count > 1 else { return }
        pages.removeAll { $0.id == id }; if selected == id { selected = pages.first?.id }; refresh()
    }
    func insertPDF() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.pdf]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true; panel.directoryURL = directory; panel.prompt = "插入页面"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        preparing = true; message = nil
        let insertion = selected.flatMap { id in pages.firstIndex(where: { $0.id == id }) }.map { $0 + 1 } ?? pages.count
        queue.async { [weak self] in
            let result = Result { try urls.flatMap { try PDFStudioOperations.pageChoices($0) } }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let items): self.pages.insert(contentsOf: items, at: min(insertion, self.pages.count)); self.refresh()
                case .failure(let error): self.preparing = false; self.message = error.localizedDescription
                }
            }
        }
    }
    func export() {
        guard canExport else { return }
        let mode = mode, source = source, directory = directory, choices = pages, range = range
        let data = compressedData, format = format, dpi = dpi, ocr = recognizeScans
        work.start(mode.title) { token, progress in
            switch mode {
            case .compress, .organize:
                let output: Data
                if mode == .compress, let data { output = data }
                else if let value = try PDFStudioOperations.organized(choices, cancellation: token).dataRepresentation() { output = value }
                else { throw FileOperationError.message("PDF 输出失败。") }
                return try LocalOutputs.staged(in: directory, cancellation: token) { staging in
                    let temp = staging.appendingPathComponent("result.pdf"); try output.write(to: temp)
                    return [(temp, source.deletingPathExtension().lastPathComponent + (mode == .compress ? "-压缩.pdf" : "-整理.pdf"))]
                }
            case .images:
                return try PDFStudioOperations.exportImages(source, range: range, format: format, dpi: dpi, in: directory, cancellation: token, progress: progress)
            case .text:
                let text = try PDFStudioOperations.extractText(source, range: range, recognizeScans: ocr, cancellation: token, progress: progress)
                return try LocalOutputs.staged(in: directory, cancellation: token) { staging in
                    let temp = staging.appendingPathComponent("text.txt"); try Data(text.utf8).write(to: temp)
                    return [(temp, source.deletingPathExtension().lastPathComponent + "-文字.txt")]
                }
            }
        }
    }
    func stopPreview() { cancellation.cancel(); generation = UUID() }
}
