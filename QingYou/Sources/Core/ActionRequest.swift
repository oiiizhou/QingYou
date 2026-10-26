import Foundation
import Darwin

enum ActionKind: String, Codable {
    case createFile, cut, paste, copyTo, moveTo, copyPaths, copyNames, copyShellPaths, copyMarkdown
    case terminal, openApplication, openFavorite, rename, hide, unhide, setIcon, resetIcon
    case imagePNG, imageJPEG, imageResize, imageOCR, pdfMerge, pdfSplit, checksum
    case pasteAsFile, imageInfo, imagesPDF, pdfCompress, pdfOrganize, pdfImages, pdfText
    case academicProject, codeProject, settings
}
struct ActionRequest: Codable {
    var id = UUID()
    var createdAt = Date()
    let action: ActionKind
    let paths: [String]
    let directory: String?
    let argument: String?
    init(action: ActionKind, paths: [String] = [], directory: String? = nil, argument: String? = nil) {
        self.action = action
        self.paths = paths
        self.directory = directory
        self.argument = argument
    }
    func validate() throws {
        guard abs(createdAt.timeIntervalSinceNow) < 120, paths.count <= 10_000,
              paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }),
              directory == nil || (directory!.hasPrefix("/") && !directory!.contains("\0")) else {
            throw FileOperationError.message("操作请求无效或已过期，请重新使用右键菜单。")
        }
    }
    func write(to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        for url in (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where url.pathExtension == "qyrequest" {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               Date().timeIntervalSince(date) > 3600 { try? fm.removeItem(at: url) }
        }
        let url = directory.appendingPathComponent("\(id.uuidString).qyrequest")
        try JSONEncoder().encode(self).write(to: url, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    static func consume(_ url: URL, inbox: URL = Product.requestDirectory) throws -> ActionRequest {
        let actual = url.resolvingSymlinksInPath().standardizedFileURL
        let expected = inbox.resolvingSymlinksInPath().standardizedFileURL
        // 不注册可执行任意路径操作的 URL scheme，只接受扩展私有目录中的短时请求。
        guard url.isFileURL, url.pathExtension == "qyrequest",
              actual.deletingLastPathComponent() == expected else {
            throw FileOperationError.message("仅接受轻右 Finder 扩展生成的操作请求。")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: actual.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0,
              ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 2_000_000 else {
            throw FileOperationError.message("操作请求的权限或大小不符合要求。")
        }
        let request = try JSONDecoder().decode(ActionRequest.self, from: Data(contentsOf: actual))
        try request.validate()
        guard url.deletingPathExtension().lastPathComponent == request.id.uuidString else {
            throw FileOperationError.message("操作请求标识不匹配。")
        }
        try FileManager.default.removeItem(at: actual)
        return request
    }
}
