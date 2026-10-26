import AppKit

enum TerminalService {
    static func open(_ directory: URL, perform: (String, NSPasteboard) -> Bool = { NSPerformService($0, $1) }) throws {
        try FileOperations.requireDirectory(directory)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        // Terminal 自带的“新建位于文件夹位置的终端窗口”服务接受纯路径，
        // 不把目录作为待执行文件打开，也不拼接任何 shell 命令。
        board.setString(directory.path, forType: .string)
        board.writeObjects([directory as NSURL])
        let bundle = Bundle(path: "/System/Applications/Utilities/Terminal.app")
        let title = bundle?.localizedString(forKey: "New Terminal at Folder", value: nil, table: "ServicesMenu") ?? "New Terminal at Folder"
        guard perform(title, board) else {
            throw FileOperationError.message("系统的“新建位于文件夹位置的终端窗口”服务暂不可用。请在系统设置 → 键盘 → 键盘快捷键 → 服务中启用它，再重试。")
        }
    }
}
