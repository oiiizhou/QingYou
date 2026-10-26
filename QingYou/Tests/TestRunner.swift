import Foundation
import AppKit
import PDFKit
import ImageIO
import CoreText

struct TestFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "断言失败") throws {
    guard try condition() else { throw TestFailure(message: message) }
}
func expectThrows(_ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw TestFailure(message: "预期操作应被拒绝，但它成功了")
}

@main
struct TestRunner {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("qingyou-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        var passed = 0
        var failures: [String] = []
        func folder(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func file(_ name: String, in directory: URL, text: String = "original") throws -> URL {
            let url = directory.appendingPathComponent(name)
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            return url
        }
        func test(_ name: String, _ body: () throws -> Void) {
            do { try body(); passed += 1; print("✓ \(name)") }
            catch { failures.append("\(name)：\(error.localizedDescription)"); print("✗ \(name)：\(error.localizedDescription)") }
        }
        test("拒绝空名、路径穿越、空字符和超长中文名") {
            for name in ["", " ", ".", "..", "../a", "a/b", "a\0b", String(repeating: "中", count: 86)] {
                try expectThrows { try FileOperations.validateFilename(name) }
            }
        }
        test("允许中文、引号、空格和 shell 特殊字符作为文件名") {
            try FileOperations.validateFilename("论文 '第一版' $(date); &.md")
        }
        test("创建同名文件时保留原内容") {
            let directory = try folder("create")
            let original = try file("报告.md", in: directory)
            let created = try FileOperations.createFile(in: directory, filename: "报告.md", data: Data("new".utf8))
            try expect(created.lastPathComponent == "报告 2.md")
            try expect(try String(contentsOf: original, encoding: .utf8) == "original")
            try expect(try String(contentsOf: created, encoding: .utf8) == "new")
        }
        test("断开的符号链接不会被当作空闲名称覆盖") {
            let directory = try folder("dangling")
            let link = directory.appendingPathComponent("a.txt")
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "/nonexistent-qingyou-target")
            let created = try FileOperations.createFile(in: directory, filename: "a.txt", data: Data())
            try expect(created.lastPathComponent == "a 2.txt")
            try expect(try fm.destinationOfSymbolicLink(atPath: link.path) == "/nonexistent-qingyou-target")
        }
        test("不存在的目录不会被隐式创建") {
            try expectThrows { _ = try FileOperations.createFile(in: root.appendingPathComponent("absent"), filename: "a", data: Data()) }
        }
        test("复制保留两份并保留源文件") {
            let source = try folder("copy-source"), target = try folder("copy-target")
            let input = try file("a.txt", in: source, text: "new")
            let original = try file("a.txt", in: target, text: "old")
            let result = try FileOperations.transfer([input], to: target, moving: false, policy: .keepBoth)
            try expect(result.completed.count == 1 && result.failures.isEmpty)
            try expect(try String(contentsOf: original, encoding: .utf8) == "old")
            try expect(try String(contentsOf: result.completed[0].destination, encoding: .utf8) == "new")
            try expect(FileOperations.exists(input))
            try expect(try fm.contentsOfDirectory(atPath: target.path).allSatisfy { !$0.hasPrefix(".qingyou") })
        }
        test("跳过重名时不修改任何一个文件") {
            let source = try folder("skip-source"), target = try folder("skip-target")
            let input = try file("a", in: source, text: "new")
            let original = try file("a", in: target, text: "old")
            let result = try FileOperations.transfer([input], to: target, moving: true, policy: .skip)
            try expect(result.skipped == [input] && result.completed.isEmpty)
            try expect(try String(contentsOf: original, encoding: .utf8) == "old")
            try expect(FileOperations.exists(input))
        }
        test("移动成功后源文件消失，结果映射可用于撤销") {
            let source = try folder("move-source"), target = try folder("move-target")
            let input = try file("中文.txt", in: source)
            let result = try FileOperations.transfer([input], to: target, moving: true, policy: .keepBoth)
            try expect(result.completed == [.init(source: input, destination: target.appendingPathComponent("中文.txt"))])
            try expect(!FileOperations.exists(input))
            try expect(try String(contentsOf: result.completed[0].destination, encoding: .utf8) == "original")
        }
        test("移动到原目录只跳过，不意外改名") {
            let directory = try folder("same-parent")
            let input = try file("a", in: directory)
            let result = try FileOperations.transfer([input], to: directory, moving: true, policy: .keepBoth)
            try expect(result.skipped == [input] && result.completed.isEmpty)
        }
        test("拒绝把目录复制到自身的子目录") {
            let directory = try folder("recursive")
            let child = directory.appendingPathComponent("child")
            try fm.createDirectory(at: child, withIntermediateDirectories: false)
            let result = try FileOperations.transfer([directory], to: child, moving: false, policy: .keepBoth)
            try expect(result.failures.count == 1 && result.completed.isEmpty)
        }
        test("解析目标符号链接后仍拒绝递归复制") {
            let directory = try folder("recursive-link")
            let child = directory.appendingPathComponent("child")
            try fm.createDirectory(at: child, withIntermediateDirectories: false)
            let alias = root.appendingPathComponent("alias")
            try fm.createSymbolicLink(at: alias, withDestinationURL: child)
            let result = try FileOperations.transfer([directory], to: alias, moving: false, policy: .keepBoth)
            try expect(result.failures.count == 1)
        }
        test("选中父目录和子文件时避免重复操作") {
            let directory = try folder("selection")
            let child = try file("child", in: directory)
            try expect(FileOperations.normalizedSelection([child, directory, directory]) == [directory])
        }
        test("部分源文件缺失时继续处理其他文件并报告失败") {
            let directory = try folder("partial"), target = try folder("partial-target")
            let valid = try file("valid", in: directory)
            let result = try FileOperations.transfer([directory.appendingPathComponent("missing"), valid], to: target, moving: false, policy: .keepBoth)
            try expect(result.completed.count == 1 && result.failures.count == 1)
        }
        test("复制符号链接本身，不复制它指向的内容") {
            let source = try folder("symlink-source"), target = try folder("symlink-target")
            let original = try file("original", in: source)
            let link = source.appendingPathComponent("link")
            try fm.createSymbolicLink(at: link, withDestinationURL: original)
            let result = try FileOperations.transfer([link], to: target, moving: false, policy: .keepBoth)
            try expect(result.completed.count == 1)
            try expect(try fm.destinationOfSymbolicLink(atPath: result.completed[0].destination.path) == original.path)
        }
        test("文件身份在移动后保持不变，替换文件后不同") {
            let directory = try folder("file-identity")
            let original = try file("original", in: directory)
            let identity = try FileIdentity.read(original)
            let moved = directory.appendingPathComponent("moved")
            try fm.moveItem(at: original, to: moved)
            try expect(try FileIdentity.read(moved) == identity)
            let replacement = try file("replacement", in: directory)
            try fm.removeItem(at: moved)
            try fm.moveItem(at: replacement, to: moved)
            try expect(try FileIdentity.read(moved) != identity)
        }
        test("终端路径正确转义单引号，特殊字符不被解释") {
            let value = "/tmp/I'm $(not-a-command); 中文"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf '%s' " + FileOperations.shellQuoted(value)]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try expect(process.terminationStatus == 0)
            try expect(String(data: data, encoding: .utf8) == value)
        }
        test("重命名按自然顺序编号并保留扩展名") {
            let directory = try folder("rename-plan")
            let a = try file("图10.png", in: directory), b = try file("图2.png", in: directory)
            var options = RenameOptions(); options.numbered = true; options.prefix = "实验_"
            let plan = try RenameEngine.plan([a, b], options: options)
            try expect(plan[0].destination.lastPathComponent == "实验_001_图2.png")
            try expect(plan[1].destination.lastPathComponent == "实验_002_图10.png")
        }
        test("目录名称中的点号不被当作扩展名") {
            let directory = try folder("name.with.dot")
            var options = RenameOptions(); options.suffix = "_新版"
            let plan = try RenameEngine.plan([directory], options: options)
            try expect(plan[0].destination.lastPathComponent == "name.with.dot_新版")
        }
        test("拒绝重复的重命名目标，原文件不变") {
            let directory = try folder("duplicate-rename")
            let a = try file("a", in: directory), b = try file("b", in: directory)
            let plan = [FileMapping(source: a, destination: directory.appendingPathComponent("same")),
                        FileMapping(source: b, destination: directory.appendingPathComponent("SAME"))]
            try expectThrows { try RenameEngine.apply(plan) }
            try expect(FileOperations.exists(a) && FileOperations.exists(b))
        }
        test("重命名不覆盖未选中的现有文件") {
            let directory = try folder("occupied-rename")
            let a = try file("a", in: directory), b = try file("b", in: directory, text: "keep")
            try expectThrows { try RenameEngine.apply([.init(source: a, destination: b)]) }
            try expect(try String(contentsOf: b, encoding: .utf8) == "keep")
        }
        test("支持交换文件名，内容不丢失") {
            let directory = try folder("swap")
            let a = try file("a", in: directory, text: "A"), b = try file("b", in: directory, text: "B")
            try RenameEngine.apply([.init(source: a, destination: b), .init(source: b, destination: a)])
            try expect(try String(contentsOf: a, encoding: .utf8) == "B")
            try expect(try String(contentsOf: b, encoding: .utf8) == "A")
        }
        test("支持仅修改文件名大小写，并可撤销") {
            let directory = try folder("case")
            let a = try file("small.txt", in: directory), b = directory.appendingPathComponent("SMALL.txt")
            let done = try RenameEngine.apply([.init(source: a, destination: b)])
            try RenameEngine.apply(done.map { .init(source: $0.destination, destination: $0.source) })
            try expect(try fm.contentsOfDirectory(atPath: directory.path).contains("small.txt"))
        }
        test("改名计划不能用于跨目录移动") {
            let directory = try folder("rename-boundary")
            let a = try file("a", in: directory)
            try expectThrows { try RenameEngine.apply([.init(source: a, destination: root.appendingPathComponent("outside"))]) }
        }
        test("文件名替换导致非法名称时拒绝执行") {
            let directory = try folder("invalid-rename")
            let a = try file("a", in: directory)
            var options = RenameOptions(); options.prefix = "../"
            try expectThrows { _ = try RenameEngine.plan([a], options: options) }
        }
        test("配置持久化保留顺序、开关和中文名称") {
            let url = root.appendingPathComponent("settings.json")
            var config = Configuration()
            config.menuItems.reverse(); config.menuItems[0].enabled = false
            config.favorites = [.init(name: "论文资料", path: "/tmp/中文 空格")]
            try ConfigurationStore.save(config, to: url)
            let restored = try ConfigurationStore.load(from: url)
            try expect(restored.menuItems[0].feature == config.menuItems[0].feature)
            try expect(!restored.menuItems[0].enabled)
            try expect(restored.favorites == config.favorites)
        }
        test("旧配置缺少功能项时自动补齐") {
            let url = root.appendingPathComponent("old-settings.json")
            var config = Configuration(); config.menuItems = [.init(feature: .paths, enabled: false)]
            try ConfigurationStore.save(config, to: url)
            let restored = try ConfigurationStore.load(from: url)
            try expect(restored.menuItems.count == MenuFeature.available.count)
            try expect(restored.menuItems.first?.feature == .paths && restored.menuItems.first?.enabled == false)
        }
        test("损坏和高版本配置不会被静默覆盖") {
            let url = root.appendingPathComponent("corrupt.json")
            try Data("broken".utf8).write(to: url)
            try expectThrows { _ = try ConfigurationStore.load(from: url) }
            try expect(try String(contentsOf: url, encoding: .utf8) == "broken")
            var config = Configuration(); config.schemaVersion = 2
            try ConfigurationStore.save(config, to: url)
            try expectThrows { _ = try ConfigurationStore.load(from: url) }
        }
        test("文字模板替换名称和日期") {
            let template = FileTemplate(id: "test", name: "test", fileExtension: "txt", content: "{{name}} {{date}}")
            let data = try FileOperations.templateData(template, name: "实验", resources: root)
            try expect(String(data: data, encoding: .utf8)?.hasPrefix("实验 20") == true)
        }
        test("导入模板保留二进制内容") {
            let directory = try folder("import")
            let bytes = Data([0, 255, 32, 0, 128])
            try bytes.write(to: directory.appendingPathComponent("test.bin"))
            let template = FileTemplate(id: "test", name: "test", fileExtension: "bin", importedFilename: "test.bin")
            let result = try FileOperations.templateData(template, name: "ignored", resources: root, importedDirectory: directory)
            try expect(result == bytes)
        }
        test("自定义模板路径不能穿越模板目录") {
            let template = FileTemplate(id: "x", name: "x", fileExtension: "txt", importedFilename: "../secret")
            try expectThrows { _ = try FileOperations.templateData(template, name: "x", resources: root) }
        }
        test("论文项目生成完整目录，重名时保留两份") {
            let directory = try folder("projects")
            let first = try FileOperations.createProject(in: directory, name: "论文", academic: true)
            let second = try FileOperations.createProject(in: directory, name: "论文", academic: true)
            try expect(second.lastPathComponent == "论文 2")
            for name in ["README.md", "data/.gitkeep", "manuscript/.gitkeep", "figures/.gitkeep"] {
                try expect(FileOperations.exists(first.appendingPathComponent(name)))
            }
        }
        test("扩展请求只消费一次") {
            let inbox = try folder("requests")
            let request = ActionRequest(action: .copyPaths, paths: ["/tmp/中文 a"])
            let url = try request.write(to: inbox)
            let decoded = try ActionRequest.consume(url, inbox: inbox)
            try expect(decoded.id == request.id && decoded.paths == request.paths)
            try expectThrows { _ = try ActionRequest.consume(url, inbox: inbox) }
        }
        test("拒绝从非扩展目录读取请求") {
            let inbox = try folder("trusted"), outside = try folder("untrusted")
            let url = try ActionRequest(action: .settings).write(to: outside)
            try expectThrows { _ = try ActionRequest.consume(url, inbox: inbox) }
        }
        test("拒绝过期请求和相对路径") {
            let inbox = try folder("expired")
            var request = ActionRequest(action: .settings)
            request.createdAt = Date(timeIntervalSinceNow: -300)
            let url = try request.write(to: inbox)
            try expectThrows { _ = try ActionRequest.consume(url, inbox: inbox) }
            try expectThrows { try ActionRequest(action: .copyPaths, paths: ["relative"]).validate() }
        }
        test("拒绝其他用户可写的请求") {
            let inbox = try folder("request-permissions")
            let url = try ActionRequest(action: .settings).write(to: inbox)
            try fm.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
            try expectThrows { _ = try ActionRequest.consume(url, inbox: inbox) }
        }
        test("拒绝通过符号链接跳出请求目录") {
            let inbox = try folder("request-link-inbox"), outside = try folder("request-link-outside")
            let original = try ActionRequest(action: .settings).write(to: outside)
            let link = inbox.appendingPathComponent(original.lastPathComponent)
            try fm.createSymbolicLink(at: link, withDestinationURL: original)
            try expectThrows { _ = try ActionRequest.consume(link, inbox: inbox) }
        }
        test("流式 SHA-256 与已知向量一致") {
            let url = try file("hash", in: root, text: "abc")
            try expect(try MediaTools.sha256(url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            try expectThrows { _ = try MediaTools.sha256(root) }
        }
        let imageDirectory = try folder("media")
        func makeImage() throws -> CGImage {
            guard let context = CGContext(data: nil, width: 2400, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw TestFailure(message: "测试图片创建失败")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
            context.textPosition = CGPoint(x: 180, y: 600)
            let text = NSAttributedString(string: "HELLO QINGYOU", attributes: [
                .font: NSFont.systemFont(ofSize: 130), .foregroundColor: NSColor.black
            ])
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            return context.makeImage()!
        }
        let image = try makeImage()
        let bitmap = NSBitmapImageRep(cgImage: image)
        let imageURL = imageDirectory.appendingPathComponent("input.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: imageURL)
        test("缩小图片保持比例，原图片不变") {
            let output = try MediaTools.image(imageURL, jpeg: false, resize: true)
            let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
            let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            try expect(decoded.width == 1920 && decoded.height == 960)
            try expect(FileOperations.exists(imageURL))
        }
        test("PNG 转 JPEG 后可解码") {
            let output = try MediaTools.image(imageURL, jpeg: true, resize: false)
            try expect(output.pathExtension == "jpg")
            try expect(CGImageSourceCreateWithURL(output as CFURL, nil) != nil)
        }
        test("非图片输入转换失败时不写出半成品") {
            let url = try file("invalid.png", in: imageDirectory, text: "not an image")
            try expectThrows { _ = try MediaTools.image(url, jpeg: false, resize: false) }
            try expect(!FileOperations.exists(imageDirectory.appendingPathComponent("invalid-converted.png")))
        }
        test("离线 OCR 能识别实际渲染的英文文字") {
            let result = try MediaTools.recognizeText(imageURL)
            let text = try String(contentsOf: result, encoding: .utf8)
            try expect(text.uppercased().contains("QINGYOU"), "OCR 结果：\(text)")
        }
        test("PDF 合并、排序、拆分结果可重新读取") {
            let pageImage = NSImage(cgImage: image, size: NSSize(width: 600, height: 300))
            for (name, count) in [("02.pdf", 2), ("01.pdf", 1)] {
                let doc = PDFDocument()
                for _ in 0..<count { doc.insert(PDFPage(image: pageImage)!, at: doc.pageCount) }
                try doc.dataRepresentation()!.write(to: imageDirectory.appendingPathComponent(name))
            }
            let sources = ["02.pdf", "01.pdf"].map { imageDirectory.appendingPathComponent($0) }
            let merged = try MediaTools.mergePDFs(sources, in: imageDirectory, filename: "merged.pdf")
            try expect(PDFDocument(url: merged)?.pageCount == 3)
            let split = try MediaTools.splitPDF(merged)
            for index in 1...3 {
                try expect(PDFDocument(url: split.appendingPathComponent(String(format: "%04d.pdf", index)))?.pageCount == 1)
            }
            try expect(sources.allSatisfy { FileOperations.exists($0) })
        }
        test("0.1 配置升级保留偏好，新增提示默认开启") {
            var old = Configuration()
            old.useSubmenu = false
            old.favorites = [.init(name: "自定义目录", path: root.path)]
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
            json.removeValue(forKey: "completionFeedback")
            let decoded = try JSONDecoder().decode(Configuration.self, from: JSONSerialization.data(withJSONObject: json))
            try expect(decoded.showsCompletionFeedback)
            try expect(!decoded.useSubmenu && decoded.favorites == old.favorites)
            var updated = decoded
            updated.completionFeedback = false
            let again = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(updated))
            try expect(!again.showsCompletionFeedback)
        }
        test("菜单预设不丢失模板、收藏和文件操作偏好") {
            var config = Configuration()
            config.templates[0].enabled = false
            config.collisionPolicy = .skip
            config.completionFeedback = false
            let favorites = config.favorites
            for preset in MenuPreset.allCases {
                preset.apply(to: &config)
                try expect(config.menuItems.filter(\.enabled).map(\.feature) == preset.features)
                try expect(Set(config.menuItems.map(\.feature)).count == MenuFeature.available.count)
                try expect(config.favorites == favorites && !config.templates[0].enabled)
                try expect(config.collisionPolicy == .skip && !config.showsCompletionFeedback)
            }
        }
        test("混选文件与目录时不提供图片、PDF 和校验工具") {
            let text = try file("profile.txt", in: root, text: "content")
            let selection = SelectionProfile([text, imageDirectory])
            try expect(!selection.allFiles && !selection.allFolders)
            try expect(ToolCommand.rename.accepts(selection))
            try expect(!ToolCommand.checksum.accepts(selection))
            try expect(!ToolCommand.png.accepts(selection) && !ToolCommand.mergePDF.accepts(selection))
        }
        test("扩展名像图片的文件夹不能作为图片处理") {
            let folder = try folder("fake.png")
            let profile = SelectionProfile([folder])
            try expect(profile.allFolders && !profile.allImages)
            try expect(!ToolCommand.ocr.accepts(profile))
        }
        test("空选择、单个 PDF 与多个 PDF 的工具可用性") {
            let empty = SelectionProfile([])
            try expect(ToolCommand.allCases.allSatisfy { !$0.accepts(empty) })
            let one = SelectionProfile([imageDirectory.appendingPathComponent("01.pdf")])
            try expect(ToolCommand.splitPDF.accepts(one) && !ToolCommand.mergePDF.accepts(one))
            let two = SelectionProfile(["01.pdf", "02.pdf"].map { imageDirectory.appendingPathComponent($0) })
            try expect(ToolCommand.mergePDF.accepts(two) && ToolCommand.checksum.accepts(two))
            try expect(!ToolCommand.jpeg.accepts(two))
        }
        test("图片工具识别有效本地文件，缺失文件不误报可用") {
            let profile = SelectionProfile([imageURL])
            try expect(ToolCommand.png.accepts(profile) && ToolCommand.ocr.accepts(profile))
            let missing = SelectionProfile([root.appendingPathComponent("missing.png")])
            try expect(!missing.allImages && !missing.allFiles)
        }
        test("精简菜单升级移除旧入口，保留现有顺序和关闭选择") {
            let url = root.appendingPathComponent("trimmed-menu.json")
            var config = Configuration()
            config.menuItems = [.init(feature: .rename, enabled: true), .init(feature: .paths, enabled: false),
                                .init(feature: .favorites, enabled: true), .init(feature: .project, enabled: true),
                                .init(feature: .checksum, enabled: true), .init(feature: .newFile, enabled: true)]
            try ConfigurationStore.save(config, to: url)
            let restored = try ConfigurationStore.load(from: url)
            try expect(restored.menuItems.first?.feature == .paths && restored.menuItems.first?.enabled == false)
            try expect(!restored.menuItems.contains { [.rename, .favorites, .project, .checksum].contains($0.feature) })
            try expect(restored.menuItems.count == MenuFeature.available.count)
        }
        test("新增旧版文档模板仅迁移一次，并保留自定义名称和禁用状态") {
            let url = root.appendingPathComponent("new-formats.json")
            var config = Configuration()
            config.templates.removeAll { ["doc", "xls", "ppt"].contains($0.id) }
            let word = config.templates.firstIndex { $0.id == "docx" }!
            config.templates[word].name = "我的工作文档"
            config.templates[word].enabled = false
            try ConfigurationStore.save(config, to: url)
            let restored = try ConfigurationStore.load(from: url)
            try expect(restored.templates.first { $0.id == "docx" }?.name == "我的工作文档")
            try expect(restored.templates.first { $0.id == "docx" }?.enabled == false)
            try expect(["doc", "xls", "ppt"].allSatisfy { id in restored.templates.contains { $0.id == id } })
            try ConfigurationStore.save(restored, to: url)
            let twice = try ConfigurationStore.load(from: url)
            try expect(twice.templates == restored.templates)
        }
        test("六种内置文档模板复制后保留真实文件格式") {
            let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
            let destination = try folder("office-templates")
            for template in FileTemplate.defaults where ["doc", "docx", "xls", "xlsx", "ppt", "pptx"].contains(template.id) {
                let data = try FileOperations.templateData(template, name: "未命名", resources: resources)
                let expected: [UInt8] = ["doc", "xls", "ppt"].contains(template.id)
                    ? [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1] : [0x50, 0x4b, 0x03, 0x04]
                try expect(data.starts(with: expected))
                let output = try FileOperations.createFile(in: destination, filename: "未命名." + template.fileExtension, data: data)
                try expect(try Data(contentsOf: output) == data)
            }
        }
        func labelledPDF(_ name: String, _ labels: [String]) throws -> URL {
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 420, height: 594)
            let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
            for label in labels {
                context.beginPDFPage(nil)
                context.textPosition = CGPoint(x: 40, y: 500)
                CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 28)])), context)
                context.endPDFPage()
            }
            context.closePDF()
            let url = imageDirectory.appendingPathComponent(name)
            try (data as Data).write(to: url)
            return url
        }
        test("PDF 页码支持范围、组合、中文逗号与明确的页面顺序") {
            try expect(try PDFOperations.pages("1-3，5", count: 6) == [0,1,2,4])
            try expect(try PDFOperations.pages("5,1–2", count: 6) == [4,0,1])
            try expect(try PDFOperations.pages(" 2 ", count: 6) == [1])
        }
        test("PDF 页码拒绝空输入、越界、逆序、重复和溢出") {
            for value in ["", "0", "7", "3-2", "1-3,2", "1,", "-2", "1--2", "99999999999999999999999999999999", "1-999999999"] {
                try expectThrows { _ = try PDFOperations.pages(value, count: 6) }
            }
        }
        test("PDF 合并保留用户顺序并且不覆盖现有合并文件") {
            let first = try labelledPDF("z.pdf", ["Z-FIRST", "Z-SECOND"])
            let second = try labelledPDF("a.pdf", ["A-FIRST"])
            let output = try PDFOperations.merge([first, second], in: imageDirectory)
            let document = PDFDocument(url: output)!
            try expect(document.pageCount == 3)
            try expect(document.page(at: 0)?.string?.contains("Z-FIRST") == true)
            try expect(document.page(at: 2)?.string?.contains("A-FIRST") == true)
            let again = try PDFOperations.merge([second, first], in: imageDirectory)
            try expect(again != output && FileOperations.exists(output))
            try expect(PDFDocument(url: again)?.page(at: 0)?.string?.contains("A-FIRST") == true)
        }
        test("PDF 拆分按指定页面组合导出到原目录并保留原件") {
            let source = try labelledPDF("range-source.pdf", ["PAGE-ONE", "PAGE-TWO", "PAGE-THREE", "PAGE-FOUR"])
            let original = try Data(contentsOf: source)
            let outputs = try PDFOperations.split(source, parts: [.init(pages: "1-2"), .init(pages: "4", name: "附录")], in: imageDirectory)
            try expect(outputs.count == 2 && outputs.allSatisfy { $0.deletingLastPathComponent().path == imageDirectory.path }, "结果数量或目录不正确")
            try expect(outputs[0].lastPathComponent == "range-source-第1-2页.pdf", "默认名称不正确")
            try expect(outputs[1].lastPathComponent == "附录.pdf", "自定义名称不正确")
            try expect(PDFDocument(url: outputs[0])?.pageCount == 2, "拆分页数不正确")
            try expect(PDFDocument(url: outputs[1])?.page(at: 0)?.string?.contains("PAGE-FOUR") == true, "拆分页面内容不正确")
            try expect(try Data(contentsOf: source) == original)
        }
        test("PDF 拆分遇到重名时保留两份，后续范围错误时不落下部分结果") {
            let source = imageDirectory.appendingPathComponent("range-source.pdf")
            let original = try Data(contentsOf: imageDirectory.appendingPathComponent("附录.pdf"))
            let duplicate = try PDFOperations.split(source, parts: [.init(pages: "1", name: "附录")], in: imageDirectory)
            try expect(duplicate[0].lastPathComponent == "附录 2.pdf")
            try expect(try Data(contentsOf: imageDirectory.appendingPathComponent("附录.pdf")) == original)
            let before = try fm.contentsOfDirectory(atPath: imageDirectory.path).sorted()
            try expectThrows { _ = try PDFOperations.split(source, parts: [.init(pages: "1"), .init(pages: "100")], in: imageDirectory) }
            try expect(try fm.contentsOfDirectory(atPath: imageDirectory.path).sorted() == before)
        }
        test("PDF 无效输入和非法结果名称不生成输出") {
            let invalid = try file("broken.pdf", in: imageDirectory, text: "broken")
            let before = try fm.contentsOfDirectory(atPath: imageDirectory.path).sorted()
            try expectThrows { _ = try PDFOperations.merge([imageDirectory.appendingPathComponent("z.pdf"), invalid], in: imageDirectory) }
            try expectThrows { _ = try PDFOperations.split(imageDirectory.appendingPathComponent("z.pdf"), parts: [.init(pages: "1", name: "../escape")], in: imageDirectory) }
            try expect(try fm.contentsOfDirectory(atPath: imageDirectory.path).sorted() == before)
        }
        print("\n测试结果：\(passed) 项通过，\(failures.count) 项失败。")
        if !failures.isEmpty { exit(1) }
    }
}
