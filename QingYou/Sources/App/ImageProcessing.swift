import AppKit
import ImageIO
import UniformTypeIdentifiers
import PDFKit

enum ImageSizing: String, CaseIterable, Identifiable {
    case fit, percent, custom
    var id: String { rawValue }
    var title: String { switch self { case .fit: return "限制最大宽高"; case .percent: return "按百分比"; case .custom: return "自定义像素" } }
}
enum ImageOutput: String, CaseIterable, Identifiable {
    case original, png, jpeg, heic
    var id: String { rawValue }
    var title: String { switch self { case .original: return "沿用原格式"; case .png: return "PNG"; case .jpeg: return "JPEG"; case .heic: return "HEIC" } }
}
struct ImageAdjustment: Equatable {
    var sizing: ImageSizing = .fit
    var width = 1920
    var height = 1920
    var percent = 50.0
    var keepRatio = true
    var allowUpscale = false
    var output: ImageOutput = .original
    var quality = 0.85
    var removeLocation = false
    var quarterTurns = 0
    var flipHorizontal = false

    func dimensions(width sourceWidth: Int, height sourceHeight: Int) throws -> (Int, Int) {
        guard sourceWidth > 0, sourceHeight > 0 else { throw FileOperationError.message("图片尺寸无效。") }
        let rotated = abs(quarterTurns) % 2 == 1
        let w = Double(rotated ? sourceHeight : sourceWidth), h = Double(rotated ? sourceWidth : sourceHeight)
        var targetW: Double, targetH: Double
        switch sizing {
        case .fit:
            guard width > 0, height > 0 else { throw FileOperationError.message("最大宽高必须大于 0。") }
            let scale = min(Double(width) / w, Double(height) / h, allowUpscale ? Double.greatestFiniteMagnitude : 1)
            targetW = w * scale; targetH = h * scale
        case .percent:
            guard percent.isFinite, percent > 0, percent <= 1000 else { throw FileOperationError.message("缩放比例应在 0–1000% 之间。") }
            let scale = min(percent / 100, allowUpscale ? 10 : 1)
            targetW = w * scale; targetH = h * scale
        case .custom:
            guard width > 0, height > 0 else { throw FileOperationError.message("目标宽高必须大于 0。") }
            if keepRatio {
                // 自定义模式锁定比例时以宽度为准，高度在界面联动；范围模式才同时限制两个上限。
                let scale = min(Double(width) / w, allowUpscale ? Double.greatestFiniteMagnitude : 1)
                targetW = w * scale; targetH = h * scale
            } else {
                targetW = min(Double(width), allowUpscale ? Double(width) : w)
                targetH = min(Double(height), allowUpscale ? Double(height) : h)
            }
        }
        guard targetW.isFinite, targetH.isFinite, targetW <= 30_000, targetH <= 30_000,
              targetW * targetH <= 100_000_000 else { throw FileOperationError.message("输出过大，请将总像素控制在 1 亿以内。") }
        return (max(1, Int(targetW.rounded())), max(1, Int(targetH.rounded())))
    }
}

struct ImageDetails {
    let url: URL
    let type: UTType
    let width: Int
    let height: Int
    let bytes: Int64
    let rows: [(String, String)]
    let latitude: Double?
    let longitude: Double?
    let hasLocationMetadata: Bool
    var mapURL: URL? {
        guard let latitude, let longitude else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)")
    }
}

enum ImageProcessing {
    static func details(_ url: URL) throws -> ImageDetails {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeID = CGImageSourceGetType(source), let type = UTType(typeID as String),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let rawW = p[kCGImagePropertyPixelWidth as String] as? Int,
              let rawH = p[kCGImagePropertyPixelHeight as String] as? Int else {
            throw FileOperationError.message("无法读取图片：\(url.lastPathComponent)")
        }
        let orientation = p[kCGImagePropertyOrientation as String] as? Int ?? 1
        let width = (5...8).contains(orientation) ? rawH : rawW
        let height = (5...8).contains(orientation) ? rawW : rawH
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let gps = p[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        let iptc = p[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        func coordinate(_ value: String, _ ref: String, negative: String) -> Double? {
            guard let number = gps[value] as? NSNumber else { return nil }
            let signed = number.doubleValue * ((gps[ref] as? String) == negative ? -1 : 1)
            return signed.isFinite ? signed : nil
        }
        var latitude = coordinate("Latitude", "LatitudeRef", negative: "S")
        var longitude = coordinate("Longitude", "LongitudeRef", negative: "W")
        if let value = latitude, !(-90...90).contains(value) { latitude = nil }
        if let value = longitude, !(-180...180).contains(value) { longitude = nil }
        let dateFormatter = DateFormatter(); dateFormatter.dateStyle = .medium; dateFormatter.timeStyle = .medium
        var rows: [(String, String)] = [
            ("文件名", url.lastPathComponent), ("像素", "\(width) × \(height)"),
            ("文件大小", ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)),
            ("格式", CGImageSourceGetType(source).flatMap { UTType($0 as String)?.localizedDescription } ?? url.pathExtension.uppercased())
        ]
        if CGImageSourceGetCount(source) > 1 { rows.append(("帧／页数", String(CGImageSourceGetCount(source)))) }
        for (label, key) in [("文件创建", FileAttributeKey.creationDate), ("文件修改", .modificationDate)] {
            if let date = attrs[key] as? Date { rows.append((label, dateFormatter.string(from: date))) }
        }
        if let taken = exif["DateTimeOriginal"] as? String { rows.append(("拍摄时间", taken + ((exif["OffsetTimeOriginal"] as? String).map { " \($0)" } ?? "（未记录时区）"))) }
        for (label, value) in [("相机", tiff["Model"]), ("镜头", exif["LensModel"]), ("光圈", exif["FNumber"]),
                               ("曝光秒数", exif["ExposureTime"]), ("ISO", exif["ISOSpeedRatings"]),
                               ("焦距 mm", exif["FocalLength"]), ("色彩空间", p[kCGImagePropertyProfileName as String])] {
            if let values = value as? [NSNumber] { rows.append((label, values.map(\.stringValue).joined(separator: ", "))) }
            else if let value { rows.append((label, String(describing: value))) }
        }
        let place = ["City", "ProvinceState", "CountryPrimaryLocationName"].compactMap { iptc[$0] as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !place.isEmpty { rows.append(("记录的地点", place)) }
        if let latitude, let longitude { rows.append(("GPS 坐标", String(format: "%.6f, %.6f", latitude, longitude))) }
        else { rows.append(("拍摄位置", "文件未记录可用的 GPS 位置")) }
        return ImageDetails(url: url, type: type, width: width, height: height, bytes: bytes, rows: rows, latitude: latitude, longitude: longitude, hasLocationMetadata: !gps.isEmpty || !place.isEmpty)
    }

    static func outputType(_ choice: ImageOutput, original: UTType, filename: String) throws -> UTType {
        switch choice {
        case .original:
            guard [.png, .jpeg, .heic, .tiff].contains(original) else {
                throw FileOperationError.message("暂不支持按原格式导出「\(filename)」。请选择 PNG、JPEG 或 HEIC。")
            }
            return original
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }

    static func decoded(_ url: URL, maxPixel: Int? = nil, allowsMultiple: Bool = false) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let w = p[kCGImagePropertyPixelWidth as String] as? Int,
              let h = p[kCGImagePropertyPixelHeight as String] as? Int,
              w > 0, h > 0, Double(w) * Double(h) <= 150_000_000 else {
            throw FileOperationError.message("图片无法解码或总像素超过 1.5 亿：\(url.lastPathComponent)")
        }
        guard allowsMultiple || CGImageSourceGetCount(source) == 1 else { throw FileOperationError.message("动态或多页图片请先导出为单张图片：\(url.lastPathComponent)") }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: min(maxPixel ?? max(w, h), max(w, h))]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw FileOperationError.message("图片解码失败。") }
        return image
    }

    static func adjusted(_ image: CGImage, options: ImageAdjustment, targetSize: (Int, Int)? = nil, previewLimit: Int? = nil) throws -> CGImage {
        let dimensions: (Int, Int)
        if let targetSize { dimensions = targetSize }
        else { dimensions = try options.dimensions(width: image.width, height: image.height) }
        var (w, h) = dimensions
        if let limit = previewLimit {
            let factor = min(1, Double(limit) / Double(max(w, h)))
            w = max(1, Int(Double(w) * factor)); h = max(1, Int(Double(h) * factor))
        }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw FileOperationError.message("无法创建图片画布。")
        }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        if options.flipHorizontal { ctx.scaleBy(x: -1, y: 1) }
        let turns = ((options.quarterTurns % 4) + 4) % 4
        ctx.rotate(by: -CGFloat(turns) * .pi / 2)
        let rotated = turns % 2 == 1
        let drawW = CGFloat(rotated ? h : w), drawH = CGFloat(rotated ? w : h)
        ctx.draw(image, in: CGRect(x: -drawW / 2, y: -drawH / 2, width: drawW, height: drawH))
        guard let result = ctx.makeImage() else { throw FileOperationError.message("图片处理失败。") }
        return result
    }

    static func encode(_ originalImage: CGImage, type: UTType, quality: Double,
                       properties: [String: Any] = [:]) throws -> Data {
        var image = originalImage
        if type == .jpeg {
            guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw FileOperationError.message("无法创建 JPEG 画布。") }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = ctx.makeImage() else { throw FileOperationError.message("无法合成 JPEG。") }
            image = flattened
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw FileOperationError.message("系统不支持写入 \(type.identifier)。")
        }
        var p = properties
        p[kCGImagePropertyOrientation as String] = 1
        p[kCGImagePropertyPixelWidth as String] = image.width; p[kCGImagePropertyPixelHeight as String] = image.height
        p[kCGImageDestinationLossyCompressionQuality as String] = min(1, max(0, quality))
        // 像素已按方向旋转，避免旧 EXIF 方向和旧尺寸让看图软件再次旋转。
        if var tiff = p[kCGImagePropertyTIFFDictionary as String] as? [String: Any] { tiff["Orientation"] = 1; p[kCGImagePropertyTIFFDictionary as String] = tiff }
        if var exif = p[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif["PixelXDimension"] = image.width; exif["PixelYDimension"] = image.height
            p[kCGImagePropertyExifDictionary as String] = exif
        }
        CGImageDestinationAddImage(destination, image, p as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileOperationError.message("图片编码失败。") }
        return data as Data
    }

    static func export(_ urls: [URL], options: ImageAdjustment, in directory: URL, suffix: String? = nil,
                       cancellation: WorkCancellation, progress: (Int, Int) -> Void) throws -> [URL] {
        try LocalOutputs.staged(in: directory, cancellation: cancellation) { staging in
            try urls.enumerated().map { index, url in
                try cancellation.check()
                let item: (URL, String) = try autoreleasepool {
                    let info = try details(url)
                    let type = try outputType(options.output, original: info.type, filename: url.lastPathComponent)
                    let dimensions = try options.dimensions(width: info.width, height: info.height)
                    // 在解码时先下采样，缩小大图不必分配原始尺寸的整块画布。
                    let image = try adjusted(decoded(url, maxPixel: max(dimensions.0, dimensions.1)), options: options, targetSize: dimensions)
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                        throw FileOperationError.message("源图片已无法读取，请重新选择。")
                    }
                    var p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
                    if options.removeLocation {
                        p.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
                        if var iptc = p[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
                            for key in ["City", "SubLocation", "ProvinceState", "CountryPrimaryLocationCode", "CountryPrimaryLocationName", "LocationCreated", "LocationShown"] {
                                iptc.removeValue(forKey: key)
                            }
                            // 去掉地点字段，保留作者、说明和版权等无关内容。
                            p[kCGImagePropertyIPTCDictionary as String] = iptc
                        }
                    }
                    let data = try encode(image, type: type, quality: options.quality, properties: p)
                    let temp = staging.appendingPathComponent("\(index)")
                    try data.write(to: temp, options: .withoutOverwriting)
                    return (temp, url.deletingPathExtension().lastPathComponent + (suffix ?? "-\(image.width)x\(image.height)") + "." + (type.preferredFilenameExtension ?? "png"))
                }
                progress(index + 1, urls.count)
                return item
            }
        }
    }
}
