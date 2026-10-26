import SwiftUI

private struct RenameRow: Identifiable {
    let mapping: FileMapping
    var id: String { mapping.source.path }
    var changed: Bool { mapping.source.path != mapping.destination.path }
}

/// 输入期间合并预览请求；后台结果只允许更新对应的那一次输入。
private final class RenamePreview: ObservableObject {
    @Published var plan: [FileMapping] = []
    @Published var error: String?
    @Published var updating = true
    private var generation = UUID()
    private var pending: DispatchWorkItem?
    private let worker = DispatchQueue(label: "io.github.qingyou.rename-preview", qos: .userInitiated)

    func update(_ urls: [URL], options: RenameOptions) {
        pending?.cancel()
        let token = UUID()
        generation = token
        updating = true
        let work = DispatchWorkItem { [weak self] in
            let result = Result { () throws -> [FileMapping] in
                let plan = try RenameEngine.plan(urls, options: options)
                try RenameEngine.validate(plan)
                return plan
            }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                switch result {
                case .success(let plan): self.plan = plan; self.error = nil
                case .failure(let error): self.plan = []; self.error = error.localizedDescription
                }
                self.updating = false
            }
        }
        pending = work
        worker.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    func cancel() { pending?.cancel(); generation = UUID() }
}

struct RenameView: View {
    let urls: [URL]
    let apply: ([FileMapping]) -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var preview = RenamePreview()
    @State private var options = RenameOptions()
    @State private var onlyChanges = false
    private var changed: Int { preview.plan.filter { $0.source.path != $0.destination.path }.count }
    private var rows: [RenameRow] {
        preview.plan.map { RenameRow(mapping: $0) }.filter { !onlyChanges || $0.changed }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "character.cursor.ibeam").font(.system(size: 28, weight: .light))
                        .foregroundStyle(QingYouStyle.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("给文件一个更整齐的名字").font(.title2.bold())
                        Text("已选择 \(urls.count) 个项目 · 自然排序 · 保留文件扩展名")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        Text("查找"); TextField("要替换的文字", text: $options.find)
                        Text("替换为"); TextField("替换后的文字", text: $options.replacement)
                    }
                    GridRow {
                        Text("前缀"); TextField("名称前添加", text: $options.prefix)
                        Text("后缀"); TextField("扩展名前添加", text: $options.suffix)
                    }
                }.textFieldStyle(.roundedBorder)
                HStack(spacing: 20) {
                    Toggle("添加编号", isOn: $options.numbered)
                    Stepper("从 \(options.start) 开始", value: $options.start, in: 0...1_000_000).disabled(!options.numbered)
                    Stepper("\(options.digits) 位数字", value: $options.digits, in: 1...8).disabled(!options.numbered)
                    Spacer()
                    Button("重置") { options = RenameOptions() }.disabled(options == RenameOptions())
                }.font(.callout)
            }.padding(24)
            Divider()
            HStack {
                Text("名称预览").font(.headline)
                if preview.updating { ProgressView().controlSize(.mini) }
                Spacer()
                Toggle("只看变化", isOn: $onlyChanges).toggleStyle(.checkbox).font(.caption)
            }.padding(.horizontal, 24).padding(.vertical, 12)
            Table(rows) {
                TableColumn("原文件名") { row in
                    Text(row.mapping.source.lastPathComponent).foregroundStyle(.secondary)
                        .help(row.mapping.source.path)
                }
                TableColumn("新文件名") { row in
                    HStack {
                        Text(row.mapping.destination.lastPathComponent)
                            .foregroundStyle(row.changed ? Color.primary : Color.secondary)
                        Spacer()
                        if row.changed { Image(systemName: "pencil").foregroundStyle(QingYouStyle.accent).font(.caption) }
                    }.help(row.mapping.destination.lastPathComponent)
                }
            }
            .opacity(preview.updating ? 0.5 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: preview.updating)
            .overlay {
                if let error = preview.error, !preview.updating {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                        Text(error).font(.callout).multilineTextAlignment(.center).textSelection(.enabled)
                    }.padding(28).frame(maxWidth: 500)
                } else if rows.isEmpty && !preview.updating {
                    Text("没有需要修改的名称").foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Label(preview.updating ? "正在检查名称…" : "将修改 \(changed) 个项目",
                      systemImage: preview.error == nil ? "checkmark.shield" : "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("重命名") { apply(preview.plan) }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.updating || preview.error != nil || changed == 0)
            }.padding(20).background(.bar)
        }
        .tint(QingYouStyle.accent)
        .frame(minWidth: 780, minHeight: 540)
        .onAppear { preview.update(urls, options: options) }
        .onChange(of: options) { preview.update(urls, options: $0) }
        .onDisappear { preview.cancel() }
    }
}
