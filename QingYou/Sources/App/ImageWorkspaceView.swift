import SwiftUI
import AppKit

private enum ImageDimensionField: Hashable { case width, height }

struct ImageWorkspaceView: View {
    @ObservedObject var model: ImageWorkspaceModel
    @ObservedObject private var work: LocalWorkState
    let close: () -> Void
    @FocusState private var dimensionFocus: ImageDimensionField?
    @State private var widthText = "1920"
    @State private var heightText = "1920"
    @State private var percentText = "50"
    @State private var marginText = "20"
    init(model: ImageWorkspaceModel, close: @escaping () -> Void) {
        self.model = model; self.work = model.work; self.close = close
    }
    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(title: model.mode.title, subtitle: subtitle, symbol: model.mode.symbol, preparing: model.preparing)
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    if model.files.count > 1 || model.mode == .pdf { fileList }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if model.mode == .resize { resizeControls }
                            else if model.mode == .pdf { paperControls }
                            else { information }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(minWidth: 270, idealWidth: 300, maxWidth: 350)
                    .background(Color(NSColor.controlBackgroundColor)).disabled(work.isWorking)
                preview.padding(16).frame(minWidth: 540)
            }
            Divider()
            if model.mode == .information && !work.isWorking { informationFooter }
            else { UtilityFooter(work: work, directory: model.directory, message: model.message,
                canExport: !model.preparing && model.message == nil && !model.files.isEmpty,
                exportTitle: model.mode == .pdf ? "生成 PDF" : (model.mode == .information ? "生成无位置副本" : "保存 \(model.files.count) 张图片"),
                export: { model.export(removeLocationOnly: model.mode == .information) }, close: close) }
        }.background(QingYouStyle.canvas).tint(QingYouStyle.accent).font(.system(size: 13))
            .frame(minWidth: 880, minHeight: 650)
            .onChange(of: widthText) { model.options.width = Int($0) ?? 0 }
            .onChange(of: heightText) { model.options.height = Int($0) ?? 0 }
            .onChange(of: percentText) { model.options.percent = Double($0) ?? 0 }
            .onChange(of: marginText) { model.paper.margin = Double($0) ?? -1 }
            .onChange(of: model.options.width) { value in
                if dimensionFocus != .width { widthText = String(value) }
                updateLinkedDimension(from: .width)
            }
            .onChange(of: model.options.height) { value in
                if dimensionFocus != .height { heightText = String(value) }
                updateLinkedDimension(from: .height)
            }
            .onChange(of: model.options.sizing) { value in
                if value == .custom, let details = model.details {
                    let rotated = abs(model.options.quarterTurns) % 2 == 1
                    model.options.width = rotated ? details.height : details.width
                    model.options.height = rotated ? details.width : details.height
                }
            }
            .onChange(of: model.options.quarterTurns) { _ in updateLinkedDimension(from: .width, force: true) }
            .onChange(of: model.options.keepRatio) { value in if value { updateLinkedDimension(from: .width, force: true) } }
    }
    private var subtitle: String {
        switch model.mode {
        case .resize: return "设置目标像素，预览后保存副本。"
        case .information: return "只展示文件中实际记录的信息。"
        case .pdf: return "调整图片顺序与纸张，每张图片生成一页。"
        }
    }
    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.files.count) 张图片").fontWeight(.medium)
                Spacer()
                Button { model.addImages() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).help("添加图片").accessibilityLabel("添加图片")
            }.padding(12)
            UtilityOrderList(items: model.files.map { UtilityListItem(id: $0.absoluteString, title: $0.lastPathComponent, image: NSWorkspace.shared.icon(forFile: $0.path)) },
                selection: Binding(get: { model.selected?.absoluteString }, set: { model.selected = $0.flatMap(URL.init(string:)) }),
                busy: work.isWorking, compact: true,
                move: model.mode == .pdf ? { model.move($0, to: $1) } : nil,
                remove: { id in if let url = model.files.first(where: { $0.absoluteString == id }) { model.remove(url) } })
                .frame(height: CGFloat(min(4, model.files.count)) * 46 + 16)
            Divider()
        }
    }
    @ViewBuilder private var resizeControls: some View {
        Text("尺寸").font(.headline)
        Picker("调整方式", selection: $model.options.sizing) {
            ForEach(ImageSizing.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.menu)
        if model.options.sizing == .percent {
            HStack {
                Text("缩放比例")
                Spacer()
                TextField("百分比", text: $percentText)
                    .frame(width: 88).textFieldStyle(.roundedBorder).accessibilityLabel("缩放百分比")
                Text("%")
            }
        } else {
            HStack {
                Text(model.options.sizing == .fit ? "最大宽度" : "宽度")
                Spacer()
                TextField("宽度", text: $widthText)
                    .frame(width: 96).textFieldStyle(.roundedBorder).focused($dimensionFocus, equals: .width).accessibilityLabel("目标宽度")
                Text("px").foregroundStyle(.secondary)
            }
            HStack {
                Text(model.options.sizing == .fit ? "最大高度" : "高度")
                Spacer()
                TextField("高度", text: $heightText)
                    .frame(width: 96).textFieldStyle(.roundedBorder).focused($dimensionFocus, equals: .height).accessibilityLabel("目标高度")
                Text("px").foregroundStyle(.secondary)
            }
            if model.options.sizing == .custom { Toggle("保持原始比例", isOn: $model.options.keepRatio) }
        }
        Toggle("允许放大小图", isOn: $model.options.allowUpscale)
        Text(model.options.sizing == .custom && !model.options.keepRatio ? "宽高独立调整可能拉伸图片。" : "按比例缩放，不裁切画面。")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        Divider()
        Text("格式与质量").font(.headline)
        Picker("输出格式", selection: $model.options.output) {
            ForEach(ImageOutput.allCases) { Text($0.title).tag($0) }
        }
        if model.options.output != .png {
            HStack { Text("质量"); Slider(value: $model.options.quality, in: 0.2...1); Text("\(Int(model.options.quality * 100))%").monospacedDigit().frame(width: 38) }
            Text("质量设置作用于 JPEG / HEIC；PNG 不进行有损压缩。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Divider()
        HStack {
            Text("方向")
            Spacer()
            Button { model.options.quarterTurns = (model.options.quarterTurns + 1) % 4 } label: { Label("旋转", systemImage: "rotate.right") }
            Button { model.options.flipHorizontal.toggle() } label: { Image(systemName: "arrow.left.and.right") }
                .help("水平翻转").accessibilityLabel("水平翻转")
        }
        Toggle("移除副本中的位置信息", isOn: $model.options.removeLocation)
        Text("只处理副本；动态或多页图片请先导出为单张。")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }
    @ViewBuilder private var paperControls: some View {
        Text("纸张").font(.headline)
        Picker("页面大小", selection: $model.paper.paper) {
            ForEach(ImagePDFPaper.allCases) { Text($0.title).tag($0) }
        }
        if model.paper.paper != .original {
            Toggle("横向页面", isOn: $model.paper.landscape)
            HStack {
                Text("页边距")
                Spacer()
                TextField("页边距", text: $marginText).frame(width: 70).textFieldStyle(.roundedBorder)
                Text("pt").foregroundStyle(.secondary)
            }
        }
        Text("拖动上方列表排序，也可以用箭头移动。图片完整放入页面，不裁切。")
            .font(.system(size: 12)).foregroundStyle(.secondary)
        Text("相片按最长边 3200 像素以内生成 PDF，适合阅读与分享。")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }
    @ViewBuilder private var information: some View {
        if let details = model.details {
            ForEach(Array(details.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.0).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(row.1).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let url = details.mapURL {
                Button("在地图中查看记录位置") { NSWorkspace.shared.open(url) }
                Text("仅在点击后打开地图；这里不会自动查询或推测地址。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var preview: some View {
        if model.mode == .pdf {
            UtilityPDFPane(title: "PDF 预览", subtitle: model.resultDimensions, document: model.pdf)
        } else if model.mode == .information {
            UtilityImagePane(title: "图片预览", subtitle: model.details.map { "\($0.width) × \($0.height)" } ?? "", image: model.image)
        } else {
            VStack(spacing: 14) {
                UtilityImagePane(title: "原始图片", subtitle: model.details.map { "\($0.width) × \($0.height)" } ?? "", image: model.image)
                UtilityImagePane(title: "输出预览", subtitle: model.resultDimensions, image: model.preview,
                    emptyText: model.preparing ? "正在更新预览…" : "请修正左侧参数")
            }
        }
    }
    private var informationFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = work.message ?? model.message { Text(message).font(.system(size: 12)).foregroundStyle(.red) }
            HStack(spacing: 12) {
                Text("信息来自文件，未记录的内容不作推测。").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("另存无位置副本") { model.export(removeLocationOnly: true) }
                    .disabled(model.preparing || model.details?.hasLocationMetadata != true)
                    .help("按原尺寸重新编码并去除位置元数据；原文件保留。")
                Button("完成", action: close).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(.horizontal, 22).padding(.vertical, 16).background(QingYouStyle.surface).onExitCommand(perform: close)
    }
    private func updateLinkedDimension(from field: ImageDimensionField, force: Bool = false) {
        guard (force || dimensionFocus == field), model.options.sizing == .custom, model.options.keepRatio, let details = model.details else { return }
        let rotated = abs(model.options.quarterTurns) % 2 == 1
        let width = Double(rotated ? details.height : details.width), height = Double(rotated ? details.width : details.height)
        if field == .width { model.options.height = max(1, Int((Double(model.options.width) * height / width).rounded())) }
        else { model.options.width = max(1, Int((Double(model.options.height) * width / height).rounded())) }
    }
}
