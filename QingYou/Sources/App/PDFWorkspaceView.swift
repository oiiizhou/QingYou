import AppKit
import PDFKit
import SwiftUI

struct PDFWorkspaceView: View {
    @ObservedObject var model: PDFWorkspaceModel
    let cancel: () -> Void
    @FocusState private var focusedField: PDFSplitField?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: model.mode == .merge ? "doc.on.doc" : "scissors")
                    .font(.system(size: 20)).foregroundStyle(QingYouStyle.accent)
                    .frame(width: 42, height: 42).background(QingYouStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.mode.title).font(.system(size: 21, weight: .semibold))
                    Text(model.mode == .merge ? "调整顺序，预览后合并。" : "按范围拆分，每一份都能先预览。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading || model.isUpdatingPreview { ProgressView().controlSize(.small) }
                Text("\(model.files.count) 份文档 · \(model.totalPages) 页").font(.callout).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 18)
            Divider()
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        if model.mode == .merge { mergeList } else { splitList }
                    }.padding(18)
                }.frame(minWidth: 250, idealWidth: 282, maxWidth: 330)
                    .background(Color(NSColor.controlBackgroundColor))
                HStack(spacing: 12) {
                    preview("原始文档", subtitle: model.selectedFile?.url.lastPathComponent ?? "", document: model.sourcePreview)
                    preview(model.mode == .merge ? "合并结果" : "拆分结果", subtitle: resultSubtitle, document: model.resultPreview)
                }.padding(16).frame(minWidth: 650)
            }.disabled(model.isExporting)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("保存到当前文件夹", systemImage: "folder").font(.callout.weight(.medium))
                        Text(model.directory.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text(model.mode == .merge ? "完成后在 Finder 中直接命名；原文件保留。" : "自动使用原名和页码范围命名；重名时保留两份。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if model.isExporting { ProgressView().controlSize(.small) }
                    Button("取消", action: cancel).keyboardShortcut(.cancelAction).disabled(model.isExporting)
                    Button(model.isExporting ? "正在保存…" : (model.mode == .merge ? "合并 \(model.files.count) 份 PDF" : "导出 \(model.parts.count) 份 PDF")) {
                        model.export()
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!model.canExport)
                }
            }.padding(.horizontal, 22).padding(.vertical, 16)
        }
        .background(Color(NSColor.windowBackgroundColor)).tint(QingYouStyle.accent)
        .onChange(of: model.selectedInput) { _ in model.schedulePreview() }
        .onChange(of: model.selectedPart) { _ in model.schedulePreview() }
        .onChange(of: model.parts) { _ in model.schedulePreview() }
        .onChange(of: focusedField) { field in
            if let field { model.selectedPart = field.id }
        }
    }

    private var resultSubtitle: String {
        if model.mode == .merge { return "按左侧顺序，共 \(model.resultPreview?.pageCount ?? 0) 页" }
        guard let part = model.selectedSplit else { return "请选择一份结果" }
        return "第 \(part.pages) 页 · 共 \(model.resultPreview?.pageCount ?? 0) 页"
    }

    private func preview(_ title: String, subtitle: String, document: PDFDocument?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ZStack {
                Color(NSColor.underPageBackgroundColor)
                if let document { NativePDFPreview(document: document) }
                else {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 30))
                        Text(model.isLoading ? "正在读取文档…" : "输入有效范围后显示预览")
                    }.font(.callout).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var mergeList: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("合并顺序").font(.headline)
            Text("拖动卡片排序，点选查看原文档。也可用箭头调整。").font(.caption).foregroundStyle(.secondary)
            PDFOrderList(model: model)
                .frame(height: min(560, max(180, CGFloat(model.files.count) * 84 + 12)))
        }
    }

    private var splitList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拆分范围").font(.headline)
            Text("每一项生成一份 PDF。支持 1-3、1-3,5 等页码组合。").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(model.parts.enumerated()), id: \.element.id) { index, part in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button { model.selectedPart = part.id } label: {
                            Label("第 \(index + 1) 份", systemImage: model.selectedPart == part.id ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.plain).font(.callout.weight(.medium))
                        Spacer()
                        Button { model.removePart(part.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).disabled(model.parts.count == 1).help("移除第 \(index + 1) 份")
                    }
                    TextField("例如 1-3,5", text: $model.parts[index].pages)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("第 \(index + 1) 份页码范围")
                        .focused($focusedField, equals: .pages(part.id))
                    TextField("自动按原名和页码命名", text: $model.parts[index].name)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("第 \(index + 1) 份文件名")
                        .focused($focusedField, equals: .name(part.id))
                    Text((try? PDFOperations.splitName(part, source: model.files[0].url)) ?? "文件名不可用")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }.padding(12).background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(model.selectedPart == part.id ? QingYouStyle.accent.opacity(0.35) : Color.primary.opacity(0.06)))
            }
            Button { model.addPart() } label: { Label("添加拆分范围", systemImage: "plus") }
                .frame(maxWidth: .infinity)
        }
    }
}

private enum PDFSplitField: Hashable {
    case pages(UUID), name(UUID)
    var id: UUID {
        switch self { case .pages(let id), .name(let id): return id }
    }
}

struct NativePDFPreview: NSViewRepresentable {
    let document: PDFDocument
    var selectedPage: Int? = nil
    var wholePage = false
    func makeNSView(context: Context) -> PDFPreviewSurface { PDFPreviewSurface() }
    func updateNSView(_ view: PDFPreviewSurface, context: Context) { view.setDocument(document, selectedPage: selectedPage, wholePage: wholePage) }
}

final class PDFPreviewSurface: NSView {
    private let pdf = PDFView()
    private let thumbnails = PDFThumbnailView()
    private let pageLabel = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?
    private var lastRequestedPage: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        pdf.displaysPageBreaks = true
        pdf.backgroundColor = .underPageBackgroundColor
        thumbnails.pdfView = pdf
        thumbnails.thumbnailSize = NSSize(width: 54, height: 76)
        thumbnails.maximumNumberOfColumns = 1
        thumbnails.allowsDragging = false
        thumbnails.allowsMultipleSelection = false
        thumbnails.labelFont = .systemFont(ofSize: 10)
        thumbnails.backgroundColor = .controlBackgroundColor
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        pageLabel.textColor = .secondaryLabelColor
        toolbar.addArrangedSubview(pageLabel)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)
        for (symbol, title, action) in [("minus.magnifyingglass", "缩小", #selector(zoomOut)), ("plus.magnifyingglass", "放大", #selector(zoomIn)), ("arrow.up.left.and.arrow.down.right", "适合窗口", #selector(fit))] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!, target: self, action: action)
            button.isBordered = false; button.toolTip = title; button.setAccessibilityLabel(title)
            toolbar.addArrangedSubview(button)
        }
        // PDFThumbnailView 已内置滚动，不再套一层 NSScrollView，避免缩略图被裁切。
        for view in [toolbar, thumbnails, pdf] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor), toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 32),
            thumbnails.leadingAnchor.constraint(equalTo: leadingAnchor), thumbnails.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            thumbnails.bottomAnchor.constraint(equalTo: bottomAnchor), thumbnails.widthAnchor.constraint(equalToConstant: 76),
            pdf.leadingAnchor.constraint(equalTo: thumbnails.trailingAnchor), pdf.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdf.topAnchor.constraint(equalTo: toolbar.bottomAnchor), pdf.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: pdf, queue: .main) { [weak self] _ in self?.updatePageLabel() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func setDocument(_ document: PDFDocument, selectedPage: Int? = nil, wholePage: Bool = false) {
        let changed = pdf.document !== document
        let newSelection = selectedPage != lastRequestedPage
        let displayMode: PDFDisplayMode = wholePage ? .singlePage : .singlePageContinuous
        if pdf.displayMode != displayMode { pdf.displayMode = displayMode }
        if pdf.document !== document {
            pdf.document = document
            pdf.autoScales = true
            lastRequestedPage = nil
        }
        if changed || newSelection {
            lastRequestedPage = selectedPage
            // 等 Auto Layout 给出真实预览尺寸后再定位，避免首次跳页停在空白画布。
            DispatchQueue.main.async { [weak self, weak document] in
                guard let self, let document, self.pdf.document === document, self.lastRequestedPage == selectedPage else { return }
                self.pdf.layoutDocumentView()
                self.pdf.autoScales = true
                if let page = document.page(at: selectedPage ?? 0) { self.pdf.go(to: page) }
                self.updatePageLabel()
            }
        }
        updatePageLabel()
    }
    private func updatePageLabel() {
        let current = pdf.currentPage.flatMap { pdf.document?.index(for: $0) }.map { $0 + 1 } ?? 0
        pageLabel.stringValue = "\(current) / \(pdf.document?.pageCount ?? 0)"
    }
    @objc private func zoomIn() { pdf.zoomIn(nil) }
    @objc private func zoomOut() { pdf.zoomOut(nil) }
    @objc private func fit() { pdf.autoScales = true }
}
