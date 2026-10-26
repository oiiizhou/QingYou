import Foundation

enum FileOperationError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}
struct FileMapping: Codable, Equatable {
    let source: URL
    let destination: URL
}
struct FileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    static func read(_ url: URL) throws -> FileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw FileOperationError.message("无法确认文件身份：\(url.path)")
        }
        return .init(device: device.uint64Value, inode: inode.uint64Value)
    }
}
struct TransferResult {
    var completed: [FileMapping] = []
    var skipped: [URL] = []
    var failures: [String] = []
}
enum FileOperations {
    static func validateFilename(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0"),
              name.utf8.count <= 255 else {
            throw FileOperationError.message("文件名不能为空，不能包含 / 或空字符，且不能超过 255 字节。")
        }
    }
    static func requireDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileOperationError.message("目录不存在：\(url.path)")
        }
    }
    static func exists(_ url: URL) -> Bool {
        // fileExists 对断开的符号链接返回 false；占用检查必须包含这种情况。
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
    static func isInside(_ child: URL, directory: URL) -> Bool {
        let parent = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = child.resolvingSymlinksInPath().standardizedFileURL.path
        return path == parent || path.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
    static func normalizedSelection(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        let unique = urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL.path).inserted }
        // 父目录和子项同时选中时只操作父目录，避免重复复制和无效移动。
        return unique.filter { item in
            !unique.contains { other in
                guard other != item,
                      let values = try? other.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true else { return false }
                return item.standardizedFileURL.path.hasPrefix(other.standardizedFileURL.path + "/")
            }
        }
    }
    static func availableURL(in directory: URL, filename: String) throws -> URL {
        try validateFilename(filename)
        let original = directory.appendingPathComponent(filename)
        if !exists(original) { return original }
        let ext = original.pathExtension
        let stem = ext.isEmpty ? filename : original.deletingPathExtension().lastPathComponent
        for index in 2...100_000 {
            let candidate = directory.appendingPathComponent(
                ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            )
            try validateFilename(candidate.lastPathComponent)
            if !exists(candidate) { return candidate }
        }
        throw FileOperationError.message("同名文件过多，请使用其他名称。")
    }
    static func createFile(in directory: URL, filename: String, data: Data) throws -> URL {
        try requireDirectory(directory)
        // 在写入瞬间检查目标，避免“先检查再覆盖”的竞争。
        for _ in 0..<100 {
            let target = try availableURL(in: directory, filename: filename)
            do {
                try data.write(to: target, options: [.withoutOverwriting])
                return target
            } catch {
                if exists(target) { continue }
                throw error
            }
        }
        throw FileOperationError.message("创建文件时遇到持续的重名冲突，请重试。")
    }
    static func transfer(_ selection: [URL], to directory: URL, moving: Bool,
                         policy: CollisionPolicy) throws -> TransferResult {
        try requireDirectory(directory)
        let fm = FileManager.default
        var result = TransferResult()
        for source in normalizedSelection(selection) {
            do {
                guard exists(source) else { throw FileOperationError.message("原文件已不存在") }
                if moving && source.deletingLastPathComponent().resolvingSymlinksInPath() ==
                    directory.resolvingSymlinksInPath() {
                    result.skipped.append(source)
                    continue
                }
                let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true && values.isSymbolicLink != true &&
                    isInside(directory, directory: source) {
                    throw FileOperationError.message("不能把文件夹放进它自身或它的子目录")
                }
                let requested = directory.appendingPathComponent(source.lastPathComponent)
                if exists(requested) && policy == .skip {
                    result.skipped.append(source)
                    continue
                }
                var target = try availableURL(in: directory, filename: source.lastPathComponent)
                if moving {
                    try fm.moveItem(at: source, to: target)
                } else {
                    // 先复制到隐藏的中间项，避免失败后留下看似完整的半成品。
                    let staging = directory.appendingPathComponent(".qingyou-copy-\(UUID().uuidString)")
                    defer { try? fm.removeItem(at: staging) }
                    try fm.copyItem(at: source, to: staging)
                    var committed = false
                    for _ in 0..<100 {
                        target = try availableURL(in: directory, filename: source.lastPathComponent)
                        do {
                            try fm.moveItem(at: staging, to: target)
                            committed = true
                            break
                        } catch {
                            guard exists(target) else { throw error }
                            if policy == .skip { break }
                        }
                    }
                    if !committed {
                        if policy == .skip { result.skipped.append(source); continue }
                        throw FileOperationError.message("目标持续发生重名冲突")
                    }
                }
                result.completed.append(.init(source: source, destination: target))
            } catch {
                result.failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return result
    }
    static func templateData(_ template: FileTemplate, name: String,
                             resources: URL, importedDirectory: URL = Product.templateDirectory) throws -> Data {
        if let resource = template.resource {
            guard resource == URL(fileURLWithPath: resource).lastPathComponent else {
                throw FileOperationError.message("模板资源名称无效。")
            }
            return try Data(contentsOf: resources.appendingPathComponent("Templates").appendingPathComponent(resource))
        }
        if let filename = template.importedFilename {
            try validateFilename(filename)
            return try Data(contentsOf: importedDirectory.appendingPathComponent(filename))
        }
        let text = (template.content ?? "")
            .replacingOccurrences(of: "{{name}}", with: name)
            .replacingOccurrences(of: "{{date}}", with: ISO8601DateFormatter().string(from: Date()).prefix(10).description)
        return Data(text.utf8)
    }
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static func createProject(in directory: URL, name: String, academic: Bool) throws -> URL {
        try requireDirectory(directory)
        try validateFilename(name)
        let fm = FileManager.default
        let target = try availableURL(in: directory, filename: name)
        let staging = directory.appendingPathComponent(".qingyou-project-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let folders = academic ? ["manuscript", "references", "data", "figures", "code", "notes"] :
            ["src", "tests", "docs", "assets"]
        for folder in folders {
            let url = staging.appendingPathComponent(folder, isDirectory: true)
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
            try Data().write(to: url.appendingPathComponent(".gitkeep"))
        }
        let readme = "# \(name)\n\n\(academic ? "研究问题、数据说明和实验记录。" : "项目说明、运行方式和开发记录。")\n\n## 目录\n\n" +
            folders.map { "- \($0)/" }.joined(separator: "\n") + "\n"
        try Data(readme.utf8).write(to: staging.appendingPathComponent("README.md"))
        try Data(".DS_Store\n.env\n".utf8).write(to: staging.appendingPathComponent(".gitignore"))
        try fm.moveItem(at: staging, to: target)
        return target
    }
}
