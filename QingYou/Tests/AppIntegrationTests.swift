import AppKit
import PDFKit
import UniformTypeIdentifiers
import ServiceManagement
import CoreServices

private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrationResult: SMAppService.Status = .enabled
    var failure: Error?
    var registrations = 0
    var removals = 0
    func register() throws {
        registrations += 1
        if let failure { throw failure }
        status = registrationResult
    }
    func unregister() throws {
        removals += 1
        if let failure { throw failure }
        status = .notRegistered
    }
}

private struct Failure: Error, CustomStringConvertible { let description: String }
private func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw Failure(description: message) }
}
private func waitFor(_ condition: () -> Bool) throws {
    let limit = Date().addingTimeInterval(10)
    while !condition() && Date() < limit {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    try require(condition(), "等待后台任务超时")
}

@main
struct AppIntegrationTests {
    static func main() throws {
        let fm = FileManager.default
        let defaultsDomain = "io.github.qingyou.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: defaultsDomain)!
        defer { testDefaults.removePersistentDomain(forName: defaultsDomain) }
        let root = fm.temporaryDirectory.appendingPathComponent("QingYou-integration-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        // 测试注入独立存储，既不写用户配置，也不通知正在运行的 Finder。
        let store = AppStore(configurationURL: root.appendingPathComponent("settings.json"),
                             historyURL: root.appendingPathComponent("history.json"), integratesWithFinder: false, pasteboard: NSPasteboard.withUniqueName())
        var passed = 0
        func test(_ title: String, _ body: () throws -> Void) throws {
            try body(); passed += 1; print("✓ \(title)")
        }
        let first = root.appendingPathComponent("文件 01.txt")
        let second = root.appendingPathComponent("文件 02.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        try test("拖放异步解码全部 URL 后按原顺序呈现且不修改文件") {
            let providers = [first, second].map { url -> NSItemProvider in
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
                    DispatchQueue.global().async { completion(url.dataRepresentation, nil) }
                    return nil
                }
                return provider
            }
            try require(store.receiveDrop(providers), "未接受 URL 拖放")
            try waitFor { !store.receivingDrop }
            try require(store.stagedFiles == [first, second], "拖放顺序或数量不正确")
            try require(store.selectedPage == .tools, "未切换到工具箱")
            try require(fm.fileExists(atPath: first.path) && fm.fileExists(atPath: second.path), "拖放改变了文件")
        }
        try test("普通文字拖放不会替换已选文件") {
            let previous = store.stagedFiles
            try require(!store.receiveDrop([NSItemProvider(object: "hello" as NSString)]), "错误接受纯文字")
            try require(store.stagedFiles == previous && !store.receivingDrop, "选择状态被修改")
        }
        try test("后台重命名及撤销同步更新工具箱中的文件路径") {
            var options = RenameOptions(); options.prefix = "完成_"
            let plan = try RenameEngine.plan([first, second], options: options)
            store.applyRename(plan)
            try waitFor { store.pendingTasks == 0 }
            try require(store.stagedFiles == plan.map(\.destination), "改名后仍使用旧路径")
            try require(store.undoMappings.count == 2, "缺少撤销映射")
            store.undoLastMoveOrRename()
            try waitFor { store.pendingTasks == 0 }
            try require(store.stagedFiles == [first, second] && store.undoMappings.isEmpty, "撤销未恢复选中路径")
            let text = try String(contentsOf: first, encoding: .utf8)
            try require(text == "first", "文件内容发生改变")
        }
        try test("串行任务完成后清空忙碌状态并持久化最新记录") {
            store.run("第一项") { TaskOutcome(detail: "first") }
            store.run("第二项") { TaskOutcome(detail: "second") }
            try require(store.pendingTasks == 2, "排队数量不正确")
            try waitFor { store.pendingTasks == 0 }
            try require(store.currentTask.isEmpty, "完成后仍显示处理中")
            try require(Array(store.activities.prefix(2)).map(\.title) == ["第二项", "第一项"], "执行或记录顺序错误")
            let persisted = try JSONDecoder().decode([ActivityEntry].self, from: Data(contentsOf: root.appendingPathComponent("history.json")))
            try require(persisted.first?.title == "第二项", "记录未保存")
        }
        try test("复制路径与剪切更新剪贴板但不产生成功提示") {
            var notifications = 0
            store.showFeedback = { _ in notifications += 1 }
            store.latestFeedback = nil
            for action in [ActionKind.copyPaths, .copyNames, .copyShellPaths, .copyMarkdown] {
                store.perform(.init(action: action, paths: [first.path]))
                try require(store.pasteboard.string(forType: .string)?.isEmpty == false, "未写入剪贴板")
            }
            store.perform(.init(action: .cut, paths: [first.path]))
            try require(store.pasteboard.string(forType: store.cutType) == "1", "缺少剪切标记")
            try require(notifications == 0 && store.latestFeedback == nil, "静默操作触发了提示")
            store.pasteboard.releaseGlobally()
        }
        try test("新建文件无需命名确认，连续创建保留两份且不弹成功提示") {
            let directory = root.appendingPathComponent("quick-create")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            var notifications = 0
            store.showFeedback = { _ in notifications += 1 }
            store.latestFeedback = nil
            for _ in 0..<2 {
                store.perform(.init(action: .createFile, directory: directory.path, argument: "md"))
                try waitFor { store.pendingTasks == 0 }
            }
            try require(fm.fileExists(atPath: directory.appendingPathComponent("未命名.md").path), "未创建文件")
            try require(fm.fileExists(atPath: directory.appendingPathComponent("未命名 2.md").path), "同名文件未保留")
            try require(notifications == 0 && store.latestFeedback == nil, "新建文件不应重复提示成功")
        }
        try test("登录项只在明确切换时注册，重复开启不重复提交") {
            let service = FakeLoginItemService()
            let controller = LoginItemController(service: service, defaults: testDefaults)
            try require(!controller.isEnabled && service.registrations == 0, "初始化不应启用登录项")
            controller.setEnabled(true)
            controller.setEnabled(true)
            try require(controller.isEnabled && service.registrations == 1, "未启用或重复注册")
            controller.setEnabled(false)
            try require(!controller.isEnabled && service.removals == 1, "关闭未注销")
            service.status = .notFound
            controller.refresh()
            try require(!controller.isEnabled, "未知登录项不应显示已开启")
            controller.setEnabled(true)
            try require(controller.isEnabled && service.registrations == 2, "未允许首次发现的登录项注册")
        }
        try test("登录项待批准时不冒充已启用，并支持取消申请") {
            let service = FakeLoginItemService()
            service.registrationResult = .requiresApproval
            var openedSettings = 0
            let controller = LoginItemController(service: service, defaults: testDefaults, openSettings: { openedSettings += 1 })
            controller.setEnabled(true)
            try require(controller.needsApproval && !controller.isEnabled, "待批准状态显示错误")
            controller.setEnabled(true)
            try require(openedSettings == 1 && service.registrations == 1, "应引导系统设置而非重复申请")
            controller.setEnabled(false)
            try require(!controller.needsApproval && service.removals == 1, "未取消申请")
        }
        try test("登录项失败恢复实际状态，并能同步系统中的撤销") {
            let service = FakeLoginItemService()
            let controller = LoginItemController(service: service, defaults: testDefaults)
            service.failure = Failure(description: "模拟系统拒绝")
            controller.setEnabled(true)
            try require(!controller.isEnabled && controller.errorMessage != nil, "注册失败仍显示已启用")
            service.failure = nil
            controller.setEnabled(true)
            service.failure = Failure(description: "模拟注销失败")
            controller.setEnabled(false)
            try require(controller.isEnabled && controller.errorMessage != nil, "注销失败丢失真实状态")
            service.status = .requiresApproval
            controller.refresh()
            try require(!controller.isEnabled && controller.needsApproval, "未同步系统撤销")
        }
        try test("仅系统登录事件采用静默启动，普通启动仍显示主窗口") {
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
                eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            try require(!LoginItemController.isLoginLaunch(nil), "空事件错误识别为登录启动")
            try require(!LoginItemController.isLoginLaunch(event), "普通启动错误识别为登录启动")
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
            try require(LoginItemController.isLoginLaunch(event), "未识别登录事件")
        }
        try test("默认申请仅一次，手动关闭和失败不会在下次启动时被覆盖") {
            testDefaults.removePersistentDomain(forName: defaultsDomain)
            let service = FakeLoginItemService()
            let controller = LoginItemController(service: service, defaults: testDefaults)
            controller.applyDefaultIfNeeded()
            try require(controller.isEnabled && service.registrations == 1, "首次未默认申请")
            controller.setEnabled(false)
            let reopened = LoginItemController(service: service, defaults: testDefaults)
            reopened.applyDefaultIfNeeded()
            try require(!reopened.isEnabled && service.registrations == 1, "覆盖了用户关闭选择")
            testDefaults.removePersistentDomain(forName: defaultsDomain)
            service.failure = Failure(description: "模拟注册失败")
            reopened.applyDefaultIfNeeded()
            reopened.applyDefaultIfNeeded()
            try require(service.registrations == 2, "失败后反复申请")
        }
        try test("默认启动申请不打断已被系统撤销或待批准的登录项") {
            testDefaults.removePersistentDomain(forName: defaultsDomain)
            let service = FakeLoginItemService()
            service.status = .requiresApproval
            var prompts = 0
            let controller = LoginItemController(service: service, defaults: testDefaults, openSettings: { prompts += 1 })
            controller.applyDefaultIfNeeded()
            try require(service.registrations == 0 && prompts == 0 && controller.needsApproval, "启动时重复申请或弹出设置")
        }
        try test("Finder 名称编辑只接受单个明确匹配的文件 URL") {
            try require(FinderInlineRename.isExactSelection([first], target: first), "目标选择未被接受")
            try require(!FinderInlineRename.isExactSelection([], target: first), "接受空选择")
            try require(!FinderInlineRename.isExactSelection([nil], target: first), "接受未知选择")
            try require(!FinderInlineRename.isExactSelection([first, second], target: first), "接受多选")
            try require(!FinderInlineRename.isExactSelection([second], target: first), "接受另一文件")
            let sameNameElsewhere = root.appendingPathComponent("elsewhere").appendingPathComponent(first.lastPathComponent)
            try require(!FinderInlineRename.isExactSelection([sameNameElsewhere], target: first), "只核对文件名而未核对目录")
        }
        try test("新建改名偏好缺省开启，关闭后保存并重新读取") {
            var configuration = Configuration()
            try require(configuration.editsNameAfterCreation, "缺省未开启")
            configuration.renameAfterCreation = false
            let data = try JSONEncoder().encode(configuration)
            let restored = try JSONDecoder().decode(Configuration.self, from: data)
            try require(!restored.editsNameAfterCreation, "未保留关闭偏好")
        }
        try test("终端入口使用系统服务和纯路径，不改变用户剪贴板或拼接命令") {
            let directory = root.appendingPathComponent("目录 空格 '$()")
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            var called = 0
            try TerminalService.open(directory, perform: { title, board in
                called += 1
                return !title.isEmpty && board.string(forType: .string) == directory.path
            })
            try require(called == 1, "未使用服务或重复调用")
            do {
                try TerminalService.open(directory, perform: { _, _ in false })
                throw Failure(description: "服务失败未报告")
            } catch is FileOperationError { }
        }
        try test("Finder 文件地址兼容 URL、字符串 URL 和绝对路径") {
            try require(FinderInlineRename.fileURL(first.absoluteString) == first, "字符串 URL 未解析")
            try require(FinderInlineRename.fileURL(first.path) == first, "绝对路径未解析")
            try require(FinderInlineRename.fileURL(URL(string: "https://example.com")!) == nil, "接受了远程 URL")
            try require(FinderInlineRename.fileURL("文件 01.txt") == nil, "只靠名称推断了完整路径")
        }
        try test("Finder 图标视图回退必须同时匹配单选名称和完整路径") {
            let names: Set<String> = [first.lastPathComponent]
            try require(FinderInlineRename.matchesPathBar(selectionCount: 1, names: names, path: first, target: first), "准确的单选未通过")
            let otherFolder = root.appendingPathComponent("其他目录").appendingPathComponent(first.lastPathComponent)
            try require(!FinderInlineRename.matchesPathBar(selectionCount: 1, names: names, path: otherFolder, target: first), "其他目录中的同名文件被接受")
            try require(!FinderInlineRename.matchesPathBar(selectionCount: 2, names: names, path: first, target: first), "多选被接受")
            try require(!FinderInlineRename.matchesPathBar(selectionCount: 1, names: [second.lastPathComponent], path: first, target: first), "名称不匹配被接受")
            try require(!FinderInlineRename.matchesPathBar(selectionCount: 1, names: names, path: root, target: first), "祖先目录被当作文件地址")
        }
        try test("PDF 菜单请求进入独立工作台，不立即修改文件") {
            let a = root.appendingPathComponent("a.pdf"), b = root.appendingPathComponent("b.pdf")
            try Data("fixture".utf8).write(to: a); try Data("fixture".utf8).write(to: b)
            var modes: [PDFWorkspaceMode] = []
            var directories: [URL] = []
            let originalPicker = store.selectPDFInputs
            defer { store.selectPDFInputs = originalPicker }
            var pickerCalls = 0
            store.selectPDFInputs = { _, _ in pickerCalls += 1; return [] }
            store.presentPDF = { mode, urls, directory in
                modes.append(mode)
                directories.append(directory)
            }
            store.perform(.init(action: .pdfSplit, paths: [a.path], directory: root.path))
            store.perform(.init(action: .pdfMerge, paths: [a.path,b.path], directory: root.path))
            try require(modes == [.split,.merge] && store.pendingTasks == 0, "未进入工作台或提前导出")
            try require(directories.allSatisfy { $0.path == root.path }, "输出目录不正确")
            try require(pickerCalls == 0, "有效的 Finder 选区不应再次选择文件")
        }
        try test("空白处启动 PDF 合并先选择文件，并保留当前目录作为输出位置") {
            let sources = root.appendingPathComponent("其他来源")
            try fm.createDirectory(at: sources, withIntermediateDirectories: true)
            let a = sources.appendingPathComponent("选择一.pdf"), b = sources.appendingPathComponent("选择二.pdf")
            try Data("fixture".utf8).write(to: a); try Data("fixture".utf8).write(to: b)
            let originalPicker = store.selectPDFInputs
            let originalPresenter = store.presentPDF
            defer { store.selectPDFInputs = originalPicker; store.presentPDF = originalPresenter }
            var presented = false
            store.selectPDFInputs = { mode, directory in
                if mode == .merge && directory?.path == root.path { return [b, a] }
                return []
            }
            store.presentPDF = { mode, urls, directory in
                presented = mode == .merge && urls == [b, a] && directory.path == root.path
            }
            let filesBefore = try fm.contentsOfDirectory(atPath: root.path)
            store.perform(.init(action: .pdfMerge, directory: root.path))
            try require(presented && store.pendingTasks == 0, "文件选择结果、顺序或输出目录未带入工作台")
            let filesAfter = try fm.contentsOfDirectory(atPath: root.path)
            try require(Set(filesAfter) == Set(filesBefore), "选择文件时提前生成了结果")
        }
        try test("PDF 数量或类型不匹配时重新选择，不擅自使用部分选区") {
            let a = root.appendingPathComponent("a.pdf"), b = root.appendingPathComponent("b.pdf")
            let originalPicker = store.selectPDFInputs
            let originalPresenter = store.presentPDF
            defer { store.selectPDFInputs = originalPicker; store.presentPDF = originalPresenter }
            for (action, selection, mode, picked) in [
                (ActionKind.pdfMerge, [a], PDFWorkspaceMode.merge, [a, b]),
                (.pdfSplit, [a, b], .split, [b]),
                (.pdfSplit, [first], .split, [a])
            ] {
                var pickerCalls = 0
                var presented: [URL] = []
                store.selectPDFInputs = { requestedMode, _ in
                    pickerCalls += 1
                    return requestedMode == mode ? picked : []
                }
                store.presentPDF = { _, urls, _ in presented = urls }
                store.perform(.init(action: action, paths: selection.map(\.path), directory: root.path))
                try require(pickerCalls == 1 && presented == picked, "错误选区没有进入对应的文件选择流程")
            }
        }
        try test("取消 PDF 选择保持静默，不打开工作台或生成结果") {
            let originalPicker = store.selectPDFInputs
            let originalPresenter = store.presentPDF
            defer { store.selectPDFInputs = originalPicker; store.presentPDF = originalPresenter }
            var presentations = 0
            store.presentPDF = { _, _, _ in presentations += 1 }
            store.selectPDFInputs = { _, _ in [] }
            let activityCount = store.activities.count
            let previousFeedback = store.latestFeedback?.id
            store.perform(.init(action: .pdfSplit, directory: root.path))
            store.perform(.init(action: .pdfMerge, directory: root.path))
            try require(presentations == 0 && store.activities.count == activityCount
                        && store.latestFeedback?.id == previousFeedback, "取消选择产生了任务或反馈")
            try require(store.pendingTasks == 0, "取消选择后仍产生文件任务")
        }
        func workspacePDF(_ name: String, count: Int) throws -> URL {
            let document = PDFDocument()
            let image = NSImage(size: NSSize(width: 100, height: 140))
            image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 100, height: 140).fill(); image.unlockFocus()
            for _ in 0..<count { document.insert(PDFPage(image: image)!, at: document.pageCount) }
            let url = root.appendingPathComponent(name)
            try document.dataRepresentation()!.write(to: url)
            return url
        }
        try test("PDF 合并工作台的排序更新预览并保持导出顺序") {
            let a = try workspacePDF("workspace-a.pdf", count: 1)
            let b = try workspacePDF("workspace-b.pdf", count: 2)
            let model = PDFWorkspaceModel(mode: .merge, urls: [a,b], directory: root)
            try waitFor { !model.isLoading && !model.isUpdatingPreview }
            try require(model.canExport && model.resultPreview?.pageCount == 3, "初始预览未完成")
            model.move(model.files[0].id, to: 2)
            try waitFor { !model.isUpdatingPreview }
            model.move(model.files[0].id, to: -1) // 无效插入位置不能改变顺序
            try require(model.files.map(\.url) == [b,a] && model.resultPreview?.pageCount == 3, "排序或预览未同步")
            var outputs: [URL] = []
            var busy: [Bool] = []
            model.onBusy = { busy.append($0) }
            model.onExport = { outputs = $0 }
            model.export()
            try waitFor { !model.isExporting }
            try require(outputs.count == 1 && busy == [true,false], "导出结果或忙碌状态不正确")
        }
        try test("PDF 拆分工作台拒绝错误范围，修正后可以导出") {
            let source = try workspacePDF("workspace-split.pdf", count: 3)
            let model = PDFWorkspaceModel(mode: .split, urls: [source], directory: root)
            try waitFor { !model.isLoading && !model.isUpdatingPreview }
            model.parts[0].pages = "99"; model.schedulePreview()
            try waitFor { !model.isUpdatingPreview }
            try require(!model.canExport && model.message != nil && model.resultPreview == nil, "错误范围仍可导出")
            model.parts = [.init(pages: "1-2"), .init(pages: "3", name: "末页")]
            model.selectedPart = model.parts[0].id
            model.schedulePreview()
            try waitFor { !model.isUpdatingPreview }
            try require(model.canExport && model.resultPreview?.pageCount == 2, "修正范围后未恢复预览")
            var outputs: [URL] = []
            model.onExport = { outputs = $0 }
            model.export()
            try waitFor { !model.isExporting }
            try require(outputs.count == 2 && PDFDocument(url: outputs[1])?.pageCount == 1, "拆分工作台未正确导出")
        }
        print("\n应用集成测试：\(passed) 项通过，0 项失败。")
    }
}
