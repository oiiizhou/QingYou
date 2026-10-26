import Foundation

struct RenameOptions: Hashable {
    var find = ""
    var replacement = ""
    var prefix = ""
    var suffix = ""
    var numbered = false
    var start = 1
    var digits = 3
}
enum RenameEngine {
    static func plan(_ urls: [URL], options: RenameOptions) throws -> [FileMapping] {
        guard options.start >= 0, (1...8).contains(options.digits) else {
            throw FileOperationError.message("起始编号不能为负数，编号位数应为 1–8。")
        }
        let sources = FileOperations.normalizedSelection(urls).sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        return try sources.enumerated().map { index, source in
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            let ext = values.isDirectory == true ? "" : source.pathExtension
            var stem = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
            if !options.find.isEmpty { stem = stem.replacingOccurrences(of: options.find, with: options.replacement) }
            let number = options.numbered ? String(format: "%0*d_", options.digits, options.start + index) : ""
            let filename = options.prefix + number + stem + options.suffix + (ext.isEmpty ? "" : "." + ext)
            try FileOperations.validateFilename(filename)
            return FileMapping(source: source, destination: source.deletingLastPathComponent().appendingPathComponent(filename))
        }
    }
    static func validate(_ plan: [FileMapping]) throws {
        let sourcePaths = Set(plan.map { $0.source.standardizedFileURL.path })
        guard sourcePaths.count == plan.count else { throw FileOperationError.message("存在重复的原文件。") }
        var targets = Set<String>()
        for item in plan {
            try FileOperations.validateFilename(item.destination.lastPathComponent)
            guard item.source.deletingLastPathComponent() == item.destination.deletingLastPathComponent() else {
                throw FileOperationError.message("批量重命名不能改变文件所在目录。")
            }
            guard FileOperations.exists(item.source) else {
                throw FileOperationError.message("原文件已不存在：\(item.source.lastPathComponent)")
            }
            let key = item.destination.standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
            guard targets.insert(key).inserted else {
                throw FileOperationError.message("多个文件将使用同一个名称：\(item.destination.lastPathComponent)")
            }
            if FileOperations.exists(item.destination) && !sourcePaths.contains(item.destination.standardizedFileURL.path) {
                let sourceID = try? item.source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                let targetID = try? item.destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
                if sourceID == nil || targetID == nil || !((sourceID as? NSObject)?.isEqual(targetID) ?? false) {
                    throw FileOperationError.message("名称已被其他文件使用：\(item.destination.lastPathComponent)")
                }
            }
        }
    }
    @discardableResult
    static func apply(_ plan: [FileMapping]) throws -> [FileMapping] {
        try validate(plan)
        let changed = plan.filter { $0.source.path != $0.destination.path }
        let fm = FileManager.default
        let staging = changed.map { $0.source.deletingLastPathComponent().appendingPathComponent(".qingyou-rename-\(UUID().uuidString)") }
        var staged = 0
        var committed = 0
        do {
            // 先暂存再落到最终名称，支持交换名称和仅改变大小写。
            for (index, item) in changed.enumerated() {
                try fm.moveItem(at: item.source, to: staging[index])
                staged += 1
            }
            for (index, item) in changed.enumerated() {
                try fm.moveItem(at: staging[index], to: item.destination)
                committed += 1
            }
            return changed
        } catch {
            let original = error.localizedDescription
            var rollbackErrors: [String] = []
            for index in (0..<committed).reversed() {
                do { try fm.moveItem(at: changed[index].destination, to: staging[index]) }
                catch { rollbackErrors.append("\(changed[index].destination.path)：\(error.localizedDescription)") }
            }
            for index in 0..<staged where FileOperations.exists(staging[index]) {
                do { try fm.moveItem(at: staging[index], to: changed[index].source) }
                catch { rollbackErrors.append("\(staging[index].path)：\(error.localizedDescription)") }
            }
            let detail = rollbackErrors.isEmpty ? "已还原原文件名。" :
                "部分文件未能还原，请按以下路径检查：\n" + rollbackErrors.joined(separator: "\n")
            throw FileOperationError.message("重命名失败：\(original)\n\(detail)")
        }
    }
}
