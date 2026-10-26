import AppKit
import Combine
import FinderSync
import UniformTypeIdentifiers
import ApplicationServices

struct ActivityEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var detail: String
    var failed: Bool = false
    var outputPath: String?
}
struct TaskOutcome {
    var detail: String
    var output: URL?
    var undo: [FileMapping]?
    var failures: [String] = []
    var text: String?
    var completion: (() -> Void)?
}

final class AppStore: ObservableObject {
    @Published var configuration: Configuration { didSet { persistConfiguration() } }
    @Published var activities: [ActivityEntry] = []
    @Published var pendingTasks = 0
    @Published var currentTask = ""
    @Published var extensionEnabled = false
    @Published var configurationError: String?
    @Published var undoMappings: [FileMapping] = []
    var undoIdentities: [String: FileIdentity] = [:]
    @Published var selectedPage: SettingsPage = .overview
    @Published var stagedFiles: [URL] = []
    @Published var receivingDrop = false
    @Published var latestFeedback: ActivityEntry?
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    let loginItem = LoginItemController()
    private let inlineRename = FinderInlineRename()
    var showFeedback: ((ActivityEntry) -> Void)?
    var showWindow: (() -> Void)?
    var presentRename: (([URL]) -> Void)?
    var presentPDF: ((PDFWorkspaceMode, [URL], URL) -> Void)?
    var presentImages: ((ImageWorkspaceMode, [URL], URL) -> Void)?
    var presentPDFStudio: ((PDFStudioMode, URL, URL) -> Void)?
    var selectPDFInputs: (PDFWorkspaceMode, URL?) -> [URL] = PDFInputPicker.choose
    var selectPDFStudioInput: (PDFStudioMode, URL?) -> [URL] = { mode, directory in
        PDFInputPicker.chooseSingle(title: mode.title, in: directory)
    }
    private var canSave = true
    private let worker = DispatchQueue(label: "io.github.qingyou.file-tasks", qos: .userInitiated)
    private let configurationURL: URL
    private let historyURL: URL
    private let integratesWithFinder: Bool
    let pasteboard: NSPasteboard
    let cutType = NSPasteboard.PasteboardType("io.github.qingyou.cut")

    init(configurationURL: URL = Product.configurationURL,
         historyURL: URL = Product.supportDirectory.appendingPathComponent("history.json"),
         integratesWithFinder: Bool = true, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.configurationURL = configurationURL
        self.historyURL = historyURL
        self.integratesWithFinder = integratesWithFinder
        do { configuration = try ConfigurationStore.load(from: configurationURL) }
        catch {
            configuration = Configuration()
            configurationError = error.localizedDescription
            canSave = false
        }
        if let data = try? Data(contentsOf: historyURL), let entries = try? JSONDecoder().decode([ActivityEntry].self, from: data) {
            activities = Array(entries.prefix(100))
        }
        if canSave {
            let known = [("Visual Studio Code", "com.microsoft.VSCode"), ("Typora", "abnerworks.Typora"),
                         ("PyCharm", "com.jetbrains.pycharm"), ("iTerm", "com.googlecode.iterm2")]
            if configuration.applications.isEmpty && integratesWithFinder {
                configuration.applications = known.compactMap { name, identifier in
                    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
                    return .init(name: name, bundleIdentifier: identifier, path: url.path)
                }
            }
            persistConfiguration()
        }
        refreshExtensionStatus()
    }
    func refreshExtensionStatus() { extensionEnabled = integratesWithFinder && FIFinderSyncController.isExtensionEnabled }
    func manageExtension() { FIFinderSyncController.showExtensionManagementInterface() }

    private func persistConfiguration() {
        guard canSave else { return }
        do {
            try ConfigurationStore.save(configuration, to: configurationURL)
            configurationError = nil
            if integratesWithFinder {
                DistributedNotificationCenter.default().postNotificationName(
                    Notification.Name(Product.configurationChanged), object: nil, userInfo: nil, deliverImmediately: true
                )
            }
        } catch { configurationError = "设置保存失败：\(error.localizedDescription)" }
    }
    func resetConfiguration() {
        do {
            if FileOperations.exists(configurationURL) {
                let backup = configurationURL.deletingLastPathComponent().appendingPathComponent("settings-backup-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: configurationURL, to: backup)
            }
            canSave = true
            configuration = Configuration()
        } catch { report(error) }
    }
    func record(_ title: String, detail: String, failed: Bool = false, output: URL? = nil, notify: Bool = true) {
        let entry = ActivityEntry(title: title, detail: detail, failed: failed, outputPath: output?.path)
        activities.insert(entry, at: 0)
        if notify {
            latestFeedback = entry
            if !failed && configuration.showsCompletionFeedback { showFeedback?(entry) }
        }
        activities = Array(activities.prefix(100))
        do {
            try FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(activities).write(to: historyURL, options: .atomic)
        } catch {
            configurationError = "操作已完成，但记录未能保存：\(error.localizedDescription)"
        }
    }
    func report(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "操作未完成"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func run(_ title: String, notify: Bool = true, task: @escaping () throws -> TaskOutcome) {
        pendingTasks += 1
        if pendingTasks == 1 { currentTask = title }
        worker.async {
            // 队列里的任务真正开始时再更新标题，避免显示尚未执行的操作。
            DispatchQueue.main.async { self.currentTask = title }
            let result = Result { try task() }
            DispatchQueue.main.async {
                self.pendingTasks -= 1
                if self.pendingTasks == 0 { self.currentTask = "" }
                switch result {
                case .success(let outcome):
                    if let undo = outcome.undo, !undo.isEmpty {
                        self.undoMappings = undo
                        self.remapStagedFiles(undo)
                        self.undoIdentities = Dictionary(uniqueKeysWithValues: undo.compactMap { item in
                            guard let identity = try? FileIdentity.read(item.destination) else { return nil }
                            return (item.destination.path, identity)
                        })
                    }
                    outcome.completion?()
                    self.record(title, detail: outcome.detail, failed: !outcome.failures.isEmpty, output: outcome.output, notify: notify)
                    if let text = outcome.text { self.showText(title: title, text: text) }
                    if !outcome.failures.isEmpty {
                        self.report(FileOperationError.message(outcome.detail + "\n\n" + outcome.failures.joined(separator: "\n")))
                    }
                case .failure(let error):
                    self.record(title, detail: error.localizedDescription, failed: true)
                    self.report(error)
                }
            }
        }
    }
    func showText(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "复制结果")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 560, height: 250))
        scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.string = text
        view.autoresizingMask = [.width]
        scroll.documentView = view
        alert.accessoryView = scroll
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { copyText(text) }
    }
    func finishCreation(_ url: URL, open: Bool, editName: Bool? = nil) {
        guard integratesWithFinder else { return }
        inlineRename.cancel()
        let finish = {
            if open { NSWorkspace.shared.open(url) }
            else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                if editName ?? self.configuration.editsNameAfterCreation { self.inlineRename.begin(url) }
            }
        }
        if configuration.prefersWPS, DocumentPresentation.officeExtensions.contains(url.pathExtension.lowercased()),
           let wps = DocumentPresentation.wpsApplication {
            // 使用“仅此文件”的关联 API，不能改动用户全局的文档默认应用。
            NSWorkspace.shared.setDefaultApplication(at: wps, toOpenFileAt: url) { error in
                DispatchQueue.main.async {
                    if let error { self.configurationError = "文件已创建，但未能设置 WPS 打开：\(error.localizedDescription)" }
                    finish()
                }
            }
        } else { finish() }
    }
    func refreshAccessibilityStatus() { accessibilityTrusted = AXIsProcessTrusted() }
    func openAccessibilitySettings() {
        // 仅用户点击入口时请求系统显示授权说明，不在每次新建文件时打断操作。
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func copyText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    func askName(title: String, prompt: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = prompt
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 26)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func chooseDirectory(message: String = "选择文件夹") -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
    func chooseFiles(message: String, folders: Bool = true, types: [UTType]? = nil) -> [URL] {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseFiles = true
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = true
        if let types { panel.allowedContentTypes = types }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls : []
    }
    func addFavorite() {
        guard let url = chooseDirectory(message: "添加常用目录") else { return }
        guard !configuration.favorites.contains(where: { $0.path == url.path }) else { return }
        configuration.favorites.append(.init(name: url.lastPathComponent, path: url.path))
    }
    func addMonitoredDirectory() {
        guard let url = chooseDirectory(message: "选择需要显示轻右菜单的目录") else { return }
        if !configuration.monitoredPaths.contains(url.path) { configuration.monitoredPaths.append(url.path) }
    }
    func addApplication() {
        let panel = NSOpenPanel()
        panel.message = "选择加入右键菜单的应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return }
        if !configuration.applications.contains(where: { $0.bundleIdentifier == identifier }) {
            configuration.applications.append(.init(name: url.deletingPathExtension().lastPathComponent,
                                                    bundleIdentifier: identifier, path: url.path))
        }
    }
    func importTemplate() {
        let panel = NSOpenPanel()
        panel.message = "选择一个有效的文档作为新建模板；以后会复制它的内容"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) <= 50_000_000, !url.pathExtension.isEmpty else {
                throw FileOperationError.message("请选择带扩展名且不超过 50 MB 的普通文件。")
            }
            let id = UUID().uuidString
            let filename = id + "." + url.pathExtension
            try FileManager.default.createDirectory(at: Product.templateDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: Product.templateDirectory.appendingPathComponent(filename))
            configuration.templates.append(.init(id: id, name: url.deletingPathExtension().lastPathComponent,
                                                 fileExtension: url.pathExtension, importedFilename: filename))
        } catch { report(error) }
    }
    func execute(_ command: ToolCommand) {
        let urls = stagedFiles.isEmpty
            ? chooseFiles(message: command.title, folders: command == .rename, types: command.contentTypes)
            : stagedFiles
        guard !urls.isEmpty else { return }
        guard command.accepts(SelectionProfile(urls)) else {
            report(FileOperationError.message("当前文件不适用于「\(command.title)」。请重新选择文件。"))
            return
        }
        perform(.init(action: command.action, paths: urls.map(\.path), directory: urls[0].deletingLastPathComponent().path))
    }

    func remapStagedFiles(_ mappings: [FileMapping]) {
        let destinations = Dictionary(mappings.map { ($0.source.path, $0.destination) }, uniquingKeysWith: { _, newest in newest })
        stagedFiles = stagedFiles.map { destinations[$0.path] ?? $0 }
    }

    func stageFiles(_ urls: [URL]) {
        stagedFiles = FileOperations.normalizedSelection(urls.filter(\.isFileURL))
        selectedPage = .tools
    }

    func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !receivingDrop else { return false }
        let providers = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !providers.isEmpty else { return false }
        guard providers.count <= 1_000 else {
            report(FileOperationError.message("单次最多拖入 1,000 个项目，请分批处理。"))
            return false
        }
        receivingDrop = true
        let group = DispatchGroup()
        let lock = NSLock()
        var received: [Int: URL] = [:]
        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return }
                lock.lock()
                received[index] = url
                lock.unlock()
            }
        }
        group.notify(queue: .main) {
            self.receivingDrop = false
            // 全部解析成功后才替换待处理列表，避免悄悄遗漏拖入的文件。
            guard received.count == providers.count else {
                self.report(FileOperationError.message("部分拖入项目无法读取。请使用「选择文件」重新添加。"))
                return
            }
            self.stageFiles(received.keys.sorted().compactMap { received[$0] })
        }
        return true
    }

    func moveFeature(_ index: Int, by offset: Int) {
        let destination = index + offset
        guard configuration.menuItems.indices.contains(destination) else { return }
        configuration.menuItems.swapAt(index, destination)
    }
}
