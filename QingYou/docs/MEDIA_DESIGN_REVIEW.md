# 媒体工具扩展设计复查

日期：2026-10-26。结论：本轮是既有 macOS 产品的普通功能扩展，继续使用用户已确认的视觉系统；没有建立新视觉方向，也不新增全局设计 token。

## Overview

复查依据为 [DESIGN.md](../DESIGN.md)、[PRODUCT.md](../PRODUCT.md)、[MEDIA_WORKSPACES.md](MEDIA_WORKSPACES.md)，以及以下实际实现：

- `Sources/App/UtilityWorkspaceViews.swift`
- `Sources/App/UtilityOrderList.swift`
- `Sources/App/ImageWorkspaceView.swift`
- `Sources/App/PDFStudioView.swift`
- `Sources/App/EntryPoint.swift`
- `Sources/App/DesignSystem.swift`

用户冻结的世界是 macOS 原生效率软件：系统字体、真实 NSWindow 交通灯、浅灰白平面、系统蓝与细边框，无装饰渐变和大阴影。新窗口接续这一世界；Finder 直达一次文件任务，不把主程序的固定导航侧栏或首页组合复制到每个工具窗口。剪贴板生成文件沿用静默落盘与 Finder 命名流程，不为没有参数的任务增加窗口。

本复查仅写入这份记录，未修改 `DESIGN.md`、`.impeccable/design.json`、`PRODUCT.md` 或业务源码。后续复查覆盖顺序列表的命中处理修正，仍无新布局 token 或视觉方向。原生平台不适用 HTML/CSS detector，没有新视觉 comp；sidecar 中的 HTML/CSS 也不能替代 SwiftUI / AppKit 的运行时证据。

## Colors

图片与 PDF 工作台均复用 `QingYouStyle.canvas`、`surface`、`accent` 和 `border`，对应现有明暗映射。参数栏和原生列表使用 `NSColor.controlBackgroundColor`，预览底部使用 `NSColor.underPageBackgroundColor`，由系统适配外观。正文与说明继续使用 `.primary` / `.secondary`；数字尺寸、比例或文件大小按需要使用等宽数字。

明确的文档差异：`UtilityWorkspaceViews.swift:34` 和 `ImageWorkspaceView.swift:194` 的错误信息使用系统 `.red`；既有 `DESIGN.md` 的 Status 段仍描述错误与警示沿用 `.orange`。这是本轮局部实现与既有说明的差异，记录但不顺便修复，也不将红色扩展为新的全局状态色规则。错误同时通过文字、无效预览和禁用确认动作表达，不只依赖颜色。

## Typography

全部使用 `Font.system`、AppKit `systemFont` 或系统语义字号，没有引入展示字体、网页字体或自定义字距。正文以 13 pt 为主；预览标题为 13 pt 中等字重，辅助文字为 11–12 pt，符合现有桌面密度。

`UtilityHeader` 的标题为 21 pt 半粗体，不同于主程序页面标题的 22 pt；它是独立工具窗口的局部层级。原生列表标题为 12 pt 中等字重、补充标签为 10 pt，属于缩略图列表的紧凑呈现，不能据此下调通用 caption 规范。此记录不添加全局字号、固定行高或新的字体 ramp。

## Layout

两个工作台都复用“标题—分隔线—左右分栏—分隔线—固定底栏”的结构。左侧组织参数或顺序列表，右侧呈现原文与结果；参数区和列表可独立滚动，底部保留保存位置、取消与确认。图片尺寸使用上下对照，PDF 压缩使用左右对照；这是任务对比方式，不是全局页面模板。

以下均为当前桌面组件的实际局部数值，单位为逻辑点（pt），不是屏幕像素或全局 token：

| 局部对象 | 代码中的数值 | 用途与边界 |
| --- | --- | --- |
| 工具标题区 | 水平 24、垂直 18；图标占位 28；图文间距 12 | 保持桌面窗口标题与说明的层级 |
| 参数区 | 内边距 20；主要组间距 18 | 承载原生表单；组内仍依内容使用 8–12 等间距 |
| 预览区 | 外边距 16；预览头内边距 12；图片内边距 18 | 保留原文与结果的阅读空间 |
| 底栏 | 水平 22、垂直 16；动作间距 12 | 路径中间截断并提供完整路径提示，主动作固定可达 |
| 图片参数栏 | 最小 270、理想 300、最大 350 | 不替代主程序的固定 220 pt 导航侧栏 |
| PDF 参数栏 | 最小 280、理想 310、最大 360 | 压缩模式右侧保留双预览空间 |
| 顺序列表 | 紧凑行高 42、页面行高 72；操作图标按钮宽 19 | 原生列表的任务密度，不作为全局控件最小尺寸 |
| 文字结果区 | 内边距 14、最大高度 180 | 已有文字可选中，区域独立滚动 |

`EntryPoint.showUtility` 创建带 `.titled`、`.closable`、`.miniaturizable`、`.resizable` 的真实 NSWindow，采用透明标题栏和 `.unifiedCompact`。常规窗口首次内容尺寸为 1080 × 780，压缩窗口为 1200 × 780；NSWindow 最小尺寸分别为 900 × 700 和 1040 × 700。SwiftUI 内容最小尺寸为 880 × 650，压缩为 1020 × 650；窗口边界由 NSWindow 管理，不把两组尺寸混称同一个规范。

## Elevation & Depth

指定新视图没有渐变、装饰阴影或悬停位移。层级依靠画布与内容的灰度、1 pt 预览边界、原生 Divider、系统列表选中及 PDFKit 页面环境形成。原生 NSWindow / PDFKit 自身的系统呈现不属于自绘装饰阴影，也不应为套用网页式禁令而删除。

## Shapes

新预览平面使用矩形 1 pt 边界，不强制套用首页卡片的 12 pt 圆角。它们是展示文件内容的工作区域，和原生分栏、列表、PDF 页面一起形成连续平面；此局部做法不改写既有 `Surface` 的圆角规则。按钮、输入框、菜单、焦点和系统窗口控制继续由 macOS 原生控件管理。

## Components

| 复用对象 | 已实现的作用 | 系统关系 |
| --- | --- | --- |
| `UtilityHeader` | 标题、说明、SF Symbol、预览更新进度 | 图片与 PDF 共用，无新品牌标语 |
| `UtilityFooter` | 保存副本说明、目录、处理状态、取消及默认确认 | 共用原生按钮与键盘快捷行为；信息窗口用简化底栏 |
| `UtilityImagePane` / `UtilityPDFPane` | 预览标题、尺寸或文件名、空态、原生内容预览 | 复用现有表面色与边界；PDF 使用 PDFKit |
| `UtilityOrderList` | 单选、系统选中样式、缩略图、箭头、旋转、移除及内部拖动 | 图片合成 PDF 和页面整理共用 NSTableView，按钮各有可访问性名称与提示 |
| 原生表单控件 | Button、Picker、Toggle、TextField、Slider | 继续使用系统焦点和状态；无需为外观一致强制改用 `SoftActionStyle` |

处理时左侧参数区禁用，确认按钮进入处理状态，取消保留独立动作；错误行允许换行。预览准备状态与真实导出状态分开表达。图片信息字段可选取，缺失或未记录的信息不作推测；OCR 文案明确当前为已有文字预览，识别在需要时进行。以上属于本任务的状态语义，不扩展成新全局视觉组件。

后续源码复查确认 `UtilityOrderCell` 沿用既有 `PDFOrderCell` 的命中处理：`textField` 指向标题，行内标签不可选择文字，非按钮区域由单元格承接选中与拖放；命中按钮及其子视图时保留原始目标。此修正只明确事件归属，不改变列表外观或上述局部数值，也不能单凭实现推断桌面拖动已经成功。

### 复查证据与限制

- 先前由独立 reviewer 逐一打开并通过视觉检查的 11 种状态，现已在 Mac 解锁后使用当前构建刷新同路径截图。浅色文件为 `build/media-review/resize-light.png`、`info-light.png`、`images-pdf-light.png`、`compress-light.png`、`organize-light.png`、`export-light.png`、`text-light.png`；紧凑／深色／错误文件为 `resize-compact-dark.png`、`organize-compact-dark.png`、`text-dark.png`、`resize-error-dark.png`，均位于同一目录。
- 当前截图已改为 1x：常规窗口图像为 1080 × 812 像素（内容 1080 × 780 pt），压缩为 1200 × 812，两个紧凑窗口为 900 × 732。本次读取全部 11 张 PNG 的尺寸确认该批次，不再将此前的 2x 图像作为当前尺寸证据。截图外框包含系统标题栏，不能把 812 / 732 像素直接写成内容高度或新的最小窗口 token。本记录没有重新操作 UI 或重新逐图进行视觉验收，也不把截图当作导出内容或文件兼容性证明。
- 新顺序列表的箭头排序及 PDF 预览同步已重新确认；原生拖动接口、命中处理、插入位置映射与模型测试有证据。命中修正后的桌面拖动尝试仍未观察到顺序改变，**完整桌面拖动未通过实测**。不能借用旧 PDF 合并窗口的拖动成功记录来证明新列表。
- 当前 `build/workspace-test-results.log` 记录重跑工作台检查 17 项通过、0 项失败；生产构建与严格签名通过由父任务确认。“原格式禁止静默转换”和“PDF 页面图片按导出顺序命名”是行为真值修复，继承同一界面方向。完整测试范围以 [VERIFICATION.md](VERIFICATION.md) 和对应构建日志为准；本复查读取结果，未重新运行测试或签名检查。
- 截图来自隔离的本地预览应用。真实 Finder 新入口与最终安装检查由父任务另行记录，本设计文档不提前认证。没有以本次复查声称扫描页 OCR 准确率、全部键盘／辅助功能组合或完整安装链路已经验收。

## Do's and Don'ts

- **Do** 保持既有系统字体、语义色、真实窗口控制和原生焦点；优先复用本轮已经共用的标题、底栏、预览与顺序列表。
- **Do** 将原文／结果、参数、确认状态组织成一次文件任务；按实际窗口尺寸滚动，保留副本与明确失败说明。
- **Don't** 将标题 21 pt、列表 10 pt 补充标签、22 pt 底栏边距或矩形预览边界写成全局 token；不把任务布局变成所有窗口的模板。
- **Don't** 为消除文档差异而回写 `DESIGN.md`、sidecar 或源码；本轮只记录错误色差异，不将其规范化为未来组件必须继承的规则。
- **Don't** 将未观察成功的桌面拖动、静态预览或现有文字测试表述为完整交互、实际导出或 OCR 准确率的验收。
