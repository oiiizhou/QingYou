import Foundation
import PDFKit

struct PDFSplitPart: Identifiable, Equatable {
    var id = UUID()
    var pages: String
    var name: String = ""
}

enum PDFOperations {
    /// 逗号表示同一份结果中的多个范围；每个拆分条目生成一个独立文件。
    static func pages(_ text: String, count: Int) throws -> [Int] {
        let normalized = text.replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
        guard count > 0, !normalized.isEmpty else { throw FileOperationError.message("请输入页码，例如 1-3 或 1-3,5。") }
        var result: [Int] = []
        var seen = Set<Int>()
        for component in normalized.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = component.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count), let first = Int(bounds[0]), first >= 1,
                  let last = Int(bounds.last!), last >= first, last <= count else {
                throw FileOperationError.message("页码范围无效，请输入 1–\(count) 之间的页码，且起始页不大于结束页。")
            }
            for page in first...last {
                guard seen.insert(page).inserted else { throw FileOperationError.message("同一份结果中重复包含第 \(page) 页。") }
                result.append(page - 1)
            }
        }
        return result
    }

    static func read(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            throw FileOperationError.message("无法读取 PDF，文件可能已加密或没有页面：\(url.lastPathComponent)")
        }
        return document
    }

    static func extract(_ document: PDFDocument, pages: [Int]) throws -> PDFDocument {
        guard !pages.isEmpty else { throw FileOperationError.message("至少选择一页。") }
        let output = PDFDocument()
        for index in pages {
            guard index >= 0, index < document.pageCount, let page = document.page(at: index)?.copy() as? PDFPage else {
                throw FileOperationError.message("无法读取第 \(index + 1) 页。")
            }
            output.insert(page, at: output.pageCount)
        }
        return output
    }

    static func combined(_ sources: [URL]) throws -> PDFDocument {
        guard sources.count >= 2 else { throw FileOperationError.message("请至少选择两个 PDF。") }
        let output = PDFDocument()
        // 明确保留界面顺序，不能在导出时偷偷按文件名重新排序。
        for source in sources {
            let document = try read(source)
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.copy() as? PDFPage else {
                    throw FileOperationError.message("无法读取页面：\(source.lastPathComponent)")
                }
                output.insert(page, at: output.pageCount)
            }
        }
        return output
    }

    static func merge(_ sources: [URL], in directory: URL) throws -> URL {
        let document = try combined(sources)
        guard let data = document.dataRepresentation() else { throw FileOperationError.message("PDF 合并失败。") }
        return try FileOperations.createFile(in: directory, filename: "合并PDF.pdf", data: data)
    }

    static func splitName(_ part: PDFSplitPart, source: URL) throws -> String {
        let custom = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = custom.isEmpty
            ? source.deletingPathExtension().lastPathComponent + "-第" + part.pages.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "、").replacingOccurrences(of: "，", with: "、") + "页"
            : custom
        let name = base.lowercased().hasSuffix(".pdf") ? base : base + ".pdf"
        try FileOperations.validateFilename(name)
        return name
    }

    static func split(_ source: URL, parts: [PDFSplitPart], in directory: URL) throws -> [URL] {
        guard !parts.isEmpty else { throw FileOperationError.message("请添加至少一个拆分范围。") }
        try FileOperations.requireDirectory(directory)
        let document = try read(source)
        let plan = try parts.map { (try pages($0.pages, count: document.pageCount), try splitName($0, source: source)) }
        let fm = FileManager.default
        let staging = directory.appendingPathComponent(".qingyou-pdf-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        // 所有范围先生成成功，再落到用户目录；失败时不会留下半套输出。
        var staged: [(URL, String)] = []
        for (index, item) in plan.enumerated() {
            let output = try extract(document, pages: item.0)
            guard let data = output.dataRepresentation() else { throw FileOperationError.message("PDF 拆分失败。") }
            let temporary = staging.appendingPathComponent("\(index).pdf")
            try data.write(to: temporary, options: .withoutOverwriting)
            staged.append((temporary, item.1))
        }
        var completed: [(URL, FileIdentity)] = []
        do {
            for (temporary, name) in staged {
                let identity = try FileIdentity.read(temporary)
                let target = try FileOperations.availableURL(in: directory, filename: name)
                try fm.moveItem(at: temporary, to: target)
                completed.append((target, identity))
            }
        } catch {
            for (url, identity) in completed where (try? FileIdentity.read(url)) == identity { try? fm.removeItem(at: url) }
            throw error
        }
        return completed.map(\.0)
    }
}
