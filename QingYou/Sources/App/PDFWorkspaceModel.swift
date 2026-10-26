import AppKit
import PDFKit
import SwiftUI

enum PDFWorkspaceMode { case split, merge
    var title: String { self == .split ? "拆分 PDF" : "合并 PDF" }
}

struct PDFInput: Identifiable {
    let id = UUID()
    let url: URL
    var pages = 0
    var thumbnail: NSImage?
}

final class PDFWorkspaceModel: ObservableObject {
    let mode: PDFWorkspaceMode
    let directory: URL
    @Published var files: [PDFInput]
    @Published var parts: [PDFSplitPart] = []
    @Published var selectedInput: UUID?
    @Published var selectedPart: UUID?
    @Published var sourcePreview: PDFDocument?
    @Published var resultPreview: PDFDocument?
    @Published var isLoading = true
    @Published var isUpdatingPreview = false
    @Published var isExporting = false
    @Published var message: String?
    var onBusy: ((Bool) -> Void)?
    var onExport: (([URL]) -> Void)?
    private let worker = DispatchQueue(label: "io.github.qingyou.pdf-workspace", qos: .userInitiated)
    private var generation = UUID()

    var totalPages: Int { files.reduce(0) { $0 + $1.pages } }
    var canExport: Bool { !isLoading && !isUpdatingPreview && !isExporting && message == nil && resultPreview != nil }
    var selectedFile: PDFInput? { files.first { $0.id == selectedInput } ?? files.first }
    var selectedSplit: PDFSplitPart? { parts.first { $0.id == selectedPart } ?? parts.first }

    init(mode: PDFWorkspaceMode, urls: [URL], directory: URL) {
        self.mode = mode
        self.directory = directory
        files = urls.map { PDFInput(url: $0) }
        selectedInput = files.first?.id
        load()
    }

    private func load() {
        let inputs = files
        worker.async { [weak self] in
            let result = Result { try inputs.map { input -> PDFInput in
                let document = try PDFOperations.read(input.url)
                var item = input
                item.pages = document.pageCount
                item.thumbnail = document.page(at: 0)?.thumbnail(of: NSSize(width: 90, height: 120), for: .cropBox)
                return item
            } }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let items):
                    self.files = items
                    if self.mode == .split, let count = items.first?.pages {
                        let midpoint = max(1, count / 2)
                        self.parts = [PDFSplitPart(pages: midpoint == 1 ? "1" : "1-\(midpoint)")]
                        if midpoint < count { self.parts.append(PDFSplitPart(pages: midpoint + 1 == count ? "\(count)" : "\(midpoint + 1)-\(count)")) }
                        self.selectedPart = self.parts.first?.id
                    }
                    self.schedulePreview()
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }

    func schedulePreview() {
        guard !isLoading && !isExporting else { return }
        let token = UUID(); generation = token
        isUpdatingPreview = true
        message = nil
        let ordered = files.map(\.url)
        let source = selectedFile?.url
        let selected = selectedSplit
        let plans = parts
        worker.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            guard DispatchQueue.main.sync(execute: { self.generation == token && !self.isExporting }) else { return }
            // 后台仅处理自己的 PDFDocument；不同时读写已交给 PDFView 的实例。
            let result = Result { () throws -> (PDFDocument, PDFDocument) in
                guard let source else { throw FileOperationError.message("没有可预览的 PDF。") }
                let original = try PDFOperations.read(source)
                if self.mode == .merge { return (original, try PDFOperations.combined(ordered)) }
                guard !plans.isEmpty, let selected else { throw FileOperationError.message("请添加拆分范围。") }
                for part in plans {
                    _ = try PDFOperations.pages(part.pages, count: original.pageCount)
                    _ = try PDFOperations.splitName(part, source: source)
                }
                return (original, try PDFOperations.extract(original, pages: PDFOperations.pages(selected.pages, count: original.pageCount)))
            }
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                self.isUpdatingPreview = false
                switch result {
                case .success(let pair): self.sourcePreview = pair.0; self.resultPreview = pair.1
                case .failure(let error): self.resultPreview = nil; self.message = error.localizedDescription
                }
            }
        }
    }

    func move(_ id: UUID, by delta: Int) {
        guard !isExporting, let index = files.firstIndex(where: { $0.id == id }), files.indices.contains(index + delta) else { return }
        files.swapAt(index, index + delta)
        schedulePreview()
    }

    /// 原生列表给出的是两行之间的插入位置，移除原行后要修正索引。
    func move(_ id: UUID, to insertion: Int) {
        guard !isExporting, let from = files.firstIndex(where: { $0.id == id }),
              (0...files.count).contains(insertion) else { return }
        let destination = insertion > from ? insertion - 1 : insertion
        guard destination != from else { return }
        let item = files.remove(at: from)
        files.insert(item, at: destination)
        schedulePreview()
    }

    func addPart() {
        guard !isExporting else { return }
        let part = PDFSplitPart(pages: "")
        parts.append(part); selectedPart = part.id
    }

    func removePart(_ id: UUID) {
        guard !isExporting && parts.count > 1 else { return }
        parts.removeAll { $0.id == id }
        if selectedPart == id { selectedPart = parts.first?.id }
    }

    func export() {
        guard canExport else { return }
        isExporting = true
        generation = UUID()
        onBusy?(true)
        let ordered = files.map(\.url)
        let plans = parts
        worker.async { [weak self] in
            guard let self else { return }
            let result = Result { () throws -> [URL] in
                if self.mode == .merge { return [try PDFOperations.merge(ordered, in: self.directory)] }
                guard let source = ordered.first else { throw FileOperationError.message("没有可拆分的文件。") }
                return try PDFOperations.split(source, parts: plans, in: self.directory)
            }
            DispatchQueue.main.async {
                self.isExporting = false
                self.onBusy?(false)
                switch result {
                case .success(let outputs): self.onExport?(outputs)
                case .failure(let error): self.message = error.localizedDescription
                }
            }
        }
    }
}
