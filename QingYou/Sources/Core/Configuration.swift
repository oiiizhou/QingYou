import Foundation
import Darwin

enum Product {
    static let name = "轻右"
    static let version = "0.2.1"
    static let bundleID = "io.github.qingyou.app"
    static let extensionID = "io.github.qingyou.app.finder"
    static let configurationChanged = "io.github.qingyou.configurationChanged"
    static let finderLaunchArgument = "--finder-request"

    // 扩展中的 NSHomeDirectory 指向沙盒；配置目录需要使用真实用户目录。
    static var userHome: URL {
        if let entry = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    static var supportDirectory: URL {
        userHome.appendingPathComponent("Library/Application Support/QingYou", isDirectory: true)
    }
    static var configurationURL: URL { supportDirectory.appendingPathComponent("settings.json") }
    static var templateDirectory: URL { supportDirectory.appendingPathComponent("Templates", isDirectory: true) }
    static var requestDirectory: URL {
        userHome.appendingPathComponent(
            "Library/Containers/\(extensionID)/Data/Library/Application Support/QingYou/Requests",
            isDirectory: true
        )
    }
}

enum MenuFeature: String, Codable, CaseIterable, Identifiable {
    case newFile, clipboard, transfer, paths, openWith, favorites, rename, visibility, folderIcon
    case image, pdf, checksum, project
    var id: String { rawValue }
    // 保留旧枚举用于读取历史配置；精简后的菜单与设置只展示这些功能。
    static let available: [MenuFeature] = [.newFile, .clipboard, .paths, .transfer, .openWith, .visibility, .folderIcon, .image, .pdf]
    var title: String {
        switch self {
        case .newFile: return "新建文件"
        case .clipboard: return "剪切与粘贴"
        case .transfer: return "复制 / 移动到"
        case .paths: return "拷贝路径"
        case .openWith: return "在此处打开终端"
        case .favorites: return "常用目录"
        case .rename: return "批量重命名"
        case .visibility: return "隐藏与显示"
        case .folderIcon: return "文件夹图标"
        case .image: return "图片处理"
        case .pdf: return "PDF 处理"
        case .checksum: return "SHA-256 校验"
        case .project: return "创建项目目录"
        }
    }
    var symbol: String {
        switch self {
        case .newFile: return "doc.badge.plus"
        case .clipboard: return "scissors"
        case .transfer: return "folder.badge.arrow.forward"
        case .paths: return "link"
        case .openWith: return "terminal"
        case .favorites: return "star"
        case .rename: return "character.cursor.ibeam"
        case .visibility: return "eye"
        case .folderIcon: return "paintpalette"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .checksum: return "number"
        case .project: return "folder.badge.plus"
        }
    }
    var detail: String {
        switch self {
        case .newFile: return "空白文档、代码文件与自定义模板"
        case .clipboard: return "先标记文件，粘贴时再完成移动"
        case .transfer: return "选择目标文件夹，重名时保留两份或跳过"
        case .paths: return "直接拷贝完整路径，多选时每行一个"
        case .openWith: return "在当前文件夹打开终端"
        case .favorites: return "常用文件夹随手打开"
        case .rename: return "替换文字、添加前后缀和编号，执行前预览"
        case .visibility: return "切换选中文件的隐藏属性"
        case .folderIcon: return "用自己的图片设置图标，随时恢复"
        case .image: return "像素与质量调整、图片信息、图片转 PDF、离线 OCR"
        case .pdf: return "合并、拆分、压缩、页面整理、图片与文字导出"
        case .checksum: return "流式计算校验值，大文件不必一次读入内存"
        case .project: return "创建带 README 的论文或代码目录"
        }
    }
}

struct MenuItemSetting: Codable, Identifiable {
    var feature: MenuFeature
    var enabled: Bool
    var id: String { feature.rawValue }
}
struct FileTemplate: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var fileExtension: String
    var resource: String?
    var content: String?
    var importedFilename: String?
    var enabled: Bool = true
    var menuTitle: String { "\(name)（.\(fileExtension.lowercased())）" }
    static let defaults: [FileTemplate] = [
        .init(id: "txt", name: "文本文档", fileExtension: "txt", content: ""),
        .init(id: "md", name: "Markdown 文档", fileExtension: "md", content: "# {{name}}\n\n"),
        .init(id: "docx", name: "文字文档", fileExtension: "docx", resource: "Blank.docx"),
        .init(id: "doc", name: "文字文档", fileExtension: "doc", resource: "Blank.doc"),
        .init(id: "xlsx", name: "电子表格", fileExtension: "xlsx", resource: "Blank.xlsx"),
        .init(id: "xls", name: "电子表格", fileExtension: "xls", resource: "Blank.xls"),
        .init(id: "pptx", name: "演示文稿", fileExtension: "pptx", resource: "Blank.pptx"),
        .init(id: "ppt", name: "演示文稿", fileExtension: "ppt", resource: "Blank.ppt"),
        .init(id: "py", name: "Python 脚本", fileExtension: "py", content: "#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n\n\ndef main():\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n"),
        .init(id: "json", name: "JSON 文档", fileExtension: "json", content: "{}\n"),
        .init(id: "yaml", name: "YAML 文档", fileExtension: "yaml", content: "# {{name}}\n"),
        .init(id: "csv", name: "CSV 表格", fileExtension: "csv", content: ""),
        .init(id: "sh", name: "Shell 脚本", fileExtension: "sh", content: "#!/bin/zsh\nset -euo pipefail\n\n")
    ]
}
struct Favorite: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var path: String
}
struct OpenApplication: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bundleIdentifier: String
    var path: String
}
enum CollisionPolicy: String, Codable, CaseIterable, Identifiable {
    case keepBoth, skip
    var id: String { rawValue }
    var title: String { self == .keepBoth ? "保留两份" : "跳过重名文件" }
}
struct Configuration: Codable {
    var schemaVersion = 1
    var menuItems = MenuFeature.available.map { MenuItemSetting(feature: $0, enabled: true) }
    var templates = FileTemplate.defaults
    var favorites: [Favorite] = [
        .init(name: "下载", path: Product.userHome.appendingPathComponent("Downloads").path),
        .init(name: "桌面", path: Product.userHome.appendingPathComponent("Desktop").path),
        .init(name: "文稿", path: Product.userHome.appendingPathComponent("Documents").path)
    ]
    var applications: [OpenApplication] = []
    var monitoredPaths = [Product.userHome.path, "/Volumes"]
    var collisionPolicy: CollisionPolicy = .keepBoth
    var useSubmenu = false
    var openAfterCreation = false
    // 可选字段使 0.1 的配置无需重置就能升级；缺省开启轻量完成提示。
    var completionFeedback: Bool?
    var showsCompletionFeedback: Bool { completionFeedback ?? true }
    var renameAfterCreation: Bool?
    var editsNameAfterCreation: Bool { renameAfterCreation ?? true }
    var preferWPS: Bool?
    var prefersWPS: Bool { preferWPS ?? true }
}
enum ConfigurationStore {
    static func load(from url: URL = Product.configurationURL) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else { return Configuration() }
        let data = try Data(contentsOf: url)
        guard data.count <= 2_000_000 else { throw FileOperationError.message("配置文件过大，无法加载。") }
        var configuration = try JSONDecoder().decode(Configuration.self, from: data)
        guard configuration.schemaVersion == 1 else {
            throw FileOperationError.message("配置来自较新的轻右版本，请先更新软件。")
        }
        configuration.menuItems.removeAll { !MenuFeature.available.contains($0.feature) }
        // 保留原有顺序，新功能附加到末尾。
        let existing = Set(configuration.menuItems.map(\.feature))
        for feature in MenuFeature.available where !existing.contains(feature) {
            configuration.menuItems.append(.init(feature: feature, enabled: true))
        }
        // 只补充新增格式，保留用户已有模板的内容和开关；旧的默认名称统一排版。
        let previousNames = ["md": "Markdown", "docx": "Word 文档", "xlsx": "Excel 表格",
                             "pptx": "PowerPoint 演示文稿", "py": "Python", "json": "JSON", "yaml": "YAML", "csv": "CSV"]
        for template in FileTemplate.defaults {
            if let index = configuration.templates.firstIndex(where: { $0.id == template.id }) {
                if configuration.templates[index].importedFilename == nil,
                   configuration.templates[index].name == previousNames[template.id] {
                    configuration.templates[index].name = template.name
                }
            } else if ["doc", "xls", "ppt"].contains(template.id) {
                let sibling = ["doc": "docx", "xls": "xlsx", "ppt": "pptx"][template.id]!
                if let index = configuration.templates.firstIndex(where: { $0.id == sibling }) {
                    configuration.templates.insert(template, at: index + 1)
                } else { configuration.templates.append(template) }
            }
        }
        return configuration
    }
    static func save(_ configuration: Configuration, to url: URL = Product.configurationURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}
