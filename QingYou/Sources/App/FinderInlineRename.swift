import AppKit
import ApplicationServices

/// Finder 没有公开的“进入名称编辑”接口。使用辅助功能点击它自己的改名菜单，
/// 只有选中的完整 URL 和新建文件一致时才执行，绝不向未知窗口发送回车。
final class FinderInlineRename {
    private let worker = DispatchQueue(label: "io.github.qingyou.finder-rename", qos: .userInitiated)
    private var requestID = UUID() // 只在主线程访问
    private var diagnosedToken: UUID? // 仅在 worker 队列访问

    func cancel() { requestID = UUID() }

    func begin(_ url: URL) {
        cancel()
        guard AXIsProcessTrusted(), let identity = try? FileIdentity.read(url) else { return }
        let token = requestID
        let deadline = Date().addingTimeInterval(2)
        attempt(url, identity: identity, token: token, deadline: deadline, sawFinder: false)
    }

    private func attempt(_ url: URL, identity: FileIdentity, token: UUID, deadline: Date, sawFinder: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.requestID == token, Date() < deadline, AXIsProcessTrusted() else { return }
            guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == "com.apple.finder" else {
                // Finder 出现前可短暂等待；用户切走后立即放弃，不抢回焦点。
                if !sawFinder { self.attempt(url, identity: identity, token: token, deadline: deadline, sawFinder: false) }
                return
            }
            let pid = front.processIdentifier
            self.worker.async { [weak self] in
                guard let self else { return }
                let finder = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(finder, 0.1)
                let canContinue = {
                    DispatchQueue.main.sync {
                        self.requestID == token && Date() < deadline
                            && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                    }
                }
                var performed = false
                if UserDefaults.standard.bool(forKey: "debugFinderRename"), self.diagnosedToken != token {
                    self.diagnosedToken = token
                    Self.saveDiagnostics(finder)
                }
                if canContinue(), Self.selectionMatches(finder, url: url, deadline: deadline),
                   let menu = Self.renameMenuItem(finder, deadline: deadline),
                   canContinue(), (try? FileIdentity.read(url)) == identity,
                   Self.selectionMatches(finder, url: url, deadline: deadline), canContinue() {
                    performed = AXUIElementPerformAction(menu, kAXPressAction as CFString) == .success
                }
                DispatchQueue.main.async {
                    if !performed { self.attempt(url, identity: identity, token: token, deadline: deadline, sawFinder: true) }
                }
            }
        }
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ object: CFTypeRef?) -> AXUIElement? {
        guard let object, CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return (object as! AXUIElement)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    // URL 不可读取、多选、焦点在输入框内时，都让用户自己按回车。
    static func isExactSelection(_ candidates: [URL?], target: URL) -> Bool {
        candidates.count == 1 && candidates[0]?.isFileURL == true
            && candidates[0]?.standardizedFileURL == target.standardizedFileURL
    }

    static func matchesPathBar(selectionCount: Int, names: Set<String>, path: URL?, target: URL) -> Bool {
        selectionCount == 1 && names.contains(target.lastPathComponent)
            && isExactSelection([path], target: target)
    }

    private static func selectionMatches(_ finder: AXUIElement, url: URL, deadline: Date) -> Bool {
        guard let window = element(value(finder, kAXFocusedWindowAttribute)),
              let focused = element(value(finder, kAXFocusedUIElementAttribute)) else { return false }
        let role = value(focused, kAXRoleAttribute) as? String
        guard role != kAXTextFieldRole && role != kAXTextAreaRole && role != kAXComboBoxRole else { return false }
        // 从实际焦点向上找最近的选择容器，不把侧边栏选中目录当作文件选择。
        var current: AXUIElement? = focused
        for _ in 0..<12 {
            guard let node = current, Date() < deadline else { return false }
            for attribute in [kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute] {
                if let selected = value(node, attribute) as? [AXUIElement], !selected.isEmpty {
                    let urls = selected.map { selectedURL($0, deadline: deadline) }
                    if isExactSelection(urls, target: url) { return true }
                    // 图标视图有时不暴露文件 URL。只有单选名称和路径栏的完整
                    // 文件地址同时一致时才使用路径栏，不能仅凭同名就触发改名。
                    guard selected.count == 1, urls[0] == nil else { return false }
                    return matchesPathBar(selectionCount: selected.count,
                                          names: selectedNames(selected[0], deadline: deadline),
                                          path: pathBarURL(window, deadline: deadline), target: url)
                }
            }
            if CFEqual(node, window) { break }
            current = element(value(node, kAXParentAttribute))
        }
        return false
    }

    private static func selectedNames(_ selected: AXUIElement, deadline: Date) -> Set<String> {
        var queue = [selected], index = 0
        var names = Set<String>()
        while index < queue.count && index < 40 && Date() < deadline {
            let node = queue[index]; index += 1
            for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
                if let text = value(node, key) as? String { names.insert(text) }
            }
            queue.append(contentsOf: children(node).prefix(40 - min(queue.count, 40)))
        }
        return names
    }

    private static func pathBarURL(_ window: AXUIElement, deadline: Date) -> URL? {
        var queue = [window], index = 0
        while index < queue.count && index < 100 && Date() < deadline {
            let node = queue[index]; index += 1
            if value(node, kAXRoleAttribute) as? String == kAXListRole,
               let description = value(node, kAXDescriptionAttribute) as? String,
               ["path", "路径", "路徑"].contains(description.lowercased()) {
                // 最后一段是当前选中项；祖先目录不能替代完整文件地址。
                guard let last = children(node).last else { return nil }
                return fileURL(value(last, kAXURLAttribute))
            }
            queue.append(contentsOf: children(node).prefix(100 - min(queue.count, 100)))
        }
        return nil
    }

    private static func selectedURL(_ selected: AXUIElement, deadline: Date) -> URL? {
        var queue = [selected]
        var index = 0
        var urls = Set<URL>()
        while index < queue.count && index < 40 && Date() < deadline {
            let node = queue[index]; index += 1
            for attribute in [kAXURLAttribute, kAXFilenameAttribute, kAXDocumentAttribute] {
                if let url = fileURL(value(node, attribute)) { urls.insert(url.standardizedFileURL) }
            }
            queue.append(contentsOf: children(node).prefix(40 - min(queue.count, 40)))
        }
        return urls.count == 1 ? urls.first : nil
    }

    static func fileURL(_ value: Any?) -> URL? {
        if let url = value as? URL, url.isFileURL { return url }
        if let text = value as? String {
            if text.hasPrefix("file:"), let url = URL(string: text), url.isFileURL { return url }
            if text.hasPrefix("/") { return URL(fileURLWithPath: text) }
        }
        return nil
    }

    // 开发诊断只在显式启用时记录，正常使用不会保存 Finder 界面内容。
    private static func saveDiagnostics(_ finder: AXUIElement) {
        guard let window = element(value(finder, kAXFocusedWindowAttribute)) else { return }
        var queue = [window]
        var result: [[String: String]] = []
        var index = 0
        while index < queue.count && index < 150 {
            let node = queue[index]; index += 1
            var fields: [String: String] = ["node": "\(index)"]
            for key in [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXURLAttribute, kAXFilenameAttribute, kAXDocumentAttribute, kAXSelectedAttribute] {
                if let v = value(node, key) { fields[key] = String(describing: v) }
            }
            for key in [kAXSelectedChildrenAttribute, kAXSelectedRowsAttribute] {
                if let v = value(node, key) as? [AXUIElement] { fields[key] = "count=\(v.count)" }
            }
            result.append(fields)
            queue.append(contentsOf: children(node).prefix(150 - min(queue.count, 150)))
        }
        if let focused = element(value(finder, kAXFocusedUIElementAttribute)) {
            result.insert(["focusedRole": value(focused, kAXRoleAttribute).map { String(describing: $0) } ?? "nil"], at: 0)
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: Product.supportDirectory.appendingPathComponent("finder-rename-debug.json"), options: .atomic)
        }
    }

    private static func renameMenuItem(_ finder: AXUIElement, deadline: Date) -> AXUIElement? {
        guard let menuBar = element(value(finder, kAXMenuBarAttribute)) else { return nil }
        let fileTitles: Set<String> = ["File", "文件", "檔案"]
        let renameTitles: Set<String> = ["Rename", "重命名", "重新命名"]
        guard let fileMenu = children(menuBar).first(where: { fileTitles.contains(value($0, kAXTitleAttribute) as? String ?? "") }) else { return nil }
        var queue = children(fileMenu)
        var index = 0
        while index < queue.count && index < 100 && Date() < deadline {
            let node = queue[index]; index += 1
            if renameTitles.contains(value(node, kAXTitleAttribute) as? String ?? ""),
               value(node, kAXEnabledAttribute) as? Bool == true { return node }
            queue.append(contentsOf: children(node).prefix(100 - min(queue.count, 100)))
        }
        return nil
    }
}
