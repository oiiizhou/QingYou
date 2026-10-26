import AppKit
import SwiftUI

@main
struct QingYouMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store = AppStore()
    private var settingsWindow: NSWindow?
    private var renameWindow: NSWindow?
    private var pdfWindows: [NSWindow] = []
    private var pdfModels: [ObjectIdentifier: PDFWorkspaceModel] = [:]
    private var utilityWindows: [NSWindow] = []
    private var utilityModels: [ObjectIdentifier: UtilitySession] = [:]
    private var statusItem: NSStatusItem?
    private let feedback = CompletionFeedback()
    private var receivedRequest = false
    private var processedRequests = Set<UUID>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchedAtLogin = LoginItemController.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        NSApp.applicationIconImage = QingYouStyle.icon
        createMainMenu()
        store.loginItem.applyDefaultIfNeeded()
        store.showWindow = { [weak self] in self?.showSettings() }
        store.presentRename = { [weak self] urls in self?.showRename(urls) }
        store.presentPDF = { [weak self] mode, urls, directory in self?.showPDF(mode, urls: urls, directory: directory) }
        store.presentImages = { [weak self] mode, urls, directory in self?.showImages(mode, urls: urls, directory: directory) }
        store.presentPDFStudio = { [weak self] mode, url, directory in self?.showPDFStudio(mode, source: url, directory: directory) }
        store.showFeedback = { [weak self] entry in
            guard let self, self.settingsWindow?.isKeyWindow != true else { return }
            let canUndo = ["移动文件", "粘贴并移动", "批量重命名"].contains(entry.title)
                && !self.store.undoMappings.isEmpty && self.store.pendingTasks == 0
            self.feedback.show(entry, undo: canUndo ? { [weak self] in self?.store.undoLastMoveOrRename() } : nil)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: Product.name)
        item.button?.toolTip = "轻右 · 文件工具"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        // 登录项和扩展启动保持安静；用户直接打开应用时才显示设置窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.receivedRequest, !launchedAtLogin else { return }
            self.showSettings()
        }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        receivedRequest = true
        for filename in filenames {
            do {
                let request = try ActionRequest.consume(URL(fileURLWithPath: filename))
                guard processedRequests.insert(request.id).inserted else { continue }
                // 操作日志有固定上限，请求去重也不能无限增长。
                if processedRequests.count > 1_000 { processedRequests = [request.id] }
                DispatchQueue.main.async { self.store.perform(request) }
            } catch { DispatchQueue.main.async { self.store.report(error) } }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        store.refreshExtensionStatus()
        store.refreshAccessibilityStatus()
        store.loginItem.refresh()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store.pendingTasks > 0 {
            store.report(FileOperationError.message("文件任务还在处理中，请完成后再退出轻右。"))
            return .terminateCancel
        }
        return .terminateNow
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if pdfModels.removeValue(forKey: ObjectIdentifier(window)) != nil {
            pdfWindows.removeAll { $0 === window }
        }
        if window === renameWindow { renameWindow = nil }
        if let model = utilityModels.removeValue(forKey: ObjectIdentifier(window)) {
            model.stopPreview(); utilityWindows.removeAll { $0 === window }
        }
        // 关闭通知到达时窗口仍可能标记为可见，要排除正在关闭的这一扇。
        let remainingWindows = [settingsWindow, renameWindow].compactMap { $0 } + pdfWindows + utilityWindows
        if !remainingWindows.contains(where: { $0 !== window && $0.isVisible }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let session = utilityModels[ObjectIdentifier(sender)], session.work.isWorking {
            session.work.cancel(closeAfterwards: true); return false
        }
        return pdfModels[ObjectIdentifier(sender)]?.isExporting != true
    }

    private func showImages(_ mode: ImageWorkspaceMode, urls: [URL], directory: URL) {
        let model = ImageWorkspaceModel(mode: mode, urls: urls, directory: directory)
        showUtility(title: mode.title, model: model, size: NSSize(width: 1080, height: 780)) { close in
            ImageWorkspaceView(model: model, close: close)
        }
    }
    private func showPDFStudio(_ mode: PDFStudioMode, source: URL, directory: URL) {
        let model = PDFStudioModel(mode: mode, source: source, directory: directory)
        showUtility(title: mode.title, model: model, size: NSSize(width: mode == .compress ? 1200 : 1080, height: 780)) { close in
            PDFStudioView(model: model, close: close)
        }
    }
    private func showUtility<Content: View>(title: String, model: UtilitySession, size: NSSize,
                                          content: (@escaping () -> Void) -> Content) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title + " · 轻右"; window.titlebarAppearsTransparent = true; window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentViewController = NSHostingController(rootView: content { [weak window] in window?.performClose(nil) })
        window.minSize = NSSize(width: title == PDFStudioMode.compress.title ? 1040 : 900, height: 700)
        window.setContentSize(size)
        model.work.closeWindow = { [weak window] in window?.close() }
        model.work.onBusy = { [weak self] busy in
            guard let self else { return }
            self.store.pendingTasks += busy ? 1 : -1
            if busy { self.store.currentTask = title }
            else if self.store.pendingTasks == 0 { self.store.currentTask = "" }
        }
        model.work.onExport = { [weak self, weak window] outputs in
            guard let self, let first = outputs.first else { return }
            self.store.record(title, detail: "已生成 \(outputs.count) 个结果，原文件保留", output: first, notify: false)
            window?.close()
            if outputs.count == 1 { self.store.finishCreation(first, open: false) }
            else { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        }
        utilityModels[ObjectIdentifier(window)] = model; utilityWindows.append(window)
        window.center(); NSApp.setActivationPolicy(.regular); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func showPDF(_ mode: PDFWorkspaceMode, urls: [URL], directory: URL) {
        let model = PDFWorkspaceModel(mode: mode, urls: urls, directory: directory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = mode.title + " · 轻右"
        window.minSize = NSSize(width: 1040, height: 650)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: PDFWorkspaceView(model: model, cancel: { [weak window] in window?.close() }))
        model.onBusy = { [weak self] busy in
            guard let self else { return }
            self.store.pendingTasks += busy ? 1 : -1
            if busy { self.store.currentTask = mode.title }
            else if self.store.pendingTasks == 0 { self.store.currentTask = "" }
        }
        model.onExport = { [weak self, weak window] outputs in
            guard let self, let first = outputs.first else { return }
            self.store.record(mode.title, detail: "已生成 \(outputs.count) 份 PDF，原文件保留", output: first, notify: false)
            window?.close()
            if mode == .merge || outputs.count == 1 { self.store.finishCreation(first, open: false, editName: true) }
            else { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
        }
        pdfModels[ObjectIdentifier(window)] = model
        pdfWindows.append(window)
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = Product.name
            // 使用系统交通灯和紧凑工具栏，保留关闭、最小化、全屏与窗口拖动行为。
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unifiedCompact
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
            window.minSize = NSSize(width: 900, height: 700)
            // HostingController 会先按最小布局测量；挂载后再设定首次打开的内容尺寸。
            window.setContentSize(NSSize(width: 1040, height: 760))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("QingYouSettings")
            settingsWindow = window
        }
        store.refreshExtensionStatus()
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showRename(_ urls: [URL]) {
        renameWindow?.close()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "批量重命名 · 轻右"
        window.minSize = NSSize(width: 800, height: 570)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RenameView(urls: urls, apply: { [weak self, weak window] plan in
            self?.store.applyRename(plan)
            window?.close()
        }, cancel: { [weak window] in window?.close() }))
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        renameWindow = window
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: store.pendingTasks > 0 ? "正在处理 \(store.pendingTasks) 项任务…" : "轻右 · 文件工具", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "打开轻右…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let undo = NSMenuItem(title: "撤销上次移动 / 重命名", action: #selector(undoLast), keyEquivalent: "")
        undo.target = self
        undo.isEnabled = !store.undoMappings.isEmpty && store.pendingTasks == 0
        menu.addItem(undo)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出轻右", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }
    @objc private func undoLast() { store.undoLastMoveOrRename() }
    @objc private func focusFeatureSearch() {
        showSettings()
        // 从系统菜单响应快捷键，窗口首次创建时也能等视图订阅完成再聚焦。
        DispatchQueue.main.async { NotificationCenter.default.post(name: .qingYouFocusSearch, object: nil) }
    }
    private func createMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "轻右设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出轻右", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let file = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let close = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.keyEquivalentModifierMask = .command
        // target 留空，沿系统响应链关闭当前窗口，也尊重导出中的关闭保护。
        fileMenu.addItem(close)
        file.submenu = fileMenu
        main.addItem(file)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let search = NSMenuItem(title: "搜索轻右功能", action: #selector(focusFeatureSearch), keyEquivalent: "f")
        search.target = self
        editMenu.addItem(search)
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }
}
