# 架构与开发约定

## 三层职责

主程序是独立发布的非沙盒 Mac 应用，使用 SwiftUI 展示设置、AppKit 接收文件打开事件。
Finder 扩展是沙盒进程，只构建菜单和投递任务，不执行复制、转换或 OCR。
Core 层不依赖界面；文件操作与重命名可以在临时目录中独立测试。

普通文件任务采用串行后台队列；独立图片／PDF 工作台各自维护后台预览和导出队列。配置与可观察界面状态只在主线程修改，完成结果回主线程记录和展示，主程序汇总实际导出任务数量。
退出时如有任务正在执行，会提示等待任务完成。

## 扩展和主程序如何通信

1. 在 menu(for:) 中获取当前选择与目标目录，按文件类型构造适用菜单。
2. 菜单项使用 tag 对应不可变操作快照，避免之后选择变化影响原操作。
3. 点击菜单时，扩展在自身 Application Support/QingYou/Requests 写入 JSON 请求。
4. 文件权限为 0600，包含 UUID、创建时间、动作、文件路径与必要参数。
5. 使用 NSWorkspace 将请求文件交给同一 bundle 内的主程序。
6. 主程序检查请求目录、文件所有者、权限、大小、UUID 和 120 秒有效期；消费后移除请求文件。

不提供远程 URL scheme 执行文件操作的接口。配置中的应用、模板和收藏通过内部 ID 查找，
不把请求参数拼接为 shell 命令。终端打开调用 NSPerformService，使用 Terminal 本地化的文件夹服务与独立 NSPasteboard；不把文件夹作为可执行文件交给 Terminal。

扩展通过精确指向 Library/Application Support/QingYou/ 的只读沙盒例外读取配置，
不依赖 App Groups 或收费开发者账号。配置变更使用无载荷分布式通知刷新；
每次构造菜单也重新读取配置。该设计面向 GitHub 独立分发，不宣称已符合 Mac App Store 审核要求。

## 文件操作约定

- 所有文件名先校验，拒绝路径分隔符、空字符、空名及过长名称。
- 写入新文件使用不覆盖模式；复制先写入隐藏中间项，完成后提交最终名称。
- 移动使用 FileManager，失败结果单独汇报。跨卷行为还需要在实际外接盘补测。
- 同时选中父目录和子项时去重；解析目标符号链接，避免复制进自身。
- 复制符号链接时保留链接本身，不展开链接目标。
- 批量重命名先校验所有目标，再将原文件暂存为唯一名称，最后提交，支持名称交换。
- 失败时尝试回退；回退失败会给出残留文件路径，不把部分失败报告为成功。
- 撤销之前核对文件设备号与 inode，避免把路径上后来替换的新文件当成原文件移动。
- 当前版本不提供覆盖重名文件、永久删除、文件上传或任意脚本执行。

## 新增功能

1. 给 ActionKind 添加动作，并在主程序 Actions.swift 中实现处理。
2. 如需新功能组，更新 MenuFeature 和 Finder 菜单构造；旧配置会在末尾补充新组。
3. 文件基础算法放进 Core；媒体算法放在 MediaTools、ImageProcessing 或 PDFStudioOperations，界面只收集参数和展示结果。
4. 测试必须操作独立临时目录，不使用开发者桌面或文稿作为测试数据。
5. 同步修改使用说明，明确结果保存位置、原文件是否保留、失败如何处理。

## 资源与可复现构建

应用没有第三方运行时。图标通过 scripts/generate_icon.swift 绘制；
Office 模板通过 scripts/generate_templates.py 独立生成后随仓库分发。
模板生成工具需要 python-docx、openpyxl、python-pptx 和 xlwt，日常构建无需安装这些包。
发布构建可使用 ARCHS 指定架构；本地签名和 Developer ID 签名使用同一组代码。

## 0.2 原生界面与交互

- SettingsView 使用 NavigationSplitView / toolbar / searchable，品牌导航由普通可聚焦按钮构成；DesignSystem 集中管理配色、材质与轻量交互；当前外壳使用灰白、系统蓝和细边界。
- ToolCatalog 定义工具展示、动作和适用条件；SelectionProfile 被 Finder 菜单和工具箱共同使用。
- 文件拖放只接受本地 file URL，最多 1,000 项；等待全部项目解析成功后替换待处理列表，不自动运行工具。
- RenamePreview 在专用串行队列上生成、检查预览，输入后延迟 180 ms 合并；通过请求代号忽略过期结果。
- 预览生成期间与名称冲突时，提交按钮禁用；真正执行仍经过 RenameEngine 的再次校验。
- CompletionFeedback 使用 nonactivatingPanel，不调用应用激活；提示 7 秒自动关闭，悬停暂停。
- 完成面板关闭后，结果仍在主窗口与操作记录中；界面动画读取 Reduce Motion，面板材质读取 Reduce Transparency。
- completionFeedback 为可选配置字段，旧 JSON 缺少该字段时采用开启默认值，不提升配置 schema 或重置个人数据。

精简菜单通过 MenuFeature.available 和 ToolCommand.available 统一限制入口；旧枚举保留以便读取历史配置。DOC 使用系统 textutil 转换，XLS 使用 xlwt 生成，PPT 由桌面演示软件另存为 97–2003 格式后随源码提交。新建办公文档调用文件级默认应用 API 关联 WPS，不改全局文件类型关联。

## PDF 工作台

PDFOperations 独立负责范围解析、页复制、按界面顺序合并和结果落盘。拆分先校验所有范围与文件名，在当前目录的隐藏临时文件夹中生成全部结果，再逐一提交；提交失败时仅回退自己创建且身份一致的输出。

PDFWorkspaceModel 使用独立串行后台队列读取文件、生成缩略图和结果预览。输入延迟 180 ms 合并，通过代号丢弃过期任务。PDFKit 对象在后台构造完成后才交给 PDFView，后台不修改已显示实例。

PDFWorkspaceView 使用原生分栏与 PDFKit 预览；PDFThumbnailView 自带滚动，不套嵌第二层滚动容器。合并使用 NSTableView 的原生插入式拖动和箭头排序，拆分支持多组范围与可选文件名。文档名称标签不接受文字选择，鼠标事件交给整行处理；拆分输入框焦点与预览选择保持同步，实时显示预计文件名。导出期间禁用编辑与关闭，并计入主程序正在处理的任务。完成后关闭工作台、静默记录，再交给 Finder 选中结果。

原生表格拖放接入参考 [Apple 的 NSTableView 示例](https://developer.apple.com/documentation/appkit/supporting-table-view-drag-and-drop-through-file-promises)。只接受当前列表发起的内部排序，拖放内容为文档标识，不移动原 PDF。

## 系统窗口关闭行为

菜单栏的「文件 → 关闭窗口」使用 nil target 的 performClose:，由 Cocoa 响应链找到当前窗口。这样文本编辑器、PDFView 获得焦点时也沿用 ⌘W，不注册全局按键监听或自己派发键盘事件。窗口 delegate 的关闭保护仍会执行。

窗口关闭时，先移除对应模型，再检查除正在关闭窗口外是否还有可见的主窗口、PDF 窗口或兼容重命名窗口。只在最后一扇窗口关闭时切回菜单栏驻留模式。


## 图片与 PDF 独立工作台（2026-10-26）

- FinderSync 生成不可变请求，Actions 识别适用选区或调起系统选择器；EntryPoint 创建独立 NSWindow，不依赖先打开设置主页。
- ImageWorkspaceModel 管理 resize／information／pdf；PDFStudioModel 管理 compress／organize／images／text。预览有独立串行队列、代次和取消令牌，旧结果不覆盖最新参数。
- ImageProcessing 使用 ImageIO 读取实际类型、方向与元数据，先下采样再渲染，预览与导出共用格式选择规则。多帧输入不静默丢帧，去除位置不删除无关版权。
- PDFStudioOperations 使用 PDFKit 保留页面内容；系统图片优化要求 macOS 13.4+，不栅格化整份 PDF。图片导出使用范围顺序前缀；文字先读现有文字层，仅在需要时使用 Vision。
- UtilityOrderList 是共用 NSTableView，按钮语义与非按钮行命中分开。新列表箭头实测通过，桌面拖动尚未验证；不得混用原合并列表的历史证据。
- LocalWorkState 处理忙碌、进度、取消、错误及关闭请求；LocalOutputs 在当前目录暂存、提交，同名自动编号，失败只撤回本次身份一致的输出。
- ClipboardFile 在主线程抓取剪贴板内容快照，后台落盘；已有 file URL 继续走文件粘贴，独立剪贴板测试不改全局剪贴板。
- 新窗口使用 UtilityHeader／Footer、图片预览和原有 NativePDFPreview。工具 PDF 按整页查看，旧合并／拆分连续浏览模式保持兼容。

设计规则见 [DESIGN.md](../DESIGN.md)，任务合约见 [MEDIA_WORKSPACES.md](MEDIA_WORKSPACES.md)，验证事实见 [VERIFICATION.md](VERIFICATION.md)。
