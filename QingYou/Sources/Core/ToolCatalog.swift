import Foundation
import UniformTypeIdentifiers

/// 右键菜单与拖放工具共用类型判断，避免混选目录时显示无法执行的工具。
struct SelectionProfile {
    let count: Int
    let allFiles: Bool
    let allFolders: Bool
    let allImages: Bool
    let allPDFs: Bool

    init(_ urls: [URL]) {
        count = urls.count
        let values = urls.map { try? $0.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) }
        allFiles = !urls.isEmpty && values.allSatisfy { $0?.isRegularFile == true }
        allFolders = !urls.isEmpty && values.allSatisfy { $0?.isDirectory == true }
        allImages = allFiles && urls.allSatisfy { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .image) == true }
        allPDFs = allFiles && urls.allSatisfy { $0.pathExtension.lowercased() == "pdf" }
    }
}

enum ToolCommand: String, CaseIterable, Identifiable {
    case rename, png, jpeg, resize, ocr, mergePDF, splitPDF, checksum
    case imageInfo, imagesPDF, compressPDF, organizePDF, pdfImages, pdfText
    var id: String { rawValue }
    static let available: [ToolCommand] = [.resize, .imageInfo, .imagesPDF, .png, .jpeg, .ocr, .mergePDF, .splitPDF, .compressPDF, .organizePDF, .pdfImages, .pdfText]
    var title: String {
        switch self {
        case .rename: return "批量重命名"
        case .png: return "转换为 PNG"
        case .jpeg: return "转换为 JPEG"
        case .resize: return "调整图片"
        case .ocr: return "识别图片文字"
        case .mergePDF: return "合并 PDF"
        case .splitPDF: return "拆分 PDF"
        case .checksum: return "SHA-256 校验"
        case .imageInfo: return "图片信息"
        case .imagesPDF: return "图片合并为 PDF"
        case .compressPDF: return "压缩 PDF"
        case .organizePDF: return "整理 PDF 页面"
        case .pdfImages: return "PDF 导出图片"
        case .pdfText: return "提取 PDF 文字"
        }
    }
    var detail: String {
        switch self {
        case .rename: return "实时预览名称，保留扩展名，可撤销。"
        case .png: return "保留透明背景，另存为 PNG 图片。"
        case .jpeg: return "透明区域填充白色，另存为 JPEG。"
        case .resize: return "按比例、百分比或自定义像素调整，预览后另存。"
        case .ocr: return "在本机识别中英文，保存为 TXT。"
        case .mergePDF: return "预览文档、拖动排序，合并后在 Finder 中命名。"
        case .splitPDF: return "按页码范围拆分，预览结果并保存到当前文件夹。"
        case .checksum: return "流式计算文件指纹，支持复制结果。"
        case .imageInfo: return "查看像素、文件时间、拍摄参数与实际记录的位置。"
        case .imagesPDF: return "拖动排序、选择纸张，将图片合为一份 PDF。"
        case .compressPDF: return "保留文字与矢量，比较系统优化后的实际体积。"
        case .organizePDF: return "排序、旋转、删除与插入页面，另存 PDF 副本。"
        case .pdfImages: return "按页码范围导出 PNG 或 JPEG，可选分辨率。"
        case .pdfText: return "提取已有文字，扫描页可使用本机 OCR。"
        }
    }
    var symbol: String {
        switch self {
        case .rename: return "character.cursor.ibeam"
        case .png, .jpeg: return "photo.on.rectangle"
        case .resize: return "arrow.down.right.and.arrow.up.left"
        case .ocr: return "text.viewfinder"
        case .mergePDF: return "doc.on.doc"
        case .splitPDF: return "scissors"
        case .checksum: return "number"
        case .imageInfo: return "info.circle"
        case .imagesPDF: return "photo.on.rectangle.angled"
        case .compressPDF: return "arrow.down.doc"
        case .organizePDF: return "square.grid.2x2"
        case .pdfImages: return "photo"
        case .pdfText: return "text.viewfinder"
        }
    }
    var action: ActionKind {
        switch self {
        case .rename: return .rename
        case .png: return .imagePNG
        case .jpeg: return .imageJPEG
        case .resize: return .imageResize
        case .ocr: return .imageOCR
        case .mergePDF: return .pdfMerge
        case .splitPDF: return .pdfSplit
        case .checksum: return .checksum
        case .imageInfo: return .imageInfo
        case .imagesPDF: return .imagesPDF
        case .compressPDF: return .pdfCompress
        case .organizePDF: return .pdfOrganize
        case .pdfImages: return .pdfImages
        case .pdfText: return .pdfText
        }
    }
    var contentTypes: [UTType]? {
        switch self {
        case .png, .jpeg, .resize, .ocr, .imageInfo, .imagesPDF: return [.image]
        case .mergePDF, .splitPDF, .compressPDF, .organizePDF, .pdfImages, .pdfText: return [.pdf]
        default: return nil
        }
    }
    func accepts(_ selection: SelectionProfile) -> Bool {
        switch self {
        case .rename: return selection.count > 0
        case .png, .jpeg, .resize, .ocr, .imageInfo, .imagesPDF: return selection.allImages
        case .mergePDF: return selection.allPDFs && selection.count > 1
        case .splitPDF: return selection.allPDFs && selection.count == 1
        case .checksum: return selection.allFiles
        case .compressPDF, .organizePDF, .pdfImages, .pdfText: return selection.allPDFs && selection.count == 1
        }
    }
    func matches(_ query: String) -> Bool {
        (title + " " + detail + " " + rawValue).localizedStandardContains(query)
    }
}

enum MenuPreset: String, CaseIterable, Identifiable {
    case everyday, creative, complete
    var id: String { rawValue }
    var title: String {
        switch self {
        case .everyday: return "日常精简"
        case .creative: return "图文工作"
        case .complete: return "全部功能"
        }
    }
    var features: [MenuFeature] {
        switch self {
        case .everyday: return [.newFile, .clipboard, .paths, .openWith]
        case .creative: return [.newFile, .image, .pdf, .transfer, .paths, .openWith]
        case .complete: return MenuFeature.available
        }
    }
    func apply(to configuration: inout Configuration) {
        let enabled = Set(features)
        // 预设只调整菜单，模板、收藏和文件操作偏好保持原值。
        let ordered = features + MenuFeature.available.filter { !enabled.contains($0) }
        configuration.menuItems = ordered.map { .init(feature: $0, enabled: enabled.contains($0)) }
    }
}
