import SwiftUI
import AppKit

struct PDFStudioView: View {
    @ObservedObject var model: PDFStudioModel
    @ObservedObject private var work: LocalWorkState
    let close: () -> Void
    init(model: PDFStudioModel, close: @escaping () -> Void) { self.model = model; self.work = model.work; self.close = close }
    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(title: model.mode.title, subtitle: model.source.lastPathComponent, symbol: model.mode.symbol, preparing: model.loading || model.preparing)
            Divider()
            HSplitView {
                sidebar.frame(minWidth: 280, idealWidth: 310, maxWidth: 360)
                    .background(Color(NSColor.controlBackgroundColor)).disabled(work.isWorking)
                previews.padding(16).frame(minWidth: model.mode == .compress ? 650 : 520)
            }
            Divider()
            UtilityFooter(work: work, directory: model.directory, message: model.message, canExport: model.canExport,
                exportTitle: model.mode == .images ? "导出页面图片" : (model.mode == .text ? "保存 TXT" : "保存 PDF 副本"),
                export: model.export, close: close)
        }.background(QingYouStyle.canvas).tint(QingYouStyle.accent).font(.system(size: 13))
            .frame(minWidth: model.mode == .compress ? 1020 : 880, minHeight: 650)
    }
    @ViewBuilder private var sidebar: some View {
        if model.mode == .organize {
            VStack(spacing: 0) {
                HStack {
                    Text("\(model.pages.count) 页").fontWeight(.medium)
                    Spacer()
                    Button("插入 PDF…", action: model.insertPDF).disabled(model.preparing)
                }.padding(14)
                Text("拖动排序，或使用每行的箭头。修改只影响副本。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 8)
                UtilityOrderList(items: model.pages.enumerated().map { index, page in
                    UtilityListItem(id: page.id.uuidString, title: "第 \(index + 1) 页", subtitle: page.label, image: page.thumbnail, rotation: page.rotation)
                }, selection: Binding(get: { model.selected?.uuidString }, set: { model.selected = $0.flatMap(UUID.init(uuidString:)) }),
                    busy: work.isWorking, move: { model.move($0, to: $1) },
                    rotate: { if let id = UUID(uuidString: $0) { model.rotate(id) } },
                    remove: { if let id = UUID(uuidString: $0) { model.remove(id) } })
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.mode == .compress { compressionControls }
                    else {
                        Text("页码范围").font(.headline)
                        TextField("例如 1-3,5", text: $model.range).textFieldStyle(.roundedBorder).accessibilityLabel("导出页码范围")
                        Text("共 \(model.pageCount) 页，支持 1-3、1-3,5，按输入顺序导出。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Divider()
                        if model.mode == .images {
                            Picker("图片格式", selection: $model.format) { ForEach(PDFImageFormat.allCases) { Text($0.title).tag($0) } }
                            Picker("分辨率", selection: $model.dpi) {
                                Text("72 DPI · 屏幕").tag(72.0)
                                Text("144 DPI · 清晰").tag(144.0)
                                Text("300 DPI · 打印").tag(300.0)
                            }
                            Text("每页生成一张图片，放进当前目录的新文件夹，原 PDF 保留。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            Toggle("识别没有文字层的页面", isOn: $model.recognizeScans)
                            Text("先提取已有文字；需要时使用本机 OCR。多栏排版、表格和手写内容可能需要校对。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    @ViewBuilder private var compressionControls: some View {
        Text("优化方式").font(.headline)
        Picker("优化方式", selection: $model.compression) {
            ForEach(PDFCompression.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.radioGroup).labelsHidden()
        Text(model.compression.detail).font(.system(size: 12)).foregroundStyle(.secondary)
        Divider()
        VStack(alignment: .leading, spacing: 12) {
            sizeRow("原始大小", bytes: model.originalBytes)
            sizeRow("优化后", bytes: Int64(model.compressedBytes))
        }
        Text(model.sizeNote).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Text("系统优化保留文字与矢量内容；含签名的文档应保留签署原件。")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }
    private func sizeRow(_ title: String, bytes: Int64) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(bytes > 0 ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) : "—").monospacedDigit() }
    }
    @ViewBuilder private var previews: some View {
        if model.mode == .compress {
            HStack(spacing: 12) {
                UtilityPDFPane(title: "原始文档", subtitle: model.source.lastPathComponent, document: model.original)
                UtilityPDFPane(title: "优化结果", subtitle: "\(model.pageCount) 页", document: model.preview)
            }
        } else if model.mode == .text {
            VStack(spacing: 14) {
                UtilityPDFPane(title: "所选页面", subtitle: "第 \(model.range) 页", document: model.preview)
                VStack(alignment: .leading, spacing: 8) {
                    Text("已有文字预览").fontWeight(.medium)
                    ScrollView {
                        Text(model.previewText.isEmpty ? "这些页面没有可直接提取的文字。开启上方识别选项后，导出时会进行本机 OCR。" : model.previewText)
                            .font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(14).frame(maxHeight: 180).background(QingYouStyle.surface)
            }
        } else {
            UtilityPDFPane(title: model.mode == .organize ? "整理结果" : "导出页面预览",
                subtitle: model.mode == .organize ? "\(model.pages.count) 页 · 原文档保留" : "第 \(model.range) 页", document: model.preview,
                selectedPage: model.mode == .organize ? model.selected.flatMap { id in model.pages.firstIndex(where: { $0.id == id }) } : nil)
        }
    }
}
