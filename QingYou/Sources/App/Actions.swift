import AppKit
import UniformTypeIdentifiers

extension AppStore {
    func perform(_ request: ActionRequest) {
        let urls = FileOperations.normalizedSelection(request.paths.map { URL(fileURLWithPath: $0) })
        let directory = request.directory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        do {
            switch request.action {
            case .settings:
                showWindow?()
            case .createFile:
                guard let directory,
                      let template = configuration.templates.first(where: { $0.id == request.argument && $0.enabled }) else {
                    throw FileOperationError.message("目录或模板已失效，请重新打开右键菜单。")
                }
                // 先落地文件，再交还 Finder；无需命名弹窗或模拟键盘权限。
                let filename = "未命名." + template.fileExtension
                try FileOperations.validateFilename(filename)
                let openAfter = configuration.openAfterCreation
                run("新建文件", notify: false) {
                    let data = try FileOperations.templateData(template, name: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
                                                               resources: Bundle.main.resourceURL!)
                    let output = try FileOperations.createFile(in: directory, filename: filename, data: data)
                    return TaskOutcome(detail: "已创建 \(output.lastPathComponent)", output: output,
                                       completion: { self.finishCreation(output, open: openAfter) })
                }
            case .copyPaths, .copyNames, .copyShellPaths, .copyMarkdown:
                let items = urls.isEmpty ? [directory].compactMap { $0 } : urls
                guard !items.isEmpty else { throw FileOperationError.message("没有可以复制的项目。") }
                let text = items.map { url -> String in
                    switch request.action {
                    case .copyNames: return url.lastPathComponent
                    case .copyShellPaths: return FileOperations.shellQuoted(url.path)
                    case .copyMarkdown:
                        let label = url.lastPathComponent.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                        let link = url.absoluteString.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                        return "[\(label)](\(link))"
                    default: return url.path
                    }
                }.joined(separator: request.action == .copyShellPaths ? " " : "\n")
                copyText(text)
                record("复制文件信息", detail: "已复制 \(items.count) 个项目到剪贴板", notify: false)
            case .cut:
                guard !urls.isEmpty else { throw FileOperationError.message("请先选择要剪切的文件。") }
                let board = pasteboard
                board.clearContents()
                board.writeObjects(urls as [NSURL])
                board.setString("1", forType: cutType)
                record("标记剪切", detail: "已标记 \(urls.count) 个项目，粘贴后才会移动", notify: false)
            case .paste:
                guard let directory else { throw FileOperationError.message("无法确定粘贴位置。") }
                let board = pasteboard
                let items = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                guard !items.isEmpty else { throw FileOperationError.message("剪贴板里没有文件。请先在 Finder 中复制，或使用轻右剪切。") }
                let moving = board.string(forType: cutType) == "1"
                let changeCount = board.changeCount
                let policy = configuration.collisionPolicy
                run(moving ? "粘贴并移动" : "粘贴并复制") {
                    let result = try FileOperations.transfer(items, to: directory, moving: moving, policy: policy)
                    let done = Set(result.completed.map { $0.source.path })
                    return TaskOutcome(detail: self.transferSummary(result), output: result.completed.last?.destination,
                        undo: moving ? result.completed : nil, failures: result.failures, completion: {
                            if moving && board.changeCount == changeCount {
                                let remaining = items.filter { !done.contains($0.path) }
                                board.clearContents()
                                if !remaining.isEmpty {
                                    board.writeObjects(remaining as [NSURL])
                                    board.setString("1", forType: self.cutType)
                                }
                            }
                        })
                }
            case .pasteAsFile:
                guard let directory else { throw FileOperationError.message("无法确定保存文件夹。") }
                let content = try ClipboardFile.read(pasteboard, textOnly: request.argument == "md")
                run("粘贴为文件", notify: false) {
                    let output = try content.save(in: directory, markdown: request.argument == "md")
                    return TaskOutcome(detail: "已创建 \(output.lastPathComponent)", output: output,
                        completion: { self.finishCreation(output, open: false) })
                }
            case .copyTo, .moveTo:
                guard !urls.isEmpty else { throw FileOperationError.message("请先选择文件。") }
                let destination: URL
                if let argument = request.argument {
                    guard let favorite = configuration.favorites.first(where: { $0.id.uuidString == argument }) else {
                        throw FileOperationError.message("收藏目录已移除，请重新打开菜单。")
                    }
                    destination = URL(fileURLWithPath: favorite.path)
                } else {
                    guard let chosen = chooseDirectory(message: request.action == .moveTo ? "移动到哪个文件夹？" : "复制到哪个文件夹？") else { return }
                    destination = chosen
                }
                let moving = request.action == .moveTo
                let policy = configuration.collisionPolicy
                run(moving ? "移动文件" : "复制文件") {
                    let result = try FileOperations.transfer(urls, to: destination, moving: moving, policy: policy)
                    return TaskOutcome(detail: self.transferSummary(result), output: result.completed.last?.destination,
                                       undo: moving ? result.completed : nil, failures: result.failures)
                }
            case .terminal:
                guard let directory else { throw FileOperationError.message("无法确定目录。") }
                try TerminalService.open(directory)
            case .openApplication:
                guard let app = configuration.applications.first(where: { $0.id.uuidString == request.argument }) else {
                    throw FileOperationError.message("应用已从设置中移除。")
                }
                let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) ??
                    URL(fileURLWithPath: app.path)
                guard FileOperations.exists(application) else { throw FileOperationError.message("应用不存在，请在设置中重新添加。") }
                open(urls.isEmpty ? [directory].compactMap { $0 } : urls, with: application)
            case .openFavorite:
                guard let favorite = configuration.favorites.first(where: { $0.id.uuidString == request.argument }) else {
                    throw FileOperationError.message("收藏目录已移除。")
                }
                let url = URL(fileURLWithPath: favorite.path)
                try FileOperations.requireDirectory(url)
                guard NSWorkspace.shared.open(url) else { throw FileOperationError.message("目录无法打开。") }
            case .rename:
                guard !urls.isEmpty else { throw FileOperationError.message("请先选择需要重命名的文件。") }
                presentRename?(urls)
            case .hide, .unhide:
                guard !urls.isEmpty else { return }
                let hidden = request.action == .hide
                run(hidden ? "隐藏文件" : "取消隐藏") {
                    var failures: [String] = []
                    for var url in urls {
                        do {
                            if !hidden && url.lastPathComponent.hasPrefix(".") {
                                throw FileOperationError.message("名称以点号开头，请通过重命名移除开头的点号")
                            }
                            var values = URLResourceValues()
                            values.isHidden = hidden
                            try url.setResourceValues(values)
                        } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
                    }
                    return TaskOutcome(detail: "已处理 \(urls.count - failures.count) 个项目", failures: failures)
                }
            case .setIcon, .resetIcon:
                let image: NSImage?
                if request.action == .setIcon {
                    let selected = chooseFiles(message: "选择文件夹图标图片", folders: false, types: [.image])
                    guard let first = selected.first else { return }
                    guard let loaded = NSImage(contentsOf: first) else { throw FileOperationError.message("无法读取这张图片。") }
                    image = loaded
                } else { image = nil }
                var failures: [String] = []
                for url in urls {
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                        failures.append(url.lastPathComponent + "：不是文件夹"); continue
                    }
                    if !NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) { failures.append(url.lastPathComponent) }
                }
                record("修改文件夹图标", detail: "已处理 \(urls.count - failures.count) 个文件夹", failed: !failures.isEmpty)
                if !failures.isEmpty { throw FileOperationError.message("以下文件夹修改失败：\n" + failures.joined(separator: "\n")) }
            case .pdfSplit, .pdfMerge:
                let mode: PDFWorkspaceMode = request.action == .pdfSplit ? .split : .merge
                let command: ToolCommand = mode == .split ? .splitPDF : .mergePDF
                // 空白处也能启动 PDF 工具；不合适的选区交给系统文件选择器处理。
                let inputs = command.accepts(SelectionProfile(urls)) ? urls
                    : FileOperations.normalizedSelection(selectPDFInputs(mode, directory))
                guard !inputs.isEmpty else { return }
                guard command.accepts(SelectionProfile(inputs)), let first = inputs.first else {
                    throw FileOperationError.message(mode == .split ? "请选择单个 PDF 文件进行拆分。" : "请至少选择两个 PDF 文件进行合并。")
                }
                presentPDF?(mode, inputs, directory ?? first.deletingLastPathComponent())
            case .imageResize, .imageInfo, .imagesPDF:
                let mode: ImageWorkspaceMode = request.action == .imageResize ? .resize : (request.action == .imageInfo ? .information : .pdf)
                let inputs = SelectionProfile(urls).allImages ? urls : chooseFiles(message: mode.title, folders: false, types: [.image])
                guard !inputs.isEmpty else { return }
                guard SelectionProfile(inputs).allImages else { throw FileOperationError.message("请选择有效的图片文件。") }
                presentImages?(mode, inputs, directory ?? inputs[0].deletingLastPathComponent())
            case .pdfCompress, .pdfOrganize, .pdfImages, .pdfText:
                let mode: PDFStudioMode
                switch request.action { case .pdfCompress: mode = .compress; case .pdfOrganize: mode = .organize
                case .pdfImages: mode = .images; default: mode = .text }
                let inputs = urls.count == 1 && SelectionProfile(urls).allPDFs ? urls : selectPDFStudioInput(mode, directory)
                guard !inputs.isEmpty else { return }
                guard inputs.count == 1, SelectionProfile(inputs).allPDFs else { throw FileOperationError.message("请选择一份 PDF。") }
                presentPDFStudio?(mode, inputs[0], directory ?? inputs[0].deletingLastPathComponent())
            case .imagePNG, .imageJPEG, .imageOCR:
                guard !urls.isEmpty else { return }
                let action = request.action
                let title = action == .imageOCR ? "图片文字识别" : "转换图片"
                run(title) {
                    var outputs: [URL] = []
                    var failures: [String] = []
                    for url in urls {
                        do {
                            let output = try autoreleasepool { () throws -> URL in
                                if action == .imageOCR { return try MediaTools.recognizeText(url) }
                                return try MediaTools.image(url, jpeg: action == .imageJPEG, resize: action == .imageResize)
                            }
                            outputs.append(output)
                        } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
                    }
                    return TaskOutcome(detail: "已生成 \(outputs.count) 个结果，原文件已保留", output: outputs.last, failures: failures)
                }
            case .checksum:
                guard !urls.isEmpty else { return }
                run("SHA-256 校验") {
                    var lines: [String] = []
                    var failures: [String] = []
                    for url in urls {
                        do { lines.append("\(try MediaTools.sha256(url))  \(url.lastPathComponent)") }
                        catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
                    }
                    return TaskOutcome(detail: "已计算 \(lines.count) 个文件", failures: failures, text: lines.joined(separator: "\n"))
                }
            case .academicProject, .codeProject:
                guard let directory else { throw FileOperationError.message("无法确定目录。") }
                let academic = request.action == .academicProject
                guard let name = askName(title: academic ? "新建论文项目" : "新建代码项目",
                    prompt: "创建项目目录、README 和基础子文件夹。", value: academic ? "新论文项目" : "新代码项目") else { return }
                try FileOperations.validateFilename(name)
                run("创建项目") {
                    let output = try FileOperations.createProject(in: directory, name: name, academic: academic)
                    return TaskOutcome(detail: "已创建 \(output.lastPathComponent)", output: output)
                }
            }
        } catch { report(error) }
    }

    private func open(_ urls: [URL], with app: URL) {
        let options = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: options) { _, error in
            if let error { DispatchQueue.main.async { self.report(error) } }
        }
    }
    private func transferSummary(_ result: TransferResult) -> String {
        "完成 \(result.completed.count) 项 · 跳过 \(result.skipped.count) 项 · 失败 \(result.failures.count) 项"
    }
    func applyRename(_ plan: [FileMapping]) {
        run("批量重命名") {
            let changed = try RenameEngine.apply(plan)
            return TaskOutcome(detail: "已重命名 \(changed.count) 个项目", output: changed.last?.destination, undo: changed)
        }
    }
    func undoLastMoveOrRename() {
        let mappings = undoMappings
        let identities = undoIdentities
        guard !mappings.isEmpty, pendingTasks == 0 else { return }
        run("撤销上次移动 / 重命名") {
            func requireOriginalItem(_ item: FileMapping) throws {
                guard let expected = identities[item.destination.path],
                      (try? FileIdentity.read(item.destination)) == expected else {
                    throw FileOperationError.message("文件已被移除或替换，未撤销：\(item.destination.path)")
                }
            }
            // 同目录改名可以整体回退，包含文件名交换。
            if mappings.allSatisfy({ $0.source.deletingLastPathComponent() == $0.destination.deletingLastPathComponent() }) {
                for item in mappings { try requireOriginalItem(item) }
                let reverse = mappings.map { FileMapping(source: $0.destination, destination: $0.source) }
                try RenameEngine.apply(reverse)
                return TaskOutcome(detail: "已撤销 \(mappings.count) 个项目", completion: {
                    self.remapStagedFiles(reverse)
                    self.undoMappings = []
                })
            }
            // 跨目录移动只恢复原位置空闲的项目，绝不覆盖后来新建的文件。
            var remaining: [FileMapping] = []
            var failures: [String] = []
            for item in mappings.reversed() {
                do {
                    try requireOriginalItem(item)
                    guard !FileOperations.exists(item.source) else {
                        throw FileOperationError.message("原位置已有同名文件，未覆盖")
                    }
                    try FileManager.default.moveItem(at: item.destination, to: item.source)
                } catch {
                    remaining.append(item)
                    failures.append("\(item.destination.path)：\(error.localizedDescription)")
                }
            }
            let pending = remaining
            return TaskOutcome(detail: "已恢复 \(mappings.count - remaining.count) 个项目", failures: failures,
                               completion: {
                                   let pendingPaths = Set(pending.map { $0.destination.path })
                                   self.remapStagedFiles(mappings.filter { !pendingPaths.contains($0.destination.path) }
                                       .map { FileMapping(source: $0.destination, destination: $0.source) })
                                   self.undoMappings = pending
                               })
        }
    }
}
