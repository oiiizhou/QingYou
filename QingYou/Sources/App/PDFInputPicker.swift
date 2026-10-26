import AppKit
import UniformTypeIdentifiers

/// Finder 空白处启动时，沿用系统文件选择器，取消不会产生任务或提示。
enum PDFInputPicker {
    static func choose(_ mode: PDFWorkspaceMode, in directory: URL?) -> [URL] {
        choose(title: mode.title, message: mode == .merge
            ? "选择至少两份 PDF，稍后可以调整合并顺序。"
            : "选择一份 PDF，再设置需要拆分的页码范围。", multiple: mode == .merge, directory: directory)
    }
    static func chooseSingle(title: String, in directory: URL?) -> [URL] {
        choose(title: title, message: "选择需要处理的 PDF，稍后可以预览结果。", multiple: false, directory: directory)
    }
    private static func choose(title: String, message: String, multiple: Bool, directory: URL?) -> [URL] {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "继续"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = multiple
        panel.allowedContentTypes = [.pdf]
        panel.allowsOtherFileTypes = false
        panel.directoryURL = directory
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls : []
    }
}
