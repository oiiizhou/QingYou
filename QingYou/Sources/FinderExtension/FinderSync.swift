import AppKit
import FinderSync
import UniformTypeIdentifiers
import OSLog

@objc(QingYouFinderSync)
final class QingYouFinderSync: FIFinderSync {
    private let logger = Logger(subsystem: Product.extensionID, category: "Finder")
    private var requestsByTag: [Int: ActionRequest] = [:]
    private var nextTag = 1
    override init() {
        super.init()
        reloadConfiguration()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(reloadConfiguration),
            name: Notification.Name(Product.configurationChanged), object: nil
        )
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self) }
    @objc private func reloadConfiguration() {
        let configuration = (try? ConfigurationStore.load()) ?? Configuration()
        FIFinderSyncController.default().directoryURLs = Set(
            configuration.monitoredPaths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        )
    }
    override var toolbarItemName: String { Product.name }
    override var toolbarItemToolTip: String { "轻右 · 文件工具" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: Product.name)!
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        if requestsByTag.count > 2_000 { requestsByTag.removeAll() }
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        var selection = controller.selectedItemURLs() ?? []
        if menuKind == .contextualMenuForContainer { selection = [] }
        if menuKind == .contextualMenuForSidebar, let target { selection = [target] }
        let directory: URL?
        if selection.count == 1,
           (try? selection[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            directory = selection[0]
        } else if let first = selection.first { directory = first.deletingLastPathComponent() }
        else { directory = target }
        let root = NSMenu()
        root.autoenablesItems = false
        let configuration: Configuration
        do { configuration = try ConfigurationStore.load() }
        catch {
            let item = NSMenuItem(title: "轻右配置无法读取，请打开设置检查", action: nil, keyEquivalent: "")
            item.isEnabled = false
            root.addItem(item)
            add("打开轻右设置…", action: .settings, to: root)
            logger.error("读取配置失败：\(error.localizedDescription, privacy: .public)")
            return root
        }
        let menu: NSMenu
        if configuration.useSubmenu && menuKind != .toolbarItemMenu {
            menu = submenu("轻右", symbol: "cursorarrow.click.2", in: root)
        } else { menu = root }
        let hasFiles = !selection.isEmpty
        let profile = SelectionProfile(selection)
        let allImages = profile.allImages
        let allFolders = profile.allFolders
        func item(_ title: String, _ action: ActionKind, _ parent: NSMenu, argument: String? = nil, image: NSImage? = nil) {
            add(title, action: action, paths: selection, directory: directory, argument: argument, image: image, to: parent)
        }
        for setting in configuration.menuItems where setting.enabled && MenuFeature.available.contains(setting.feature) {
            switch setting.feature {
            case .newFile:
                if directory != nil && configuration.templates.contains(where: \.enabled) {
                    let group = submenu("新建文件", symbol: "doc.badge.plus", in: menu)
                    for template in configuration.templates where template.enabled {
                        let icon = DocumentPresentation.icon(for: template.fileExtension)
                        item(template.menuTitle, .createFile, group, argument: template.id, image: icon)
                    }
                }
            case .clipboard:
                if hasFiles { item(selection.count > 1 ? "剪切 \(selection.count) 个项目" : "剪切文件", .cut, menu) }
                if directory != nil { item("粘贴文件到此处", .paste, menu) }
                if directory != nil {
                    item("粘贴为文件", .pasteAsFile, menu)
                    item("粘贴为 Markdown", .pasteAsFile, menu, argument: "md")
                    menu.items.last?.isAlternate = true
                    menu.items.last?.keyEquivalentModifierMask = [.option]
                }
            case .transfer:
                if hasFiles {
                    item("拷贝到…", .copyTo, menu)
                    item("移动到…", .moveTo, menu)
                }
            case .paths:
                if hasFiles || directory != nil {
                    item("拷贝路径", .copyPaths, menu)
                }
            case .openWith:
                if directory != nil {
                    item("在此处打开终端", .terminal, menu)
                }
            case .favorites, .rename, .checksum, .project: break
            case .visibility:
                if hasFiles {
                    let group = submenu("隐藏与显示", symbol: "eye", in: menu)
                    item("隐藏选中文件", .hide, group)
                    item("取消隐藏选中文件", .unhide, group)
                }
            case .folderIcon:
                if allFolders {
                    let group = submenu("文件夹图标", symbol: "paintpalette", in: menu)
                    item("使用图片作为图标…", .setIcon, group)
                    item("恢复默认图标", .resetIcon, group)
                }
            case .image:
                item("调整图片…", .imageResize, menu)
                item("图片信息…", .imageInfo, menu)
                item("图片合并为 PDF…", .imagesPDF, menu)
                if allImages {
                    let group = submenu("图片工具", symbol: "photo", in: menu)
                    item("转换为 PNG", .imagePNG, group)
                    item("转换为 JPEG", .imageJPEG, group)
                    item("识别文字并存为 TXT", .imageOCR, group)
                }
            case .pdf:
                // 两个入口始终可见；有效选区直接带入，否则由主程序选择 PDF。
                item("合并 PDF…", .pdfMerge, root)
                item("拆分 PDF…", .pdfSplit, root)
                item("压缩 PDF…", .pdfCompress, root)
                item("整理 PDF 页面…", .pdfOrganize, root)
                let exports = submenu("导出 PDF", symbol: "square.and.arrow.up", in: root)
                item("导出为图片…", .pdfImages, exports)
                item("提取文字…", .pdfText, exports)
            }
        }
        return root
    }
    private func submenu(_ title: String, symbol: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        item.submenu = menu
        parent.addItem(item)
        return menu
    }
    private func add(_ title: String, action: ActionKind, paths: [URL] = [], directory: URL? = nil,
                     argument: String? = nil, image: NSImage? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        if action == .paste {
            item.isEnabled = NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            if NSPasteboard.general.types?.contains(.init("io.github.qingyou.cut")) == true {
                item.title = "将剪切的文件移到此处"
            }
        }
        if action == .pasteAsFile {
            let board = NSPasteboard.general
            let types: [NSPasteboard.PasteboardType] = argument == "md" ? [.string, .rtf] : [.png, .tiff, .string, .rtf]
            item.isEnabled = board.types?.contains(.fileURL) != true && board.availableType(from: types) != nil
            item.toolTip = "文字保存为 TXT，图片保存为 PNG；按住 ⌥ 可将文字保存为 Markdown。"
        }
        let symbols: [ActionKind: String] = [
            .cut: "scissors", .paste: "doc.on.clipboard", .rename: "character.cursor.ibeam",
            .terminal: "terminal", .checksum: "number", .settings: "gearshape",
            .copyPaths: "link", .copyNames: "textformat", .copyShellPaths: "terminal",
            .copyMarkdown: "link", .createFile: "doc.badge.plus", .openFavorite: "folder",
            .imagePNG: "photo", .imageJPEG: "photo", .imageResize: "arrow.down.right.and.arrow.up.left",
            .imageOCR: "text.viewfinder", .pdfMerge: "doc.on.doc", .pdfSplit: "scissors",
            .copyTo: "doc.on.doc", .moveTo: "folder.badge.arrow.forward",
            .pasteAsFile: "doc.badge.plus", .imageInfo: "info.circle", .imagesPDF: "photo.on.rectangle",
            .pdfCompress: "arrow.down.doc", .pdfOrganize: "square.grid.2x2", .pdfImages: "photo", .pdfText: "text.viewfinder"
        ]
        if let image { item.image = image }
        else if let symbol = symbols[action] {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        let request = ActionRequest(action: action, paths: paths.map(\.path), directory: directory?.path, argument: argument)
        item.representedObject = try? JSONEncoder().encode(request)
        item.tag = nextTag
        requestsByTag[nextTag] = request
        nextTag += 1
        menu.addItem(item)
    }
    @objc private func performAction(_ sender: NSMenuItem) {
        do {
            // Finder 会代理菜单项；tag 比自定义 representedObject 更适合跨进程传递。
            var request: ActionRequest
            if let stored = requestsByTag[sender.tag] { request = stored }
            else if let data = sender.representedObject as? Data {
                request = try JSONDecoder().decode(ActionRequest.self, from: data)
            } else { throw FileOperationError.message("菜单项已过期，请重新打开右键菜单。") }
            logger.notice("执行菜单操作：\(request.action.rawValue, privacy: .public)")
            request.createdAt = Date()
            let inbox = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("QingYou/Requests", isDirectory: true)
            let url = try request.write(to: inbox)
            let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let options = NSWorkspace.OpenConfiguration()
            options.activates = false
            options.addsToRecentItems = false
            NSWorkspace.shared.open([url], withApplicationAt: host, configuration: options) { _, error in
                if let error { self.logger.error("主程序启动失败：\(error.localizedDescription, privacy: .public)") }
            }
        } catch {
            logger.error("提交操作失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
