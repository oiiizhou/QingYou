import AppKit
import FinderSync

@main
struct FinderMenuTests {
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("QingYouMenuTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let configURL = root.appendingPathComponent("settings.json")
        var config = Configuration(); config.monitoredPaths = []
        try ConfigurationStore.save(config, to: configURL)
        let finder = QingYouFinderSync(configurationURL: configURL)
        func menu(_ selection: [URL] = [], types: Set<NSPasteboard.PasteboardType> = []) -> NSMenu {
            finder.makeMenu(for: selection.isEmpty ? .contextualMenuForContainer : .contextualMenuForItems,
                            target: root, selection: selection, clipboardTypes: types)
        }
        func items(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map { items($0) } ?? []) }
        }
        struct Failure: Error { let message: String }
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw Failure(message: message) }
        }
        var passed = 0
        func test(_ name: String, _ body: () throws -> Void) throws {
            try body(); passed += 1; print("✓ \(name)")
        }
        func refresh() {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Product.configurationChanged), object: nil, userInfo: nil, deliverImmediately: true)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        try test("13 种模板只携带菜单尺寸的位图，不传输系统大图") {
            for template in config.templates {
                let icon = DocumentPresentation.icon(for: template.fileExtension)
                try require(icon.size == NSSize(width: 16, height: 16), "逻辑尺寸变化")
                try require(!icon.representations.isEmpty && icon.representations.allSatisfy {
                    $0 is NSBitmapImageRep && $0.pixelsWide <= 32 && $0.pixelsHigh <= 32
                }, "残留大尺寸／延迟生成的图像")
                try require((icon.tiffRepresentation?.count ?? Int.max) < 10_000, "图标传输体积过大")
                let bitmap = icon.representations.first as! NSBitmapImageRep
                let colors = (0..<bitmap.pixelsWide).flatMap { x in
                    (0..<bitmap.pixelsHigh).compactMap { y in bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) }
                }.filter { $0.alphaComponent > 0.5 }
                try require(!colors.isEmpty, "图标被渲染为空白")
                if ["doc", "docx"].contains(template.fileExtension) {
                    try require(colors.contains { $0.blueComponent > $0.redComponent }, "文字文档的蓝色丢失")
                }
                if ["xls", "xlsx", "csv"].contains(template.fileExtension) {
                    try require(colors.contains { $0.greenComponent > $0.redComponent && $0.greenComponent > $0.blueComponent }, "表格的绿色丢失")
                }
                if ["ppt", "pptx"].contains(template.fileExtension) {
                    try require(colors.contains { $0.redComponent > $0.greenComponent && $0.greenComponent > $0.blueComponent }, "演示文稿的橙色丢失")
                }
            }
        }
        try test("相同格式复用图标，大小写不重复生成") {
            try require(DocumentPresentation.icon(for: "TXT") === DocumentPresentation.icon(for: "txt"), "缓存未复用")
        }
        try test("空白处仍保留新建模板、图片及 PDF 二级菜单") {
            let root = menu()
            try require(root.item(withTitle: "新建文件")?.submenu?.items.count == 13, "模板丢失")
            let pdf = root.item(withTitle: "PDF 处理")?.submenu?.items.filter { !$0.isSeparatorItem } ?? []
            try require(pdf.count == 6 && pdf.allSatisfy { $0.submenu == nil && $0.image != nil && $0.target === finder }, "PDF 分类动作丢失")
            try require(root.item(withTitle: "图片处理")?.submenu?.items.count == 3, "图片空白入口丢失")
        }
        try test("大量选区只传菜单标识，完整路径与顺序保留在请求中") {
            let selected = (0..<300).map { root.appendingPathComponent("sample-\($0).txt") }
            let entry = items(menu(selected)).first { finder.request(for: $0)?.action == .copyPaths }!
            try require(entry.representedObject is NSNumber, "菜单仍附带完整选区数据")
            let request = finder.request(for: entry)!
            try require(request.paths == selected.map(\.path) && request.directory == root.path, "选区或输出目录改变")
            try request.validate()
        }
        try test("Finder 代理菜单可按 tag 或标识找回请求，拒绝未知项") {
            let entry = items(menu()).first { finder.request(for: $0)?.action == .createFile }!
            let proxy = NSMenuItem(); proxy.tag = entry.tag
            try require(finder.request(for: proxy)?.argument == "txt", "tag 回调失效")
            proxy.tag = 0; proxy.representedObject = entry.representedObject
            try require(finder.request(for: proxy)?.argument == "txt", "标识回退失效")
            proxy.representedObject = NSNumber(value: -1)
            try require(finder.request(for: proxy) == nil, "未知项未拒绝")
        }
        try test("剪贴板按当前类型更新，文件／文字／图片及剪切不混淆") {
            @MainActor func action(_ kind: ActionKind, _ types: Set<NSPasteboard.PasteboardType>, argument: String? = nil) -> NSMenuItem {
                items(menu(types: types)).first { finder.request(for: $0)?.action == kind && finder.request(for: $0)?.argument == argument }!
            }
            try require(!action(.paste, []).isEnabled, "空剪贴板可粘贴文件")
            try require(action(.paste, [.fileURL]).isEnabled && !action(.pasteAsFile, [.fileURL, .string]).isEnabled, "文件被当作文字")
            try require(action(.pasteAsFile, [.string]).isEnabled && action(.pasteAsFile, [.string], argument: "md").isEnabled, "文字粘贴被禁用")
            try require(action(.pasteAsFile, [.png]).isEnabled && !action(.pasteAsFile, [.png], argument: "md").isEnabled, "图片 Markdown 判断错误")
            try require(action(.paste, [.fileURL, .init("io.github.qingyou.cut")]).title == "将剪切的文件移到此处", "剪切状态丢失")
            try require(action(.paste, [.init("NSFilenamesPboardType")]).isEnabled, "旧文件类型未兼容")
        }
        try test("配置通知刷新缓存，保留收纳偏好和功能开关") {
            config.useSubmenu = true
            if let index = config.menuItems.firstIndex(where: { $0.feature == .newFile }) { config.menuItems[index].enabled = false }
            try ConfigurationStore.save(config, to: configURL); refresh()
            let root = menu()
            try require(root.items.count == 1 && root.items[0].title == "轻右", "配置缓存未刷新")
            try require(root.items[0].submenu?.item(withTitle: "新建文件") == nil, "开关失效")
            try require(root.items[0].submenu?.item(withTitle: "PDF 处理") != nil, "分类绕过父菜单")
        }
        try test("损坏配置显示恢复入口，修正通知后恢复菜单") {
            try Data("broken".utf8).write(to: configURL, options: .atomic); refresh()
            try require(menu().items.first?.isEnabled == false && menu().item(withTitle: "打开轻右设置…") != nil, "缓存吞掉配置错误")
            try ConfigurationStore.save(config, to: configURL); refresh()
            try require(menu().item(withTitle: "轻右") != nil, "修复后未恢复")
        }
        print("\nFinder 菜单测试：\(passed) 项通过，0 项失败。")
    }
}
