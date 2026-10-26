import Foundation

/// 后台任务只读取这个令牌；取消后不再把暂存结果提交到用户目录。
final class WorkCancellation {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

enum LocalOutputs {
    static func staged(in directory: URL, cancellation: WorkCancellation,
                       build: (URL) throws -> [(URL, String)]) throws -> [URL] {
        try FileOperations.requireDirectory(directory)
        let fm = FileManager.default
        let staging = directory.appendingPathComponent(".qingyou-work-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let plan = try build(staging)
        try cancellation.check()
        var committed: [(URL, FileIdentity)] = []
        do {
            for (source, name) in plan {
                try cancellation.check()
                try FileOperations.validateFilename(name)
                let identity = try FileIdentity.read(source)
                let target = try FileOperations.availableURL(in: directory, filename: name)
                try fm.moveItem(at: source, to: target)
                committed.append((target, identity))
            }
        } catch {
            // 只撤回本次创建且身份未变的文件，不碰用户随后替换的内容。
            for (url, identity) in committed where (try? FileIdentity.read(url)) == identity { try? fm.removeItem(at: url) }
            throw error
        }
        return committed.map(\.0)
    }
}
